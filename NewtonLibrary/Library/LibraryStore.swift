import AppKit
import CryptoKit
import Foundation

/// The library: the packages in the database, and everything you can do to them.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var items: [LibraryItem] = [] {
        // (what's worked out from them is worked out again when it's next wanted)
        didSet { derived = Derived() }
    }
    /// A short report on the last thing done (e.g. "Added 3 packages."), shown under the list.
    @Published var message: String?
    @Published private(set) var isBusy = false
    /// While several files are being added: what the progress sheet shows.
    @Published private(set) var addProgress: AddProgress?
    /// The packages selected in the list.
    @Published var selection = Set<Int64>()
    /// The sidebar choice and the search text.
    @Published var filter: LibraryFilter = .all
    @Published var search = ""
    /// The versions in the sidebar's "Runs on" row (remembered between launches).
    @Published var runsOnFrom = UserDefaults.standard.string(forKey: "RunsOnFrom") ?? "2.0" {
        didSet { UserDefaults.standard.set(runsOnFrom, forKey: "RunsOnFrom") }
    }
    @Published var runsOnTo = UserDefaults.standard.string(forKey: "RunsOnTo") ?? "2.1" {
        didSet { UserDefaults.standard.set(runsOnTo, forKey: "RunsOnTo") }
    }
    /// Which packages belong together (see Relations).
    @Published private(set) var relations = Relations() {
        didSet { derived.addOns = nil }
    }
    /// The package whose Info window is open, if any.
    @Published var infoWindow: InfoRequest?
    @Published private(set) var databaseError: String?

    private var db: LibraryDatabase?

    private init() {
        do {
            let db = try LibraryDatabase.openDefault()
            self.db = db
            items = try db.allItems()
            // Note missing files and tidy their empty folders, quietly
            markMissing()
            tidyFolders(of: items.filter(\.isMissing))
            refreshRelations()
            // Packages read by an older version of the app lack some details
            // (such as the minimum and maximum Newton OS): read them again
            if items.contains(where: { ($0.info.readerVersion ?? 0) < PackageReader.version }) {
                DispatchQueue.main.async { self.rereadAll() }
            }
        } catch {
            databaseError = error.localizedDescription
        }
    }

    /// The publishers in the library (of packages whose files are there), grouped by key, each shown by its most
    /// common spelling.
    var publishers: [(key: String, name: String)] {
        if let publishers = derived.publishers { return publishers }
        var spellings: [String: [String: Int]] = [:]
        for item in items where !item.isMissing {
            spellings[item.publisherKey, default: [:]][item.publisher, default: 0] += 1
        }
        let publishers = spellings.map { key, names in
            (key: key, name: names.max { $0.value < $1.value || $0.value == $1.value && $0.key.count < $1.key.count }?.key ?? key)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        derived.publishers = publishers
        return publishers
    }

    /// The kinds you've named yourself, in alphabetical order.
    var customKinds: [String] {
        if let kinds = derived.customKinds { return kinds }
        let kinds = Array(Set(items.compactMap(\.customKind)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        derived.customKinds = kinds
        return kinds
    }

    /// How many packages a sidebar choice shows. All of them are counted in one
    /// go, and kept until the library changes: the sidebar asks again every
    /// time anything changes, even the selection.
    func count(_ filter: LibraryFilter) -> Int {
        if case .runsOn(let from, let to) = filter {
            let key = from + "\u{1F}" + to
            if let count = derived.runsOn[key] { return count }
            let count = items.filter(filter.includes).count
            derived.runsOn[key] = count
            return count
        }
        if derived.counts == nil {
            var counts: [LibraryFilter: Int] = [:]
            let recent = Date().addingTimeInterval(-LibraryFilter.recentDays * 24 * 60 * 60)
            for item in items {
                if item.isMissing {
                    counts[.missing, default: 0] += 1
                    continue
                }
                counts[.all, default: 0] += 1
                if item.dateAdded > recent { counts[.recentlyAdded, default: 0] += 1 }
                counts[.os(item.os), default: 0] += 1
                counts[.kind(item.kindKey), default: 0] += 1
                counts[.publisher(item.publisherKey), default: 0] += 1
            }
            derived.counts = counts
        }
        return derived.counts?[filter] ?? 0
    }

    /// The packages the list shows: those the sidebar choice and the search
    /// include, sorted. Kept until any of those (or the library) changes, as the
    /// list is drawn again for every click.
    func visibleItems(sortedBy order: [KeyPathComparator<LibraryItem>]) -> [LibraryItem] {
        if let visible = derived.visible, visible.filter == filter, visible.search == search, visible.order == order {
            return visible.items
        }
        // The sidebar choice's packages, sorted, are kept too: searching only
        // takes some of them away, keeping the order (sorting takes longer
        // than searching, and the search changes with every letter typed)
        let sorted: [LibraryItem]
        if let all = derived.visible, all.filter == filter, all.search.isEmpty, all.order == order {
            sorted = all.items
        } else if let all = derived.sorted, all.filter == filter, all.order == order {
            sorted = all.items
        } else {
            sorted = items.filter { filter.includes($0) }.sorted(using: order)
        }
        derived.sorted = Visible(filter: filter, search: "", order: order, items: sorted)
        var shown = sorted
        if !search.isEmpty {
            // (each package's text is folded once, then kept until the library changes)
            if derived.searchText == nil {
                derived.searchText = Dictionary(items.map { ($0.id, $0.searchText) }, uniquingKeysWith: { a, _ in a })
            }
            let texts = derived.searchText!, wanted = LibraryItem.folded(search)
            shown = sorted.filter { texts[$0.id]?.range(of: wanted, options: .literal) != nil }
        }
        derived.visible = Visible(filter: filter, search: search, order: order, items: shown)
        return shown
    }

    private struct Visible {
        var filter: LibraryFilter
        var search: String
        var order: [KeyPathComparator<LibraryItem>]
        var items: [LibraryItem]
    }

    /// What's worked out from the items, kept until they change.
    private struct Derived {
        var visible: Visible?
        /// The sidebar choice's packages, sorted, before searching.
        var sorted: Visible?
        var counts: [LibraryFilter: Int]?
        var runsOn: [String: Int] = [:]
        var publishers: [(key: String, name: String)]?
        var customKinds: [String]?
        /// Each item's place in `items`, by ID.
        var index: [Int64: Int]?
        /// Each package's add-ons (one step), from `relations`.
        var addOns: [Int64: [Int64]]?
        /// The links found in the packages themselves, without your choices.
        var found: Relations?
        /// Each package's text for searching, by ID.
        var searchText: [Int64: String]?
        /// Every package, by title (for the Info window's Main package menu).
        var byTitle: [LibraryItem]?
    }
    private var derived = Derived()

    /// The window title for a sidebar choice.
    func title(for filter: LibraryFilter) -> String {
        if case .publisher(let key) = filter {
            let name = publishers.first { $0.key == key }?.name ?? key
            return name.isEmpty ? "No Developer" : name
        }
        return filter.title
    }

    // MARK: The library folder

    static let folderKey = "LibraryFolder"

    static var defaultFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return documents.appendingPathComponent("Newton Packages", isDirectory: true)
    }

    /// Where copies of added packages are kept (set in Preferences).
    var libraryFolder: URL {
        if let path = UserDefaults.standard.string(forKey: Self.folderKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return Self.defaultFolder
    }

    func setLibraryFolder(_ url: URL) {
        objectWillChange.send()
        UserDefaults.standard.set(url.path, forKey: Self.folderKey)
    }

    /// Whether a package's file is somewhere inside the library folder.
    func isInLibraryFolder(_ item: LibraryItem) -> Bool {
        Importer.isInside(item.fileURL, libraryFolder)
    }

    /// Where a package's file belongs: Library folder / Publisher / Kind / Title,
    /// or for an add-on, its main package's folder. When the library has
    /// different versions of the same package (the same publisher, kind and
    /// title), each version gets its own folder: "Title 1.1", "Title 1.2".
    func organizedFolder(for item: LibraryItem, publisherFolders: [String]? = nil,
                         versions: [String: Set<String>]? = nil) -> URL {
        var owner = item
        if let root = relations.root(of: item.id), let main = self.item(root) { owner = main }
        var title = owner.title
        let version = owner.version.trimmingCharacters(in: .whitespaces)
        if (versions ?? versionsByPackage())[Self.packageKey(owner)].map({ $0.count > 1 }) == true, !version.isEmpty,
           title.range(of: #"(^|\s)v?\#(NSRegularExpression.escapedPattern(for: version))$"#,
                       options: [.regularExpression, .caseInsensitive]) == nil {
            title += " " + version
        }
        return Importer.organizedFolder(root: libraryFolder, publisher: owner.publisher, kind: owner.kindLabel,
                                        title: title, publisherFolders: publisherFolders)
    }

    /// Packages count as the same one, in different versions, when they have the
    /// same publisher, kind and title.
    private static func packageKey(_ item: LibraryItem) -> String {
        [item.publisherKey, item.kindKey.lowercased(), item.title.lowercased()].joined(separator: "\u{1F}")
    }

    /// The versions in the library of each package (add-ons, which go in their
    /// main package's folder, aren't counted).
    private func versionsByPackage() -> [String: Set<String>] {
        var versions: [String: Set<String>] = [:]
        for item in items where relations.root(of: item.id) == nil {
            versions[Self.packageKey(item), default: []].insert(item.version.trimmingCharacters(in: .whitespaces).lowercased())
        }
        return versions
    }

    // MARK: Packages that belong together

    /// Works out which packages belong together, then applies the links you set
    /// yourself (Main package in Get Info).
    func refreshRelations() {
        var r = Relations.compute(items)
        derived.found = r
        let bySHA = Dictionary(items.map { ($0.sha256, $0.id) }, uniquingKeysWith: { a, _ in a })
        for item in items {
            guard let choice = item.mainPackageChoice else { continue }
            r.probable.remove(item.id)
            if let main = bySHA[choice], main != item.id {
                r.main[item.id] = main
            } else {
                r.main[item.id] = nil   // "" (or a package no longer here): stands alone
            }
        }
        relations = r
    }

    /// The package an item belongs to, if it's an add-on.
    func mainPackage(of item: LibraryItem) -> LibraryItem? {
        relations.main[item.id].flatMap { self.item($0) }
    }

    func addOns(of item: LibraryItem) -> [LibraryItem] {
        addOnIDs(of: item.id).compactMap { self.item($0) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The add-ons that belong to a package (one step). Worked out for all
    /// packages at once: the list asks for every row each time it's drawn.
    func addOnIDs(of id: Int64) -> [Int64] {
        if derived.addOns == nil {
            var addOns: [Int64: [Int64]] = [:]
            for (addOn, main) in relations.main { addOns[main, default: []].append(addOn) }
            for key in addOns.keys { addOns[key]!.sort() }
            derived.addOns = addOns
        }
        return derived.addOns?[id] ?? []
    }

    /// The links found in the packages themselves, without the main packages
    /// you chose in Get Info.
    var foundRelations: Relations {
        if let found = derived.found { return found }
        let found = Relations.compute(items)
        derived.found = found
        return found
    }

    /// Every package, sorted by title.
    var itemsByTitle: [LibraryItem] {
        if let sorted = derived.byTitle { return sorted }
        let sorted = items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        derived.byTitle = sorted
        return sorted
    }

    /// Selects a package in the list, showing all packages if it's filtered out.
    func select(_ id: Int64) {
        guard let item = item(id) else { return }
        if !filter.includes(item) { filter = item.isMissing ? .missing : .all }
        if !search.isEmpty && !item.matches(search) { search = "" }
        selection = [id]
    }

    /// Moves package files (inside the library folder) into their Publisher /
    /// Kind / Title folders, e.g. after their publisher, kind or title has
    /// changed, and removes folders left empty. Returns how many were moved.
    @discardableResult
    func organize(_ ids: Set<Int64>) -> Int {
        let root = libraryFolder
        var publisherFolders = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let versions = versionsByPackage()
        var moved = 0
        var newPaths: [Int64: String] = [:]
        defer { setFilePaths(newPaths) }
        for item in items where ids.contains(item.id) && isInLibraryFolder(item) {
            let target = organizedFolder(for: item, publisherFolders: publisherFolders, versions: versions)
            let current = item.fileURL.deletingLastPathComponent()
            guard current.standardizedFileURL.path != target.standardizedFileURL.path,
                  FileManager.default.fileExists(atPath: item.filePath) else { continue }
            do {
                let destination = try Importer.move(item.fileURL, into: target, named: item.originalName)
                newPaths[item.id] = destination.path
                Importer.removeEmptyFolders(from: current, upTo: root)
                moved += 1
                // A publisher folder it made (listing the library folder again
                // after every move was slow; a folder that's since gone is
                // passed over, as organizedFolder checks it's there)
                if destination.path.hasPrefix(root.path + "/"),
                   let top = destination.path.dropFirst(root.path.count + 1).split(separator: "/").first.map(String.init) {
                    if !publisherFolders.contains(top) { publisherFolders.append(top) }
                } else {
                    publisherFolders = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
                }
            } catch {
                message = "Couldn't move \(item.originalName): \(error.localizedDescription)"
            }
        }
        return moved
    }

    // MARK: Missing files

    /// Notes which packages' files can't be found (and which have come back).
    private func markMissing() {
        // (changed in a copy, then put back once: changing `items` one package
        // at a time copies the whole list each time)
        var updated = items
        for index in updated.indices {
            updated[index].isMissing = !FileManager.default.fileExists(atPath: updated[index].filePath)
        }
        items = updated
    }

    /// Removes the folders in the library folder that missing packages were in,
    /// if that leaves them empty (and the folders above them, up to the library folder).
    private func tidyFolders(of missing: [LibraryItem]) {
        let root = libraryFolder
        for item in missing {
            // From the nearest folder still there (the package's own may have gone too)
            var folder = item.fileURL.deletingLastPathComponent()
            while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
                folder = folder.deletingLastPathComponent()
            }
            if Importer.isInside(folder, root) {
                Importer.removeEmptyFolders(from: folder, upTo: root)
            }
        }
    }

    /// Library > Check for Missing Files: looks for every package's file. The
    /// missing ones are listed under Missing, and the folders in the library
    /// folder they were in are removed if that leaves them empty (and the folders
    /// above them, up to the library folder).
    func checkForMissingFiles() {
        let wasMissing = Set(items.filter(\.isMissing).map(\.id))
        markMissing()
        let missing = items.filter(\.isMissing)
        tidyFolders(of: missing)
        selection.subtract(missing.map(\.id))
        let back = wasMissing.subtracting(missing.map(\.id)).count
        if missing.isEmpty {
            if filter == .missing { filter = .all }
            message = "Every package's file is there."
        } else {
            filter = .missing
            message = (missing.count == 1 ? "1 package's file is missing." : "\(missing.count) packages' files are missing.")
                + " Add the file to the library again to put it back."
        }
        if back > 0 {
            message! += back == 1 ? " 1 that was missing is back." : " \(back) that were missing are back."
        }
    }

    /// Files every package in the library folder into Developer / Kind / Title folders.
    func organizeAll() {
        let moved = organize(Set(items.map(\.id)))
        message = moved == 0 ? "The library folder is already organized."
            : "Moved \(moved) package\(moved == 1 ? "" : "s") into Developer / Kind / Title folders."
    }

    // MARK: Adding packages

    /// Adds package files (or every package in the given folders): reads each one,
    /// copies it into the library folder and adds it to the database.
    /// Adding several at once (dropped together, or chosen together) shows a
    /// progress sheet, whose Cancel button stops it.
    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        // Files dropped while an add is going on are added after it
        if adding != nil {
            pendingAdds += urls
            return
        }
        let folder = libraryFolder
        // (A package whose file is missing can be added again: its new copy takes
        // the missing one's place)
        let known = Set(items.filter { !$0.isMissing }.map(\.sha256))
        let showsProgress = urls.count > 1
        let control = Importer.Control { [weak self] done, total, current in
            guard let self, self.addProgress != nil else { return }
            self.addProgress?.done = done
            self.addProgress?.total = total
            if !current.isEmpty { self.addProgress?.current = current }
        }
        adding = control
        if showsProgress { addProgress = AddProgress() }
        isBusy = true
        message = "Adding packages…"
        Task.detached(priority: .userInitiated) {
            let outcomes = Importer.importFiles(urls, into: folder, known: known, control: control)
            await self.finishAdding(outcomes, stopped: control.isCancelled)
        }
    }

    /// The progress sheet's Cancel button: stops adding (the packages added so
    /// far are kept), and forgets files dropped meanwhile.
    func cancelAdding() {
        adding?.cancel()
        pendingAdds = []
        addProgress?.stopping = true
    }

    /// Files opened from the Finder or dropped on the Dock icon arrive one by
    /// one: those that come together are added together.
    func open(_ url: URL) {
        openedURLs.append(url)
        guard openedURLs.count == 1 else { return }
        DispatchQueue.main.async {
            let urls = self.openedURLs
            self.openedURLs = []
            self.add(urls)
        }
    }

    private var adding: Importer.Control?
    private var pendingAdds: [URL] = []
    private var openedURLs: [URL] = []

    private func finishAdding(_ outcomes: [Importer.Outcome], stopped: Bool) {
        inTransaction { finishAddingNow(outcomes, stopped: stopped) }
    }

    private func finishAddingNow(_ outcomes: [Importer.Outcome], stopped: Bool) {
        adding = nil
        let hadSheet = addProgress != nil
        addProgress = nil
        defer {
            if !pendingAdds.isEmpty {
                let next = pendingAdds
                pendingAdds = []
                add(next)
            }
        }
        var added: [LibraryItem] = []
        var current = items     // (changed here, and put back once)
        let idBySha = Dictionary(items.map { ($0.sha256, $0.id) }, uniquingKeysWith: { first, _ in first })
        var duplicates: Set<Int64> = [], found: Set<Int64> = [], notPackages: [String] = [], failures: [String] = []
        var archives: [(name: String, packages: Int)] = []
        for outcome in outcomes {
            switch outcome {
            case let .added(sha, path, name, info):
                // The file of a missing package: it's back (with everything you'd set)
                if let index = current.firstIndex(where: { $0.isMissing && $0.sha256 == sha }) {
                    current[index].isMissing = false
                    current[index].filePath = path
                    do { try db?.updateFilePath(id: current[index].id, path) } catch { failures.append("\(name): \(error.localizedDescription)") }
                    found.insert(current[index].id)
                    continue
                }
                do {
                    if let item = try db?.insert(sha256: sha, filePath: path, originalName: name, info: info) {
                        added.append(item)
                    }
                } catch {
                    failures.append("\(name): \(error.localizedDescription)")
                }
            case .duplicate(_, let sha):
                if let existing = idBySha[sha] { duplicates.insert(existing) }
                else if let new = added.first(where: { $0.sha256 == sha }) { duplicates.insert(new.id) }
            case let .archive(name, count):
                archives.append((name, count))
            case .notPackage(let name):
                notPackages.append(name)
            case let .failed(name, why):
                failures.append("\(name): \(why)")
            }
        }
        items = current + added
        // New packages may be add-ons for ones already here, or the main package
        // for add-ons already here: work out the links and file everything
        refreshRelations()
        organize(Set(items.map(\.id)))
        // Select what was added, and anything that was already there
        let chosen = Set(added.map(\.id)).union(duplicates).union(found)
        // The list it was in may now be empty
        if filter == .missing, !items.contains(where: \.isMissing) { filter = .all }
        if !chosen.isEmpty { selection = chosen }
        isBusy = false
        // A single package (new or already there) opens in the Info window
        if chosen.count == 1, let id = chosen.first, failures.isEmpty {
            if hadSheet {
                // (once the progress sheet has gone: one sheet can't replace another at once)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.infoWindow = InfoRequest(id: id) }
            } else {
                infoWindow = InfoRequest(id: id)
            }
        }

        var report: [String] = stopped ? ["Stopped."] : []
        let opened = archives.filter { $0.packages > 0 }, empty = archives.filter { $0.packages == 0 }
        if !opened.isEmpty {
            let count = opened.map(\.packages).reduce(0, +)
            report.append("Found \(count) package\(count == 1 ? "" : "s") in "
                          + (opened.count == 1 ? opened[0].name + "." : "\(opened.count) archives."))
        }
        if empty.count == 1 {
            report.append("\(empty[0].name) has no Newton packages in it.")
        } else if empty.count > 1 {
            report.append("\(empty.count) archives had no Newton packages in them.")
        }
        let dupCount = outcomes.filter { if case .duplicate = $0 { return true } else { return false } }.count
        if !found.isEmpty {
            report.append(found.count == 1 ? "Found 1 missing package." : "Found \(found.count) missing packages.")
        }
        if added.isEmpty && dupCount > 0 {
            report.append(dupCount == 1 ? "That package is already in the library." : "Those \(dupCount) packages are already in the library.")
        } else if !added.isEmpty || found.isEmpty && archives.isEmpty {
            report.append(added.count == 1 ? "Added 1 package." : "Added \(added.count) packages.")
            if dupCount > 0 {
                report.append(dupCount == 1 ? "1 was already in the library." : "\(dupCount) were already in the library.")
            }
        }
        if notPackages.count == 1 {
            report.append("\(notPackages[0]) isn't a Newton package.")
        } else if notPackages.count > 1 {
            report.append("\(notPackages.count) files weren't Newton packages.")
        }
        report += failures.map { "Couldn't add \($0)" }
        message = report.joined(separator: " ")
    }

    // MARK: Changing and removing

    /// Opens the Info window for the selected package (Get Info, ⌘I).
    func showInfo() {
        if selection.count == 1, let id = selection.first { infoWindow = InfoRequest(id: id) }
    }

    func item(_ id: Int64) -> LibraryItem? {
        if derived.index == nil {
            derived.index = Dictionary(items.indices.map { (items[$0].id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        return derived.index?[id].map { items[$0] }
    }

    /// Saves what was changed in the Info window.
    func saveInfo(_ id: Int64, edits: [String: String], notes: String) {
        update(id) {
            $0.edits = edits
            $0.notes = notes
        }
    }

    /// Changes a package and saves it. If its publisher, kind or title changed,
    /// its file moves to the matching folder.
    func update(_ id: Int64, _ change: (inout LibraryItem) -> Void) {
        updateAll([id], change)
    }

    /// Changes several packages and saves them, then works out the links again
    /// and moves files whose folder has changed.
    func updateAll(_ ids: Set<Int64>, _ change: (inout LibraryItem) -> Void) {
        inTransaction { updateAllNow(ids, change) }
    }

    private func updateAllNow(_ ids: Set<Int64>, _ change: (inout LibraryItem) -> Void) {
        var changed = false
        var updated = items     // (changed here, and put back once)
        for index in updated.indices where ids.contains(updated[index].id) {
            var item = updated[index]
            change(&item)
            guard item != updated[index] else { continue }
            do {
                try db?.update(item)
                updated[index] = item
                changed = true
            } catch {
                message = error.localizedDescription
            }
        }
        guard changed else { return }
        items = updated
        refreshRelations()
        organize(Set(items.map(\.id)))
    }

    /// Runs `body` as one database transaction (see LibraryDatabase.transaction).
    private func inTransaction(_ body: () -> Void) {
        if let db { db.transaction(body) } else { body() }
    }

    /// Records where packages' files now are (without moving anything).
    private func setFilePaths(_ paths: [Int64: String]) {
        guard !paths.isEmpty else { return }
        var updated = items     // (changed here, and put back once)
        inTransaction {
            for index in updated.indices {
                guard let path = paths[updated[index].id] else { continue }
                do {
                    try db?.updateFilePath(id: updated[index].id, path)
                    updated[index].filePath = path
                } catch {
                    message = error.localizedDescription
                }
            }
        }
        items = updated
    }

    /// Removes packages from the library, and moves their files to the Trash if asked.
    func remove(_ ids: Set<Int64>, moveFilesToTrash: Bool) {
        inTransaction { removeNow(ids, moveFilesToTrash: moveFilesToTrash) }
    }

    private func removeNow(_ ids: Set<Int64>, moveFilesToTrash: Bool) {
        var removed = 0
        var emptiedFolders: Set<URL> = []
        for item in items where ids.contains(item.id) {
            do {
                try db?.delete(id: item.id)
                removed += 1
                // (Asked before the file goes: a path is compared once it's resolved,
                // which needs the file to be there)
                let inLibraryFolder = isInLibraryFolder(item)
                if moveFilesToTrash, FileManager.default.fileExists(atPath: item.filePath),
                   (try? FileManager.default.trashItem(at: item.fileURL, resultingItemURL: nil)) != nil,
                   inLibraryFolder {
                    emptiedFolders.insert(item.fileURL.deletingLastPathComponent())
                }
            } catch {
                message = error.localizedDescription
            }
        }
        // Folders in the library folder left empty go to the Trash too, and
        // their parents if that empties them (the library folder itself stays)
        for folder in emptiedFolders.sorted(by: { $0.path.count > $1.path.count }) {
            Importer.removeEmptyFolders(from: folder, upTo: libraryFolder, toTrash: true)
        }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        // Add-ons of a removed package go back to their own folders
        refreshRelations()
        organize(Set(items.map(\.id)))
        if removed > 0 {
            message = (removed == 1 ? "Removed 1 package" : "Removed \(removed) packages")
                + (moveFilesToTrash ? " and moved the files to the Trash." : " from the library.")
        }
    }

    func reveal(_ ids: Set<Int64>) {
        let urls = items.filter { ids.contains($0.id) && FileManager.default.fileExists(atPath: $0.filePath) }.map(\.fileURL)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func revealLibraryFolder() {
        let folder = libraryFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: Library commands

    /// Reads every package again, e.g. after this app learns something new.
    /// Your own titles, publishers, Newton OS choices and notes are kept.
    func rereadAll() {
        let snapshot = items
        isBusy = true
        message = "Re-reading packages…"
        Task.detached(priority: .userInitiated) {
            // (several at once: reading a package takes a while, mostly telling its language)
            let infos = Importer.concurrentMap(snapshot) { item in
                (try? Data(contentsOf: item.fileURL)).flatMap { try? PackageReader.inspect($0, fileName: item.originalName) }
            }
            var fresh: [Int64: PackageInfo] = [:]
            for (item, info) in zip(snapshot, infos) { fresh[item.id] = info }
            await self.finishRereading(fresh, missing: snapshot.count - fresh.count)
        }
    }

    private func finishRereading(_ fresh: [Int64: PackageInfo], missing: Int) {
        IconCache.shared.removeAll()
        updateAll(Set(fresh.keys)) { $0.info = fresh[$0.id] ?? $0.info }
        isBusy = false
        message = "Re-read \(fresh.count) package\(fresh.count == 1 ? "" : "s")."
            + (missing > 0 ? " \(missing) couldn't be found or read." : "")
    }

    /// Copies every package that isn't in the library folder into it (after the
    /// folder has been changed in Preferences, for instance).
    func copyAllIntoLibraryFolder() {
        let folder = libraryFolder
        let outside = items.filter { !isInLibraryFolder($0) }
        guard !outside.isEmpty else {
            message = "All packages are already in the library folder."
            return
        }
        let versions = versionsByPackage()
        let targets = Dictionary(uniqueKeysWithValues: outside.map { ($0.id, organizedFolder(for: $0, versions: versions)) })
        // (copied files are then filed with organize, in finishCopying)
        isBusy = true
        Task.detached(priority: .userInitiated) {
            var moved: [Int64: String] = [:]
            var failed = 0
            for item in outside {
                do {
                    moved[item.id] = try Importer.copy(item.fileURL, named: item.originalName, sha256: item.sha256,
                                                       into: targets[item.id]!, libraryRoot: folder).path
                } catch {
                    failed += 1
                }
            }
            await self.finishCopying(moved, failed: failed)
        }
    }

    private func finishCopying(_ moved: [Int64: String], failed: Int) {
        setFilePaths(moved)
        organize(Set(moved.keys))
        isBusy = false
        message = "Copied \(moved.count) package\(moved.count == 1 ? "" : "s") into the library folder."
            + (failed > 0 ? " \(failed) couldn't be copied (their files may be missing)." : "")
    }

    /// Lets you choose package files or folders to add.
    func chooseFilesToAdd() {
        let panel = NSOpenPanel()
        panel.title = "Add to Library"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "Choose Newton packages, archives with packages in them, or folders of them."
        if panel.runModal() == .OK { add(panel.urls) }
    }
}

/// Which package's Info window to show.
struct InfoRequest: Identifiable {
    let id: Int64
}

/// How far adding has got: files looked at, of those known about so far.
struct AddProgress: Equatable {
    var done = 0, total = 0
    /// The file being read.
    var current = ""
    /// Cancel has been clicked; it stops before the next file.
    var stopping = false
}

// MARK: - Importing

/// The file work for adding packages, done off the main thread.
enum Importer {
    enum Outcome {
        case added(sha256: String, path: String, originalName: String, info: PackageInfo)
        case duplicate(String, sha256: String)
        /// An archive that was opened, and how many packages were in it (new or not)
        case archive(String, packages: Int)
        case notPackage(String)
        case failed(String, String)
    }

    /// Newton packages are small; anything bigger than this isn't one.
    static let maximumSize = 64 * 1024 * 1024

    /// How an import tells the app how far it's got, and learns that it should stop.
    /// Used from the import's thread and the main thread.
    final class Control: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var lastReport = Date.distantPast
        private let onProgress: @MainActor @Sendable (_ done: Int, _ total: Int, _ current: String) -> Void

        /// `onProgress` is called on the main thread, a few times a second at most.
        init(onProgress: @escaping @MainActor @Sendable (_ done: Int, _ total: Int, _ current: String) -> Void) {
            self.onProgress = onProgress
        }

        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }

        /// Stops the import before its next file; what it has added so far is kept.
        func cancel() {
            lock.lock(); cancelled = true; lock.unlock()
        }

        func report(done: Int, total: Int, current: String, force: Bool = false) {
            lock.lock()
            let now = Date()
            let due = force || now.timeIntervalSince(lastReport) > 0.1
            if due { lastReport = now }
            lock.unlock()
            guard due else { return }
            let onProgress = self.onProgress
            Task { @MainActor in onProgress(done, total, current) }
        }
    }

    /// Reads each file (and every file in the folders given), copying the
    /// packages into the library folder. Archives are opened, and the packages
    /// inside them added the same way.
    static func importFiles(_ urls: [URL], into folder: URL, known: Set<String>, control: Control? = nil) -> [Outcome] {
        var seen = known
        var outcomes: [Outcome] = []
        // For the progress sheet: files looked at, of all those known about so far
        // (an archive's contents count once it's opened)
        var done = 0, total = 0
        // Archives are unpacked here, and it's all thrown away at the end
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("Newton Library \(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var packagesFound = 0

        /// `inArchive`: inside an archive, where files that aren't packages
        /// (read-mes and so on) are passed over without a word.
        func look(at files: [URL], inArchive: Bool, depth: Int) {
            total += files.count
            // Files are read several at a time (reading a package takes a while,
            // mostly telling its language), then added one by one, in order
            let batchSize = max(4, ProcessInfo.processInfo.activeProcessorCount * 2)
            var start = 0
            while start < files.count {
                if control?.isCancelled == true { return }
                let batch = Array(files[start..<min(start + batchSize, files.count)])
                start += batch.count
                let reads = read(batch, skipping: seen, done: done, total: total)
                for (file, read) in zip(batch, reads) {
                    if control?.isCancelled == true { return }
                    defer { done += 1 }
                    add(file, read, inArchive: inArchive, depth: depth)
                }
            }
        }

        /// Reads files at the same time, telling the progress sheet about each.
        func read(_ files: [URL], skipping known: Set<String>, done: Int, total: Int) -> [Read] {
            let lock = NSLock()
            var started = 0
            return concurrentMap(files) { file in
                if control?.isCancelled == true { return Read() }
                lock.lock()
                let position = done + started
                started += 1
                lock.unlock()
                control?.report(done: position, total: total, current: file.lastPathComponent)
                var read = Read()
                read.size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let data = read.size <= maximumSize ? try? Data(contentsOf: file) : nil
                read.couldRead = data != nil
                guard let package = data.flatMap(PackageReader.package(in:)) else { return read }
                let sha = sha256(package)
                read.package = (package, sha)
                // (a package that's already in the library isn't read)
                if !known.contains(sha) {
                    read.info = Result { try PackageReader.inspect(package, fileName: file.lastPathComponent) }
                }
                return read
            }
        }

        func add(_ file: URL, _ read: Read, inArchive: Bool, depth: Int) {
            let name = file.lastPathComponent
            guard let (package, sha) = read.package else {
                if let format = Archives.format(of: file), depth < Archives.maximumDepth {
                    openArchive(file, format: format, inArchive: inArchive, depth: depth)
                } else if !inArchive {
                    outcomes.append(read.size > maximumSize || read.couldRead ? .notPackage(name)
                                    : .failed(name, "it couldn't be read."))
                }
                return
            }
            packagesFound += 1
            guard !seen.contains(sha) else {
                outcomes.append(.duplicate(name, sha256: sha))
                return
            }
            do {
                let info = try (read.info ?? Result { try PackageReader.inspect(package, fileName: name) }).get()
                let target = organizedFolder(root: folder, publisher: info.publisher ?? "",
                                             kind: info.kind.label, title: info.title)
                let copy = try self.copy(file, named: name, sha256: sha, into: target, libraryRoot: folder)
                seen.insert(sha)
                outcomes.append(.added(sha256: sha, path: copy.path, originalName: name, info: info))
            } catch {
                outcomes.append(.failed(name, error.localizedDescription))
            }
        }

        func openArchive(_ file: URL, format: Archives.Format, inArchive: Bool, depth: Int) {
            let name = file.lastPathComponent
            let before = packagesFound
            do {
                let contents = try Archives.extract(file, format: format, into: scratch)
                look(at: expand([contents]), inArchive: true, depth: depth + 1)
                // Archives inside archives count towards the outermost one
                if !inArchive { outcomes.append(.archive(name, packages: packagesFound - before)) }
            } catch {
                // Inside an archive, anything that won't open is passed over
                guard !inArchive else { return }
                if case Archives.Failure.needsUnar = error {
                    outcomes.append(format == .byName ? .notPackage(name)
                                    : .failed(name, "opening this kind of archive needs unar (brew install unar)."))
                } else {
                    // Something only named like an archive isn't one
                    outcomes.append(format == .byName ? .notPackage(name) : .failed(name, "the archive couldn't be opened."))
                }
            }
        }

        look(at: expand(urls), inArchive: false, depth: 0)
        control?.report(done: done, total: total, current: "", force: true)
        return outcomes
    }

    /// What reading a file found.
    private struct Read {
        var size = 0
        var couldRead = false
        /// The package in it (without any MacBinary wrapping), and its SHA-256.
        var package: (data: Data, sha256: String)?
        /// What it says, unless it's already in the library.
        var info: Result<PackageInfo, Error>?
    }

    /// `transform` applied to each of `items`, several at a time, in order.
    static func concurrentMap<T, U>(_ items: [T], _ transform: (T) -> U) -> [U] {
        var results = [U?](repeating: nil, count: items.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: items.count) { i in
            let result = transform(items[i])
            lock.lock()
            results[i] = result
            lock.unlock()
        }
        return results.map { $0! }
    }

    /// The files to look at: the files given, plus everything inside the folders given.
    static func expand(_ urls: [URL]) -> [URL] {
        var files: [URL] = []
        for url in urls {
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { continue }
            if isFolder.boolValue {
                let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let next = walker?.nextObject() as? URL {
                    if (try? next.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                        files.append(next)
                    }
                }
            } else {
                files.append(url)
            }
        }
        return files
    }

    // MARK: Library folder layout

    /// The folder a package belongs in: root / Publisher / Kind / Title. A
    /// publisher folder that's already there under another spelling ("Apple
    /// Computer, Inc." for "Apple Computer Inc.") is used rather than a new one.
    static func organizedFolder(root: URL, publisher: String, kind: String, title: String,
                                publisherFolders: [String]? = nil) -> URL {
        var publisherFolder = folderName(publisher, fallback: "Unknown Developer")
        let key = LibraryItem.publisherKey(publisherFolder)
        if let existing = publisherFolders ?? (try? FileManager.default.contentsOfDirectory(atPath: root.path)),
           let match = existing.first(where: { name in
               var isFolder: ObjCBool = false
               return LibraryItem.publisherKey(name) == key && !key.isEmpty
                   && FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path, isDirectory: &isFolder)
                   && isFolder.boolValue
           }) {
            publisherFolder = match
        }
        return root
            .appendingPathComponent(publisherFolder, isDirectory: true)
            .appendingPathComponent(folderName(kind, fallback: "Other"), isDirectory: true)
            .appendingPathComponent(folderName(title, fallback: "Untitled"), isDirectory: true)
    }

    /// A name made safe for a folder: no slashes or colons, no leading dot,
    /// not too long.
    static func folderName(_ name: String, fallback: String) -> String {
        var safe = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while safe.hasPrefix(".") { safe.removeFirst() }
        if safe.count > 80 { safe = String(safe.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return safe.isEmpty ? fallback : safe
    }

    static func isInside(_ file: URL, _ folder: URL) -> Bool {
        file.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
    }

    /// A free name for a file in a folder: its own name, or with " 2", " 3"... added.
    /// (Made one at a time, as they're tried: the first is almost always free.)
    private static func candidates(for name: String) -> LazyMapSequence<ClosedRange<Int>, String> {
        let safeName = name.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        let base = (safeName as NSString).deletingPathExtension
        let ext = (safeName as NSString).pathExtension
        return (1...9999).lazy.map { n in n == 1 ? safeName : "\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)") }
    }

    /// Copies a package into a folder under its own name, adding " 2", " 3"...
    /// if a different file already has that name. Returns where the copy is.
    /// A file already inside the library folder isn't copied again.
    static func copy(_ source: URL, named name: String, sha256 sha: String, into folder: URL,
                     libraryRoot: URL) throws -> URL {
        if isInside(source, libraryRoot) { return source }
        // A package in MacBinary is kept as the package alone
        let data = try Data(contentsOf: source)
        let package = PackageReader.package(in: data) ?? data
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for candidate in candidates(for: name) {
            let destination = folder.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: destination.path) {
                if package.count == data.count {
                    try FileManager.default.copyItem(at: source, to: destination)
                } else {
                    try package.write(to: destination, options: .withoutOverwriting)
                }
                return destination
            }
            // The same package is already there (from an earlier library, say)
            if let existing = try? Data(contentsOf: destination),
               sha256(PackageReader.package(in: existing) ?? existing) == sha {
                return destination
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Moves a file into a folder, named `name` if given (its original name: a
    /// copy renamed "Manual 2.pkg" because another manual was in the same folder
    /// gets its name back), else keeping its name, adding " 2"… if it's taken.
    static func move(_ file: URL, into folder: URL, named name: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for candidate in candidates(for: name ?? file.lastPathComponent) {
            let destination = folder.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: file, to: destination)
                return destination
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Removes a folder if it's empty (apart from .DS_Store), then its parents,
    /// stopping at the library folder. With toTrash, they go to the Trash
    /// instead of being deleted.
    static func removeEmptyFolders(from folder: URL, upTo root: URL, toTrash: Bool = false) {
        var current = folder.standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        while current.path.hasPrefix(rootPath + "/") {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: current.path)) ?? ["?"]
            guard contents.allSatisfy({ $0 == ".DS_Store" }) else { return }
            if toTrash {
                guard (try? FileManager.default.trashItem(at: current, resultingItemURL: nil)) != nil else { return }
            } else {
                try? FileManager.default.removeItem(at: current)
            }
            current = current.deletingLastPathComponent()
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
