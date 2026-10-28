import SwiftUI

/// Everything read from a package, all of it editable, with Save and Cancel.
/// Opens when you drop a single package, or with Get Info (⌘I).
///
/// Edits are kept in the library, not written into the package file. A field
/// you change gets a ↺ button that puts back what was read from the package.
struct InfoWindow: View {
    @ObservedObject var store: LibraryStore
    let item: LibraryItem
    @Environment(\.dismiss) private var dismiss

    @State private var values: [InfoField: String]
    @State private var notes: String
    /// Typing the name of a new kind
    @State private var namingKind = false
    /// The main package (saved with the rest)
    @State private var mainChoice: MainPackageChoice
    @State private var choosingMain = false
    private static let newKindTag = "\u{1}new kind"

    init(store: LibraryStore, item: LibraryItem) {
        self.store = store
        self.item = item
        var values: [InfoField: String] = [:]
        for field in InfoField.allCases { values[field] = item.value(field) }
        values[.kind] = item.kindKey   // a kind typed as "Game" is the built-in Game kind
        _values = State(initialValue: values)
        _notes = State(initialValue: item.notes)
        _mainChoice = State(initialValue: MainPackageChoice(stored: item.mainPackageChoice))
    }

    private var info: PackageInfo { item.info }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    general
                    related
                    identity
                    notesSection
                    readOnly
                }
                .padding(16)
            }
            Divider()
            buttons
                .padding(12)
        }
        .frame(width: 620, height: 680)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            PackageIcon(item: item, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(values[.title].flatMap { $0.isEmpty ? nil : $0 } ?? item.originalName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(item.originalName)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var general: some View {
        FormSection(title: "General") {
            textRow("Title", .title)
            textRow("Developer", .publisher)
            textRow("Author", .author)
            textRow("Language", .language)
            row("Kind", .kind, detectedText: info.kind.label) {
                Picker("", selection: kindChoice) {
                    ForEach(PackageKind.allCases) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                    let custom = kindsToOffer
                    if !custom.isEmpty {
                        Divider()
                        ForEach(custom, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Divider()
                    Text("New Kind…").tag(Self.newKindTag)
                }
                .labelsHidden()
                .frame(maxWidth: 180)
                if namingKind {
                    TextField("", text: text(.kind), prompt: Text("Name of the new kind"))
                        .frame(maxWidth: 180)
                }
            }
            row("Min OS", .minOS, detectedText: NewtonOSVersion.label(item.detected(.minOS))) {
                Picker("", selection: text(.minOS)) {
                    Text("Not known").tag("")
                    ForEach(NewtonOSVersion.all, id: \.self) { v in
                        Text(NewtonOSVersion.label(v)).tag(v)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 140)
            }
            row("Max OS", .maxOS, detectedText: item.detected(.maxOS).isEmpty ? "no limit" : item.detected(.maxOS)) {
                Picker("", selection: text(.maxOS)) {
                    Text("No limit known").tag("")
                    ForEach(NewtonOSVersion.all.filter { $0 != "1.x" }, id: \.self) { v in
                        Text(v).tag(v)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 140)
                if !osRangeIsValid {
                    Text("Older than the minimum")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("Listed under \(NewtonOSVersion.group(min: values[.minOS] ?? "", max: values[.maxOS] ?? "")?.label ?? "Unknown")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            row("Version", .version, detectedText: item.detected(.version)) {
                TextField("", text: text(.version))
                    .frame(width: 100)
                Text(item.detected(.version) == String(info.version) ? "" : "Header: \(info.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            row("Created", .created, detectedText: info.creationDate.map(Self.formatDate) ?? "none") {
                Toggle("", isOn: hasCreationDate)
                    .labelsHidden()
                if hasCreationDate.wrappedValue {
                    DatePicker("", selection: creationDate)
                        .labelsHidden()
                        .frame(maxWidth: 220)
                } else {
                    Text("Unknown")
                        .foregroundColor(.secondary)
                }
            }
            row("Copyright", .copyright, detectedText: info.copyright) {
                TextEditor(text: text(.copyright))
                    .font(.body)
                    .frame(height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            }
        }
    }

    private var related: some View {
        let addOns = store.addOns(of: item)
        let needs = store.relations.needs[item.id] ?? []
        return FormSection(title: "Related Packages") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Main package")
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
                Text(mainChoiceLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose…") { choosingMain = true }
                    .help("Search the library for the package this one is an add-on for")
                Spacer(minLength: 0)
                Button {
                    mainChoice = .automatic
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.borderless)
                .help("Work out the main package from the package itself")
                .opacity(mainChoice == .automatic ? 0 : 1)
                .disabled(mainChoice == .automatic)
                .frame(width: 18)
            }
            Text("An add-on is listed with its main package and stored in the same folder.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 108)
            if !addOns.isEmpty {
                fixedRow(addOns.count == 1 ? "Add-on" : "Add-ons", addOns.map(\.title).joined(separator: ", "))
            }
            ForEach(needs, id: \.self) { name in
                fixedRow("Needs", "\(name), which isn't in your library")
            }
        }
        .sheet(isPresented: $choosingMain) {
            MainPackageChooser(store: store, packages: [item], current: mainChoice) { mainChoice = $0 }
        }
    }

    private var mainChoiceLabel: String {
        switch mainChoice {
        case .automatic:
            let found = store.foundRelations.main[item.id].flatMap { store.item($0) }
            return "Automatic (\(found?.title ?? "none found"))"
        case .none:
            return "None: it stands alone"
        case .package(let sha):
            return store.item(withSHA256: sha)?.title ?? "A package no longer in the library"
        }
    }

    private var identity: some View {
        FormSection(title: "Package") {
            textRow("Package name", .packageName)
            textRow("Signature", .signature)
            textRow("Extras name", .extrasName)
            textRow("App symbol", .appSymbol)
            textRow("ISBN", .isbn)
        }
    }

    private var notesSection: some View {
        FormSection(title: "Notes") {
            TextEditor(text: $notes)
                .font(.body)
                .frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
        }
    }

    private var readOnly: some View {
        FormSection(title: "Read from the Package") {
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
            .padding(.bottom, 4)
            fixedRow("Size", ByteCountFormatter.string(fromByteCount: Int64(info.fileSize), countStyle: .file))
            fixedRow("Format", info.formatVersion == 1 ? "package1 (Newton OS 2.0 and later)" : "package0")
            if !info.packageFlags.isEmpty { fixedRow("Flags", info.packageFlags.joined(separator: ", ")) }
            fixedRow("Native code", info.hasNativeCode ? "Yes (ARM)" : "No")
            ForEach(Array(info.parts.enumerated()), id: \.offset) { index, part in
                fixedRow(index == 0 ? (info.parts.count == 1 ? "Part" : "Parts") : "",
                         (part.type.isEmpty ? "untyped" : "'\(part.type)'") + ": \(part.kind.label), "
                            + ByteCountFormatter.string(fromByteCount: Int64(part.size), countStyle: .file)
                            + (part.flags.isEmpty ? "" : " — " + part.flags.joined(separator: ", ")))
            }
            if !info.protosUsed.isEmpty { fixedRow("Protos", info.protosUsed.joined(separator: ", ")) }
            fixedRow("Location", item.filePath)
            fixedRow("Added", Self.formatDate(item.dateAdded))
            fixedRow("SHA-256", item.sha256)
            ForEach(info.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundColor(.orange)
            }
        }
    }

    private var buttons: some View {
        HStack {
            Button("Use Package Values") {
                for field in InfoField.allCases { values[field] = item.detected(field) }
                namingKind = false
                mainChoice = .automatic
            }
            .help("Put back everything as it was read from the package (your notes are kept)")
            .disabled(InfoField.allCases.allSatisfy { values[$0] == item.detected($0) } && mainChoice == .automatic)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(!osRangeIsValid || !kindIsValid)
        }
    }

    // MARK: Rows

    private func textRow(_ label: String, _ field: InfoField) -> some View {
        row(label, field, detectedText: item.detected(field)) {
            TextField("", text: text(field), prompt: Text(item.detected(field)))
        }
    }

    /// A label, the field, and a ↺ button when it differs from the package.
    private func row<Content: View>(_ label: String, _ field: InfoField, detectedText: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            content()
            Spacer(minLength: 0)
            Button {
                values[field] = item.detected(field)
                if field == .kind { namingKind = false }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.borderless)
            .help("Use what was read from the package: \(detectedText.isEmpty ? "nothing" : detectedText)")
            .opacity(values[field] == item.detected(field) ? 0 : 1)
            .disabled(values[field] == item.detected(field))
            .frame(width: 18)
        }
    }

    private func fixedRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    // MARK: Values

    private func text(_ field: InfoField) -> Binding<String> {
        Binding(get: { values[field] ?? "" }, set: { values[field] = $0 })
    }

    /// The maximum mustn't be older than the minimum.
    private var osRangeIsValid: Bool {
        guard let low = NewtonOSVersion.rank(values[.minOS] ?? ""),
              let high = NewtonOSVersion.rank(values[.maxOS] ?? "") else { return true }
        return high >= low
    }

    /// The Kind menu: a built-in kind, a kind you named before, or "New Kind…".
    private var kindChoice: Binding<String> {
        Binding(
            get: { namingKind ? Self.newKindTag : (values[.kind] ?? "") },
            set: { choice in
                if choice == Self.newKindTag {
                    namingKind = true
                    values[.kind] = ""
                } else {
                    namingKind = false
                    values[.kind] = choice
                }
            })
    }

    /// Kinds you've named, for the Kind menu (including this package's own).
    private var kindsToOffer: [String] {
        var kinds = store.customKinds
        let current = values[.kind] ?? ""
        if !namingKind, !current.isEmpty, PackageKind(rawValue: current) == nil, !kinds.contains(current) {
            kinds.append(current)
        }
        return kinds
    }

    private var kindIsValid: Bool {
        !(values[.kind] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasCreationDate: Binding<Bool> {
        Binding(
            get: { !(values[.created] ?? "").isEmpty },
            set: { on in
                values[.created] = on
                    ? String((item.info.creationDate ?? Date()).timeIntervalSinceReferenceDate)
                    : ""
            })
    }

    private var creationDate: Binding<Date> {
        Binding(
            get: { Double(values[.created] ?? "").map { Date(timeIntervalSinceReferenceDate: $0) } ?? Date() },
            set: { values[.created] = String($0.timeIntervalSinceReferenceDate) })
    }

    private func save() {
        var edits: [String: String] = [:]
        for field in InfoField.allCases where field != .newtonOS {
            var value = values[field] ?? ""
            if field != .copyright { value = value.trimmingCharacters(in: .whitespacesAndNewlines) }
            if field == .kind { value = LibraryItem.kindKey(for: value) }
            if field == .created, let a = Double(value), let b = Double(item.detected(field)), abs(a - b) < 60 {
                continue   // the date picker only shows minutes, so this is the same date
            }
            if value != item.detected(field) { edits[field.rawValue] = value }
        }
        if let main = mainChoice.stored { edits["mainPackage"] = main }
        store.saveInfo(item.id, edits: edits, notes: notes)
        dismiss()
    }

    static func formatDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }
}

private struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Divider()
            content
        }
    }
}
