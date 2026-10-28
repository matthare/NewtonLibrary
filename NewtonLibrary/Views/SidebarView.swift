import SwiftUI

/// The filters down the left: the whole library, by Newton OS, by kind and by publisher.
struct SidebarView: View {
    @ObservedObject var store: LibraryStore
    @Binding var filter: LibraryFilter

    /// The list's selection, as a set: plain (non-optional) tags match a set
    /// selection the same way on every macOS version, whereas single-selection
    /// tags must be optional on macOS 12-13 and plain on 14 and later. Only one
    /// filter applies at a time, so the newest choice wins.
    private var selection: Binding<Set<LibraryFilter>> {
        Binding(
            get: { [filter] },
            set: { chosen in
                if let newest = chosen.first(where: { $0 != filter }) ?? chosen.first {
                    filter = newest
                }
            })
    }

    var body: some View {
        List(selection: selection) {
            Section(header: Text("Library")) {
                row(.all, symbol: "books.vertical")
                row(.recentlyAdded, symbol: "clock")
            }
            if count(.missing) > 0 {
                Section(header: Text("Missing")) {
                    row(.missing, symbol: "exclamationmark.triangle", title: "Missing Files")
                }
            }
            Section(header: Text("Newton OS")) {
                ForEach(NewtonOS.allCases.sorted { $0.rank < $1.rank }) { os in
                    if count(.os(os)) > 0 || os != .os1Only && os != .unknown {
                        row(.os(os), symbol: symbol(for: os))
                    }
                }
                runsOnRow
            }
            Section(header: Text("Kind")) {
                ForEach(PackageKind.allCases) { kind in
                    if count(.kind(kind.rawValue)) > 0 {
                        row(.kind(kind.rawValue), symbol: kind.symbolName)
                    }
                }
                // Kinds you've named yourself
                ForEach(store.customKinds, id: \.self) { name in
                    row(.kind(name), symbol: "tag")
                }
            }
            Section(header: Text("Developers")) {
                ForEach(store.publishers, id: \.key) { publisher in
                    row(.publisher(publisher.key), symbol: "person",
                        title: publisher.name.isEmpty ? "No Developer" : publisher.name)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ choice: LibraryFilter, symbol: String, title: String? = nil) -> some View {
        Label(title ?? choice.sidebarTitle, systemImage: symbol)
            .lineLimit(1)
            .badge(count(choice))
            .tag(choice)
    }

    /// "Runs on [from] to [to]": packages that work on all those versions.
    private var runsOnRow: some View {
        let choice = LibraryFilter.runsOn(store.runsOnFrom, store.runsOnTo)
        return VStack(alignment: .leading, spacing: 4) {
            Label("Runs on", systemImage: "arrow.left.and.right.circle")
                .badge(count(choice))
            HStack(spacing: 4) {
                versionMenu(store.runsOnFrom) { v in
                    store.runsOnFrom = v
                    if let a = NewtonOSVersion.rank(v), let b = NewtonOSVersion.rank(store.runsOnTo), b < a { store.runsOnTo = v }
                    filter = .runsOn(store.runsOnFrom, store.runsOnTo)
                }
                Text("to")
                    .foregroundColor(.secondary)
                versionMenu(store.runsOnTo) { v in
                    store.runsOnTo = v
                    if let a = NewtonOSVersion.rank(store.runsOnFrom), let b = NewtonOSVersion.rank(v), b < a { store.runsOnFrom = v }
                    filter = .runsOn(store.runsOnFrom, store.runsOnTo)
                }
            }
            .padding(.leading, 22)
        }
        .help("Packages that work on every Newton OS version in this range. "
              + "Any on the left: only the maximum is checked; Any on the right: only the minimum.")
        .tag(choice)
    }

    /// A version menu; "Any" (stored as "") leaves that end of the range open.
    private func versionMenu(_ current: String, choose: @escaping (String) -> Void) -> some View {
        Menu(current.isEmpty ? "Any" : current) {
            Button("Any") { choose("") }
            Divider()
            ForEach(NewtonOSVersion.all.filter { $0 != "1.x" }, id: \.self) { v in
                Button(v) { choose(v) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func count(_ choice: LibraryFilter) -> Int {
        store.count(choice)
    }

    private func symbol(for os: NewtonOS) -> String {
        switch os {
        case .any, .os1Only: return "1.circle"
        case .os20: return "2.circle"
        case .os21: return "2.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}
