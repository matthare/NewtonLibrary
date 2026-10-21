import SwiftUI

/// The pane on the right: everything about the selected package.
struct DetailPane: View {
    @ObservedObject var store: LibraryStore
    let selection: Set<Int64>
    var onRemove: () -> Void

    var body: some View {
        let selected = store.items.filter { selection.contains($0.id) }
        if selected.count == 1, let item = selected.first {
            PackageDetailView(store: store, item: item, onRemove: onRemove)
                .id(item.id)
        } else if selected.count > 1 {
            MultipleSelectionView(store: store, items: selected, onRemove: onRemove)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No Package Selected")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A summary of the selected package. Get Info (⌘I) changes it.
struct PackageDetailView: View {
    @ObservedObject var store: LibraryStore
    let item: LibraryItem
    var onRemove: () -> Void

    private var info: PackageInfo { item.info }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                compatibility
                RelatedPackagesView(store: store, item: item)
                packageDetails
                if !info.parts.isEmpty { parts }
                if !info.protosUsed.isEmpty { protos }
                file
                if !item.notes.isEmpty { notes }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            PackageIcon(item: item, size: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                if !item.publisher.isEmpty {
                    Text(item.publisher)
                        .foregroundColor(.secondary)
                }
                Text(item.kindLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Get Info…") { store.infoWindow = InfoRequest(id: item.id) }
                    .padding(.top, 4)
                    .help("See and change everything about this package (⌘I)")
            }
        }
    }

    private var compatibility: some View {
        DetailSection(title: "Compatibility") {
            Text(item.os.label)
                .font(.body.weight(.medium))
            InfoRow("Min OS", NewtonOSVersion.label(item.minOS), edited: item.isEdited(.minOS))
            InfoRow("Max OS", item.maxOS.isEmpty ? "No limit known" : item.maxOS, edited: item.isEdited(.maxOS))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(info.evidence, id: \.self) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: e.requires == nil ? "info.circle" : "checkmark.seal")
                            .foregroundColor(e.requires == nil ? .secondary : .accentColor)
                        Text(e.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var packageDetails: some View {
        DetailSection(title: "Package") {
            field("Package name", .packageName)
            field("Signature", .signature)
            field("Extras name", .extrasName)
            field("Author", .author)
            field("Language", .language)
            field("ISBN", .isbn)
            field("Copyright", .copyright)
            InfoRow("Version", item.version == String(info.version) ? item.version : "\(item.version) (header: \(info.version))",
                    edited: item.isEdited(.version))
            InfoRow("Created", item.creationDate.map { $0.formatted(date: .long, time: .shortened) } ?? "—",
                    edited: item.isEdited(.created))
            InfoRow("Size", ByteCountFormatter.string(fromByteCount: Int64(info.fileSize), countStyle: .file))
            InfoRow("Format", info.formatVersion == 1 ? "package1 (Newton OS 2.0 and later)" : "package0")
            if !info.packageFlags.isEmpty { InfoRow("Flags", info.packageFlags.joined(separator: ", ")) }
            if info.hasNativeCode { InfoRow("Native code", "Yes (ARM)") }
            field("App symbol", .appSymbol)
            ForEach(info.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundColor(.orange)
            }
        }
    }

    /// A row for a field you can edit; empty fields are left out.
    @ViewBuilder
    private func field(_ label: String, _ field: InfoField) -> some View {
        let value = item.value(field)
        if !value.isEmpty || item.isEdited(field) {
            InfoRow(label, value.isEmpty ? "—" : value, edited: item.isEdited(field))
        }
    }

    private var parts: some View {
        DetailSection(title: info.parts.count == 1 ? "Part" : "Parts (\(info.parts.count))") {
            ForEach(Array(info.parts.enumerated()), id: \.offset) { index, part in
                InfoRow(part.type.isEmpty ? "Part \(index)" : "'\(part.type)'",
                        "\(part.kind.label), \(ByteCountFormatter.string(fromByteCount: Int64(part.size), countStyle: .file))"
                            + (part.flags.isEmpty ? "" : " — " + part.flags.joined(separator: ", ")))
            }
        }
    }

    private var protos: some View {
        DetailSection(title: "Newton Protos Used (\(info.protosUsed.count))") {
            Text(info.protosUsed.joined(separator: ", "))
                .font(.callout)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var file: some View {
        let exists = FileManager.default.fileExists(atPath: item.filePath)
        return DetailSection(title: "File") {
            InfoRow("Location", item.filePath)
            if !exists {
                Label("The file is missing. It may have been moved or deleted. Add it to the library again to put it back.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundColor(.orange)
            }
            InfoRow("Original name", item.originalName)
            InfoRow("Added", item.dateAdded.formatted(date: .long, time: .shortened))
            InfoRow("SHA-256", item.sha256)
            HStack {
                Button("Show in Finder") { store.reveal([item.id]) }
                    .disabled(!exists)
                Button("Remove…", action: onRemove)
            }
            .padding(.top, 4)
        }
    }

    private var notes: some View {
        DetailSection(title: "Notes") {
            Text(item.notes)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Several packages selected: change their Newton OS or publisher together.
struct MultipleSelectionView: View {
    @ObservedObject var store: LibraryStore
    let items: [LibraryItem]
    var onRemove: () -> Void
    @State private var publisher = ""
    @State private var newKind = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(items.count) Packages Selected")
                .font(.title2.weight(.semibold))
            Text(ByteCountFormatter.string(fromByteCount: Int64(items.reduce(0) { $0 + $1.fileSize }), countStyle: .file))
                .foregroundColor(.secondary)
            DetailSection(title: "Change All") {
                HStack {
                    Menu("Set Min OS") {
                        Button("As Read from Each Package") { set(.minOS, nil) }
                        Divider()
                        ForEach(NewtonOSVersion.all, id: \.self) { v in
                            Button(NewtonOSVersion.label(v)) { set(.minOS, v) }
                        }
                    }
                    .frame(maxWidth: 160)
                    Menu("Set Max OS") {
                        Button("As Read from Each Package") { set(.maxOS, nil) }
                        Divider()
                        Button("No Limit") { set(.maxOS, "") }
                        ForEach(NewtonOSVersion.all.filter { $0 != "1.x" }, id: \.self) { v in
                            Button(v) { set(.maxOS, v) }
                        }
                    }
                    .frame(maxWidth: 160)
                }
                HStack {
                    Menu("Set Kind") {
                        Button("As Read from Each Package") { set(.kind, nil) }
                        Divider()
                        ForEach(PackageKind.allCases) { kind in
                            Button(kind.label) { set(.kind, kind.rawValue) }
                        }
                        if !store.customKinds.isEmpty {
                            Divider()
                            ForEach(store.customKinds, id: \.self) { name in
                                Button(name) { set(.kind, name) }
                            }
                        }
                    }
                    .frame(maxWidth: 160)
                    TextField("New kind", text: $newKind, prompt: Text("New kind"))
                        .frame(maxWidth: 140)
                    Button("Set") { set(.kind, LibraryItem.kindKey(for: newKind)) }
                        .disabled(newKind.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    TextField("Developer", text: $publisher, prompt: Text("Developer"))
                        .frame(maxWidth: 240)
                    Button("Set Developer") {
                        let name = publisher.trimmingCharacters(in: .whitespaces)
                        store.updateAll(Set(items.map(\.id))) { $0.publisherOverride = name.isEmpty ? nil : name }
                    }
                }
                Text("Leave the developer empty to go back to what was read from each package.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Button("Show in Finder") { store.reveal(Set(items.map(\.id))) }
                Button("Remove…", action: onRemove)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Sets a field on every selected package; nil goes back to what was read from each.
    private func set(_ field: InfoField, _ value: String?) {
        store.updateAll(Set(items.map(\.id))) {
            $0.edits[field.rawValue] = value == nil || value == $0.detected(field) ? nil : value
        }
    }
}

// MARK: - Layout pieces

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Divider()
            content
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var edited = false

    init(_ label: String, _ value: String, edited: Bool = false) {
        self.label = label
        self.value = value
        self.edited = edited
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if edited {
                Image(systemName: "pencil")
                    .foregroundColor(.accentColor)
                    .help("Changed by you")
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}

/// The packages this one belongs with: its main package, its add-ons, and any
/// app it needs that isn't in the library. Click one to select it.
struct RelatedPackagesView: View {
    @ObservedObject var store: LibraryStore
    let item: LibraryItem

    var body: some View {
        let main = store.mainPackage(of: item)
        let addOns = store.addOns(of: item)
        let needs = store.relations.needs[item.id] ?? []
        if main != nil || !addOns.isEmpty || !needs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Related Packages")
                    .font(.headline)
                Divider()
                if let main = main {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(store.relations.probable.contains(item.id) ? "Probably goes with" : "Add-on for")
                            .foregroundColor(.secondary)
                        PackageLink(store: store, item: main)
                    }
                }
                if !addOns.isEmpty {
                    Text(addOns.count == 1 ? "Add-on:" : "Add-ons (\(addOns.count)):")
                        .foregroundColor(.secondary)
                    ForEach(addOns) { addOn in
                        HStack(spacing: 6) {
                            PackageLink(store: store, item: addOn)
                            if store.relations.probable.contains(addOn.id) {
                                Text("(probably)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.leading, 12)
                    }
                }
                ForEach(needs, id: \.self) { name in
                    Label("Needs \(name), which isn't in your library", systemImage: "exclamationmark.circle")
                        .foregroundColor(.orange)
                }
                if item.mainPackageChoice != nil {
                    Text("Set by you in Get Info.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .font(.callout)
        }
    }
}

/// A related package's icon and title; clicking selects it in the list.
struct PackageLink: View {
    @ObservedObject var store: LibraryStore
    let item: LibraryItem

    var body: some View {
        Button {
            store.select(item.id)
        } label: {
            HStack(spacing: 4) {
                PackageIcon(item: item, size: 16)
                Text(item.title)
                    .underline()
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .help("Show \(item.title)")
    }
}
