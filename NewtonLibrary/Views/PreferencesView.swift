import SwiftUI

struct PreferencesView: View {
    @ObservedObject var store: LibraryStore
    @AppStorage(IconBackground.key) private var iconBackground = IconBackground.standard

    var body: some View {
        let folder = store.libraryFolder
        let outside = store.items.filter { !store.isInLibraryFolder($0) }.count
        VStack(alignment: .leading, spacing: 12) {
            Text("Library Folder")
                .font(.headline)
            Text("When you add a package, a copy is kept here, in a folder for its developer, then its kind, then its title.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: FileManager.default.fileExists(atPath: folder.path)
                                                       ? folder.path : NSHomeDirectory()))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(folder.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(folder.path)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Button("Choose…", action: chooseFolder)
                Button("Show in Finder", action: store.revealLibraryFolder)
                Spacer()
                Button("Use Default") { store.setLibraryFolder(LibraryStore.defaultFolder) }
                    .disabled(folder.standardizedFileURL == LibraryStore.defaultFolder.standardizedFileURL)
            }
            Divider()
            HStack {
                Text("Icon background:")
                ColorPicker("", selection: Binding(
                    get: { IconBackground.color(from: iconBackground) },
                    set: { iconBackground = IconBackground.string(from: $0) }), supportsOpacity: false)
                    .labelsHidden()
                Button("Reset") { iconBackground = IconBackground.standard }
                    .disabled(iconBackground == IconBackground.standard)
                Spacer()
            }
            Text("The colour behind the packages’ Newton icons. The standard one is like a MessagePad 2100’s backlight.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            if outside > 0 {
                Text(outside == 1
                     ? "1 package in the library is kept in a different folder."
                     : "\(outside) packages in the library are kept in other folders.")
                    .foregroundColor(.secondary)
                Button("Copy Them into This Folder", action: store.copyAllIntoLibraryFolder)
                    .disabled(store.isBusy)
            } else {
                Text("Every package in the library is kept in this folder.")
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Library Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = store.libraryFolder
        if panel.runModal() == .OK, let url = panel.url {
            store.setLibraryFolder(url)
        }
    }
}
