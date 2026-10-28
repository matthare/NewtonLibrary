import Foundation

/// The fields of a package you can change in the Info window.
enum InfoField: String, CaseIterable {
    case title, publisher, author, copyright, packageName, signature, extrasName, appSymbol, isbn
    case version, created, kind, minOS, maxOS, language
    /// The sidebar group, as set in version 1. Now worked out from minOS and maxOS;
    /// old edits of it are turned into those when the library is opened.
    case newtonOS
}

/// One package in the library: what was read from it, plus anything you changed.
struct LibraryItem: Identifiable, Hashable {
    let id: Int64
    var sha256: String
    var filePath: String
    var originalName: String
    var dateAdded: Date
    var info: PackageInfo
    /// Your changes, by InfoField name. A field that isn't here shows what was
    /// read from the package. (Kept apart from `info`, so re-reading the package
    /// never loses them.)
    var edits: [String: String]
    var notes: String
    /// Its file isn't where the library says it is (worked out when the app
    /// opens and by Library > Check for Missing Files; not saved).
    var isMissing = false

    var fileURL: URL { URL(fileURLWithPath: filePath) }

    // MARK: Values, edited or as read

    /// A field as text, as read from the package.
    func detected(_ field: InfoField) -> String {
        switch field {
        case .title: return info.title
        case .publisher: return info.publisher ?? ""
        case .author: return info.author ?? ""
        case .copyright: return info.copyright
        case .packageName: return info.packageName
        case .signature: return info.signature ?? ""
        case .extrasName: return info.extrasName ?? ""
        case .appSymbol: return info.appSymbol ?? ""
        case .isbn: return info.isbn ?? ""
        case .language: return info.language.map(LibraryItem.languageName) ?? ""
        case .version: return info.versionText ?? String(info.version)
        case .created: return info.creationDate.map { String($0.timeIntervalSinceReferenceDate) } ?? ""
        case .kind: return info.kind.rawValue
        case .minOS: return info.minOS ?? NewtonOSVersion.range(for: info.detectedOS).min
        case .maxOS: return info.maxOS ?? NewtonOSVersion.range(for: info.detectedOS).max
        case .newtonOS: return info.detectedOS.rawValue
        }
    }

    /// A field as text: your change if you made one, else as read.
    func value(_ field: InfoField) -> String {
        edits[field.rawValue] ?? detected(field)
    }

    func isEdited(_ field: InfoField) -> Bool {
        edits[field.rawValue] != nil
    }

    var title: String { value(.title) }
    var publisher: String { value(.publisher) }
    var author: String { value(.author) }
    /// The language it's written in ("German"), or "" if not known.
    var language: String { value(.language) }

    /// A language's name, in the language of this Mac ("de" -> "German").
    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
    var minOS: String { value(.minOS) }
    var maxOS: String { value(.maxOS) }
    /// The sidebar group, from the minimum and maximum versions.
    var os: NewtonOS { NewtonOSVersion.group(min: minOS, max: maxOS) ?? .unknown }
    /// The kind as stored: a PackageKind raw value, or a kind you named yourself.
    var kindKey: String { LibraryItem.kindKey(for: value(.kind)) }
    /// The built-in kind, or .other for one you named.
    var kind: PackageKind { PackageKind(rawValue: kindKey) ?? .other }
    /// The name of a kind you made up, if this package has one.
    var customKind: String? { PackageKind(rawValue: kindKey) == nil && !kindKey.isEmpty ? kindKey : nil }
    /// The symbol for the package when it has no Newton icon.
    var iconKind: PackageKind { PackageKind(rawValue: kindKey) ?? info.kind }

    /// What you typed as a kind, as it's stored: a built-in kind's name
    /// ("book", "Books") becomes that kind, anything else stays as typed.
    static func kindKey(for typed: String) -> String {
        kindKeys.value(for: typed) { makeKindKey(typed) }
    }

    private static let kindKeys = Memo<String, String>()

    private static func makeKindKey(_ typed: String) -> String {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        for kind in PackageKind.allCases {
            for match in [kind.rawValue, kind.label, kind.pluralLabel]
            where match.caseInsensitiveCompare(name) == .orderedSame {
                return kind.rawValue
            }
        }
        return name
    }
    var version: String { value(.version) }
    /// For sorting by version: each number in it padded, so 1.10 comes after 1.9.
    var versionSortKey: String {
        version.split(whereSeparator: { !$0.isNumber }).map { String(repeating: "0", count: max(0, 10 - $0.count)) + $0 }
            .joined(separator: ".")
    }
    var creationDate: Date? {
        Double(value(.created)).map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    /// The main package you chose for this one in Get Info: nil to work it out,
    /// "" for none (it stands alone), or the main package's SHA-256.
    var mainPackageChoice: String? {
        get { edits["mainPackage"] }
        set { edits["mainPackage"] = newValue }
    }

    /// Whether you changed the minimum or maximum version.
    var osIsEdited: Bool { isEdited(.minOS) || isEdited(.maxOS) }

    /// Puts the package in a sidebar group by setting its minimum and maximum
    /// versions; nil goes back to what was read from the package.
    mutating func setGroup(_ group: NewtonOS?) {
        edits[InfoField.newtonOS.rawValue] = nil
        guard let group = group else {
            edits[InfoField.minOS.rawValue] = nil
            edits[InfoField.maxOS.rawValue] = nil
            return
        }
        let range = NewtonOSVersion.range(for: group)
        edits[InfoField.minOS.rawValue] = range.min == detected(.minOS) ? nil : range.min
        edits[InfoField.maxOS.rawValue] = range.max == detected(.maxOS) ? nil : range.max
    }

    /// Your own publisher, or nil for what was read from the package.
    var publisherOverride: String? {
        get { edits[InfoField.publisher.rawValue] }
        set { edits[InfoField.publisher.rawValue] = newValue }
    }

    // For sorting the list
    var osRank: Int { os.rank }
    /// For sorting by version: unknown sorts last.
    var minOSRank: Double { NewtonOSVersion.rank(minOS) ?? 99 }
    var maxOSRank: Double { NewtonOSVersion.rank(maxOS) ?? 99 }
    var kindLabel: String { PackageKind(rawValue: kindKey)?.label ?? kindKey }
    var fileSize: Int { info.fileSize }
    var created: Date { creationDate ?? .distantPast }

    /// The publisher with punctuation and company endings removed, so "Apple Computer",
    /// "Apple Computer Inc." and "Apple Computer, Inc." are grouped together.
    var publisherKey: String { LibraryItem.publisherKey(publisher) }

    static func publisherKey(_ name: String) -> String {
        // (worked out once per name: the sidebar asks for thousands)
        publisherKeys.value(for: name) { makePublisherKey(name) }
    }

    private static let publisherKeys = Memo<String, String>()

    private static func makePublisherKey(_ name: String) -> String {
        let endings: Set<String> = ["inc", "llc", "ltd", "corp", "corporation", "co", "gmbh", "incorporated"]
        var words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        while words.count > 1, let last = words.last, endings.contains(last) { words.removeLast() }
        return words.joined(separator: " ")
    }

    /// Whether it works on every Newton OS version from `from` to `to`: its
    /// minimum is no newer than `from` (and known), and its maximum, if known,
    /// no older than `to`. An empty `from` or `to` ("Any") leaves that side out,
    /// so only the other version is checked.
    func runsOn(from: String, to: String) -> Bool {
        if let first = NewtonOSVersion.rank(from) {
            guard let low = NewtonOSVersion.rank(minOS), low <= first else { return false }
        }
        if let last = NewtonOSVersion.rank(to), let high = NewtonOSVersion.rank(maxOS), high < last {
            return false
        }
        return true
    }

    func matches(_ search: String) -> Bool {
        searchText.range(of: Self.folded(search), options: .literal) != nil
    }

    /// The text search looks through (titles, developers, package and file
    /// names, copyrights, notes, Extras names, authors and languages), one
    /// field to a line, folded with `folded`.
    var searchText: String {
        Self.folded([title, publisher, value(.packageName), originalName, value(.copyright), notes,
                     value(.extrasName), author, language].joined(separator: "\n"))
    }

    /// Text without case or accents, for searching: search text folded the same
    /// way is then found by a plain comparison.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// The sidebar's choices.
enum LibraryFilter: Hashable {
    case all
    case recentlyAdded
    case os(NewtonOS)
    /// Packages that run on every Newton OS version from the first to the second
    case runsOn(String, String)
    /// A kind: a PackageKind raw value, or a kind you named yourself
    case kind(String)
    /// A publisher, by its grouping key (see LibraryItem.publisherKey)
    case publisher(String)
    /// Packages whose files can't be found (listed only here)
    case missing

    /// Recently Added: packages added in this many days.
    static let recentDays: Double = 30

    func includes(_ item: LibraryItem) -> Bool {
        if self == .missing { return item.isMissing }
        if item.isMissing { return false }
        switch self {
        case .missing: return true
        case .all: return true
        case .recentlyAdded: return item.dateAdded > Date().addingTimeInterval(-LibraryFilter.recentDays * 24 * 60 * 60)
        case .os(let os): return item.os == os
        case .runsOn(let from, let to): return item.runsOn(from: from, to: to)
        case .kind(let key): return item.kindKey == key
        case .publisher(let key): return item.publisherKey == key
        }
    }

    /// The name in the sidebar, where the section headers already say "Newton OS" and so on.
    var sidebarTitle: String {
        switch self {
        case .os(let os): return os.sidebarLabel
        case .runsOn: return "Runs on"
        default: return title
        }
    }

    var title: String {
        switch self {
        case .all: return "All Packages"
        case .recentlyAdded: return "Recently Added"
        case .os(let os): return os.label
        case .runsOn(let from, let to):
            switch (from.isEmpty, to.isEmpty) {
            case (true, true): return "Any Newton OS"
            case (false, true): return "Min OS \(from) or Older"
            case (true, false): return "Max OS \(to) or Newer"
            default: return from == to ? "Runs on Newton OS \(from)" : "Runs on Newton OS \(from) to \(to)"
            }
        case .kind(let key): return PackageKind(rawValue: key)?.pluralLabel ?? key
        case .publisher(let key): return key.isEmpty ? "No Developer" : key
        case .missing: return "Missing Files"
        }
    }
}

/// Results kept by key, safe to use from any thread.
final class Memo<Key: Hashable, Value>: @unchecked Sendable {
    private var values: [Key: Value] = [:]
    private let lock = NSLock()

    func value(for key: Key, _ make: () -> Value) -> Value {
        lock.lock()
        if let value = values[key] {
            lock.unlock()
            return value
        }
        lock.unlock()
        let value = make()
        lock.lock()
        values[key] = value
        lock.unlock()
        return value
    }
}
