import SwiftUI

/// What a package's main package is set to: worked out from the packages, none
/// (it stands alone), or a package you chose.
enum MainPackageChoice: Hashable {
    case automatic
    case none
    case package(sha256: String)

    /// As kept in a package's edits: nil for automatic, "" for none, or the
    /// main package's SHA-256.
    init(stored: String?) {
        switch stored {
        case nil: self = .automatic
        case ""?: self = .none
        case let sha?: self = .package(sha256: sha)
        }
    }

    var stored: String? {
        switch self {
        case .automatic: return nil
        case .none: return ""
        case .package(let sha): return sha
        }
    }
}

/// Which packages a Set Main Package sheet is for.
struct MainPackageRequest: Identifiable {
    let id = UUID()
    let ids: Set<Int64>
}

/// Chooses the main package of one or more packages, searching the library
/// for it. Used for Set Main Package… and by the Info window.
struct MainPackageChooser: View {
    @ObservedObject var store: LibraryStore
    /// The packages whose main package this sets.
    let packages: [LibraryItem]
    let onChoose: (MainPackageChoice) -> Void
    @Environment(\.dismiss) private var dismiss

    /// nil while nothing is chosen (several packages set differently)
    @State private var choice: MainPackageChoice?
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    init(store: LibraryStore, packages: [LibraryItem], current: MainPackageChoice? = nil,
         onChoose: @escaping (MainPackageChoice) -> Void) {
        self.store = store
        self.packages = packages
        self.onChoose = onChoose
        // What they're set to now, if they're all set the same way
        let choices = Set(packages.map { MainPackageChoice(stored: $0.mainPackageChoice) })
        _choice = State(initialValue: current ?? (choices.count == 1 ? choices.first : nil))
    }

    /// The packages that can be chosen: any but the ones being set, matching the search.
    private var candidates: [LibraryItem] {
        let own = Set(packages.map(\.id))
        return store.itemsByTitle(matching: search).filter { !own.contains($0.id) }
    }

    var body: some View {
        let candidates = self.candidates
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(packages.count == 1 ? "Main Package for “\(packages[0].title)”"
                     : "Main Package for \(packages.count) Packages")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("An add-on is listed with its main package and stored in the same folder.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                TextField("Search", text: $search, prompt: Text("Search for the main package"))
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onSubmit(choose)   // (Return here chooses, as in the list)
            }
            .padding(16)
            ScrollViewReader { proxy in
                List(selection: Binding(get: { choice }, set: { if let c = $0 { choice = c } })) {
                    if search.isEmpty {
                        Text(automaticLabel)
                            .tag(MainPackageChoice.automatic)
                            .id(MainPackageChoice.automatic)
                        Text(packages.count == 1 ? "None: it stands alone" : "None: they stand alone")
                            .tag(MainPackageChoice.none)
                            .id(MainPackageChoice.none)
                    }
                    Section(search.isEmpty ? "Packages" : "\(candidates.count) Found") {
                        ForEach(candidates) { item in
                            row(item)
                                .tag(MainPackageChoice.package(sha256: item.sha256))
                                .id(MainPackageChoice.package(sha256: item.sha256))
                        }
                    }
                }
                .onAppear {
                    searchFocused = true
                    if let choice { proxy.scrollTo(choice, anchor: .center) }
                    #if DEBUG
                    if let text = UserDefaults.standard.string(forKey: "DebugMainSearch") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { search = text }
                    }
                    #endif
                }
                .onChange(of: search) { _ in
                    // The best match is chosen while the chosen package isn't among those found
                    // (so Return after typing a name chooses it)
                    let found = self.candidates     // (as the search is now)
                    guard !search.isEmpty, let first = found.first else { return }
                    if case .package(let sha) = choice, found.contains(where: { $0.sha256 == sha }) { return }
                    choice = .package(sha256: first.sha256)
                    proxy.scrollTo(choice, anchor: .top)
                }
            }
            Divider()
            HStack {
                Text(summary)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Choose", action: choose)
                    .keyboardShortcut(.defaultAction)
                .disabled(choice == nil)
            }
            .padding(12)
        }
        .frame(width: 540, height: 580)
    }

    private func choose() {
        guard let choice else { return }
        onChoose(choice)
        dismiss()
    }

    private func row(_ item: LibraryItem) -> some View {
        HStack(spacing: 8) {
            PackageIcon(item: item, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                Text([item.publisher, item.kindLabel, item.version].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 1)
    }

    /// Automatic, with what's found for a single package.
    private var automaticLabel: String {
        guard packages.count == 1 else { return "Automatic: worked out from each package" }
        let found = store.foundRelations.main[packages[0].id].flatMap { store.item($0) }
        return "Automatic (\(found?.title ?? "none found"))"
    }

    private var summary: String {
        switch choice {
        case nil: return "They're set differently now."
        case .automatic?: return "The app works it out."
        case .none?: return packages.count == 1 ? "It stands alone." : "They stand alone."
        case .package(let sha)?:
            let main = store.item(withSHA256: sha)
            return "Add-on for " + (main.map { "“\($0.title)”" } ?? "a package no longer in the library")
        }
    }
}
