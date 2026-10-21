import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: LibraryStore
    @State private var sortOrder = [KeyPathComparator(\LibraryItem.title)]
    @State private var isDropTarget = false
    @State private var confirmRemove = false
    /// Packages whose add-ons are shown under them (none to start with).
    @State private var expanded: Set<Int64> = []

    private var visibleItems: [LibraryItem] {
        let filtered = store.items.filter { store.filter.includes($0) }
        let searched = store.search.isEmpty ? filtered : filtered.filter { $0.matches(store.search) }
        return searched.sorted(using: sortOrder)
    }

    /// Whether the list shows packages with their add-ons under them: for a
    /// kind of application (Applications, Games).
    private var groupsAddOns: Bool {
        if case .kind(let key) = store.filter { return PackageKind(rawValue: key)?.isApplication == true }
        return false
    }

    /// The list's rows, with how deep each is and how many add-ons it has.
    private struct Rows {
        var items: [LibraryItem] = []
        var depth: [Int64: Int] = [:]
        var addOnCount: [Int64: Int] = [:]
    }

    private var rows: Rows {
        let visible = visibleItems
        guard groupsAddOns else { return Rows(items: visible) }
        var rows = Rows()
        // An add-on of a package in the list goes under it, not in the list itself
        let ids = Set(visible.map(\.id))
        func addOns(_ item: LibraryItem) -> [LibraryItem] {
            store.addOns(of: item).sorted(using: sortOrder)
        }
        func add(_ item: LibraryItem, depth: Int, seen: Set<Int64>) {
            let children = addOns(item).filter { !seen.contains($0.id) }
            rows.items.append(item)
            rows.depth[item.id] = depth
            rows.addOnCount[item.id] = children.count
            guard expanded.contains(item.id) else { return }
            for child in children { add(child, depth: depth + 1, seen: seen.union([item.id])) }
        }
        for item in visible where store.relations.root(of: item.id).map({ !ids.contains($0) }) ?? true {
            add(item, depth: 0, seen: [])
        }
        return rows
    }

    /// Debug builds only: -DebugKind <kind> shows that kind, and -DebugExpand
    /// <title> shows the add-ons of the packages with that title and selects
    /// them all, for checking the list and dragging from scripts.
    private func debugSetUp() {
        #if DEBUG
        guard let kind = UserDefaults.standard.string(forKey: "DebugKind") else { return }
        store.filter = .kind(kind)
        if let title = UserDefaults.standard.string(forKey: "DebugExpand") {
            let mains = store.items.filter { $0.title == title }
            expanded.formUnion(mains.map(\.id))
            store.selection = Set(mains.flatMap { [$0.id] + store.relations.addOns(of: $0.id) })
        }
        #endif
    }

    /// Shows or hides a package's add-ons; hidden ones are no longer selected.
    private func toggle(_ item: LibraryItem) {
        if expanded.contains(item.id) {
            expanded.remove(item.id)
            var hidden: [Int64] = [], queue = [item.id]
            while let id = queue.popLast() {
                let children = store.relations.addOns(of: id)
                hidden += children
                queue += children
            }
            store.selection.subtract(hidden)
        } else {
            expanded.insert(item.id)
        }
    }

    var body: some View {
        NavigationView {
            SidebarView(store: store, filter: $store.filter)
                .frame(minWidth: 210, idealWidth: 230)
            list
                .frame(minWidth: 520)
            DetailPane(store: store, selection: store.selection, onRemove: askToRemove)
                .frame(minWidth: 300, idealWidth: 340)
        }
        .navigationTitle(store.title(for: store.filter))
        .searchable(text: $store.search, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Show or hide the sidebar")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: store.chooseFilesToAdd) {
                    Label("Add", systemImage: "plus")
                }
                .help("Add packages to the library")
                Button(action: store.showInfo) {
                    Label("Get Info", systemImage: "info.circle")
                }
                .help("See and change everything about the selected package (⌘I)")
                .disabled(store.selection.count != 1)
                Button { store.reveal(store.selection) } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Show the selected packages in the Finder")
                .disabled(store.selection.isEmpty)
                Button(action: askToRemove) {
                    Label("Remove", systemImage: "trash")
                }
                .help("Remove the selected packages from the library")
                .disabled(store.selection.isEmpty)
            }
        }
        .onAppear(perform: debugSetUp)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget, perform: drop)
        .overlay(dropHighlight)
        .confirmationDialog(removeQuestion, isPresented: $confirmRemove) {
            Button("Move to Trash", role: .destructive) { remove(trash: true) }
            Button("Remove from Library Only") { remove(trash: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The copies in your library folder can be moved to the Trash, or kept.")
        }
        .sheet(item: $store.infoWindow) { request in
            if let item = store.item(request.id) {
                InfoWindow(store: store, item: item)
            }
        }
        .alert("The library couldn't be opened", isPresented: .constant(store.databaseError != nil)) {
            Button("Quit") { NSApp.terminate(nil) }
        } message: {
            Text(store.databaseError ?? "")
        }
    }

    // MARK: The list

    private var list: some View {
        let rows = self.rows
        let items = rows.items
        return VStack(spacing: 0) {
            ZStack {
                PackageTable(items: items, mainPackage: store.mainPackage(of:), selection: $store.selection, sortOrder: $sortOrder,
                             grouped: groupsAddOns, depth: rows.depth, addOnCount: rows.addOnCount, expanded: expanded,
                             onToggle: toggle, onDelete: askToRemove)
                    .id(store.filter)   // a new filter starts at the top of the list
                if store.items.isEmpty {
                    emptyLibrary
                }
            }
            Divider()
            statusBar(items)
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Drag Newton packages here")
                .font(.title2)
            Text("or choose File > Add to Library…")
                .foregroundColor(.secondary)
        }
        .padding(30)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
    }

    private func statusBar(_ items: [LibraryItem]) -> some View {
        HStack(spacing: 8) {
            if store.isBusy {
                ProgressView().controlSize(.small)
            }
            if let message = store.message {
                Text(message)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(message)
                if !store.isBusy {
                    Button {
                        store.message = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .help("Dismiss")
                }
            }
            Spacer()
            let size = Int64(items.reduce(0) { $0 + $1.fileSize })
            Text("\(items.count) package\(items.count == 1 ? "" : "s"), "
                 + ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                .foregroundColor(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: Drag and drop

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.accentColor, lineWidth: 3)
            .padding(2)
            .opacity(isDropTarget ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let url = url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            store.add(urls)
        }
        return true
    }

    // MARK: Removing

    private var removeQuestion: String {
        store.selection.count == 1 ? "Remove this package from the library?"
            : "Remove \(store.selection.count) packages from the library?"
    }

    private func askToRemove() {
        if !store.selection.isEmpty { confirmRemove = true }
    }

    private func remove(trash: Bool) {
        store.remove(store.selection, moveFilesToTrash: trash)
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
}
