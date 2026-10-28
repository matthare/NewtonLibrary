import SwiftUI

/// The list of packages: sortable columns, like a music library.
struct PackageTable: View {
    let items: [LibraryItem]
    /// The package an add-on belongs to, for the link mark after its title.
    var mainPackage: (LibraryItem) -> LibraryItem?
    @Binding var selection: Set<Int64>
    @Binding var sortOrder: [KeyPathComparator<LibraryItem>]
    /// Whether packages show their add-ons under them (for applications and games).
    var grouped = false
    /// How far each row is indented (an add-on is one deeper than its package).
    var depth: [Int64: Int] = [:]
    /// How many add-ons each package has.
    var addOnCount: [Int64: Int] = [:]
    /// Packages whose add-ons are showing.
    var expanded: Set<Int64> = []
    /// Shows or hides a package's add-ons.
    var onToggle: (LibraryItem) -> Void = { _ in }
    var onDelete: () -> Void

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        Table(items, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title) { item in titleCell(item) }
                .width(min: 140, ideal: 220)
            TableColumn("Developer", value: \.publisher)
                .width(min: 80, ideal: 160)
            TableColumn("Min OS", value: \.minOSRank) { item in minOSCell(item) }
                .width(min: 45, ideal: 60)
            TableColumn("Max OS", value: \.maxOSRank) { item in maxOSCell(item) }
                .width(min: 45, ideal: 60)
            TableColumn("Kind", value: \.kindLabel)
                .width(min: 60, ideal: 90)
            TableColumn("Language", value: \.language) { item in languageCell(item) }
                .width(min: 50, ideal: 70)
            TableColumn("Version", value: \.versionSortKey) { item in Text(item.version) }
                .width(min: 40, ideal: 55)
            TableColumn("Size", value: \.fileSize) { item in Text(Self.size(item)) }
                .width(min: 50, ideal: 70)
            TableColumn("Created", value: \.created) { item in Text(Self.date(item.creationDate)) }
                .width(min: 70, ideal: 95)
            TableColumn("Added", value: \.dateAdded) { item in Text(Self.date(item.dateAdded)) }
                .width(min: 70, ideal: 95)
        }
        .onDeleteCommand(perform: onDelete)
        // Drag rows out to the Finder and other apps
        .background(TableDragSupport(items: items))
    }

    // Cells (kept out of the table, which is otherwise too much for the compiler)

    /// The icon and title together (a table takes ten columns at most).
    private func titleCell(_ item: LibraryItem) -> some View {
        HStack(spacing: 4) {
            if grouped {
                disclosure(item)
            }
            PackageIcon(item: item, size: 18)
                .padding(.trailing, 2)
            Text(item.title)
            if let main = mainPackage(item) {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                    .help("Goes with \(main.title)")
            }
        }
    }

    /// Indentation, and the triangle that shows a package's add-ons.
    @ViewBuilder
    private func disclosure(_ item: LibraryItem) -> some View {
        let count = addOnCount[item.id] ?? 0
        let isOpen = expanded.contains(item.id)
        Spacer().frame(width: CGFloat(depth[item.id] ?? 0) * 16)
        if count > 0 {
            Button { onToggle(item) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 12, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help(isOpen ? "Hide its add-ons" : "Show its \(count) add-on\(count == 1 ? "" : "s")")
        } else {
            Spacer().frame(width: 12)
        }
    }

    /// A value that may be set by you, unknown, or read from the package.
    private func valueCell(_ item: LibraryItem, _ field: InfoField, empty: String,
                           unknownHelp: String, help: String) -> some View {
        let value = item.value(field)
        let color: Color = item.isEdited(field) ? .accentColor : (value.isEmpty ? .secondary : .primary)
        return Text(value.isEmpty ? empty : value)
            .foregroundColor(color)
            .help(item.isEdited(field) ? "Set by you" : (value.isEmpty ? unknownHelp : help))
    }

    private func minOSCell(_ item: LibraryItem) -> some View {
        valueCell(item, .minOS, empty: "?", unknownHelp: "Not known", help: "Oldest Newton OS it works with")
    }

    private func maxOSCell(_ item: LibraryItem) -> some View {
        valueCell(item, .maxOS, empty: "—", unknownHelp: "No limit known", help: "Newest Newton OS it works with")
    }

    private func languageCell(_ item: LibraryItem) -> some View {
        valueCell(item, .language, empty: "—", unknownHelp: "Not known", help: "Worked out from the package's text")
    }

    private static func size(_ item: LibraryItem) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file)
    }

    private static func date(_ date: Date?) -> String {
        date.map { dateFormat.string(from: $0) } ?? ""
    }
}
