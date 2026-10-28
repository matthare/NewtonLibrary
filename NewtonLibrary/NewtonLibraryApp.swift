import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    // One library window: quit when it's closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugSnapshot.startIfAsked()
        #endif
    }
}

@main
struct NewtonLibraryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LibraryStore.shared

    var body: some Scene {
        WindowGroup("Newton Library") {
            ContentView(store: store)
                .frame(minWidth: 1000, idealWidth: 1280, minHeight: 500, idealHeight: 720)
                // Packages dropped on the Dock icon, or opened with Newton Library from
                // the Finder, are added to the library in this window (no new windows)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL { url in store.open(url) }
                .background(WindowMemory(firstSize: NSSize(width: 1280, height: 720)))
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Newton Library", action: showAbout)
            }
            CommandGroup(replacing: .newItem) {
                Button("Add to Library…", action: store.chooseFilesToAdd)
                    .keyboardShortcut("o")
                Divider()
                Button("Get Info", action: store.showInfo)
                    .keyboardShortcut("i")
                    .disabled(store.selection.count != 1 || store.infoWindow != nil)
                Button("Set Main Package…", action: store.chooseMainPackage)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(store.selection.isEmpty || store.infoWindow != nil || store.mainPackageChooser != nil)
            }
            CommandMenu("Library") {
                Button("Show Library Folder in Finder", action: store.revealLibraryFolder)
                Divider()
                Button("Check for Missing Files", action: store.checkForMissingFiles)
                    .disabled(store.isBusy || store.items.isEmpty)
                Button("Organize Library Folder", action: store.organizeAll)
                    .disabled(store.isBusy || store.items.isEmpty)
                Button("Re-read All Packages", action: store.rereadAll)
                    .disabled(store.isBusy || store.items.isEmpty)
                Button("Copy All Packages into Library Folder", action: store.copyAllIntoLibraryFolder)
                    .disabled(store.isBusy || store.items.isEmpty)
            }
            SidebarCommands()
        }

        Settings {
            PreferencesView(store: store)
        }
    }

    private func showAbout() {
        let credits = NSAttributedString(
            string: "Organises Apple Newton software packages.\n\nWritten by Matt Hare and AI agent Claude",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

/// Remembers the window's size and place, how wide the sidebar and the
/// details pane are (and whether the sidebar is hidden), and the list's column
/// widths, and puts them back the next time the app opens.
///
/// macOS's own window restoring isn't enough: it's off whenever "Close windows
/// when quitting an application" is set in System Settings (the standard
/// setting), and it never covers the panes or columns. The first time, the
/// window opens at a comfortable size (SwiftUI on macOS 12 would open it at its
/// minimum size).
private struct WindowMemory: NSViewRepresentable {
    let firstSize: NSSize

    func makeNSView(context: Context) -> NSView { Hook(firstSize: firstSize) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Hook: NSView {
        let firstSize: NSSize
        private var started = false
        private var restoredTables: Set<ObjectIdentifier> = []
        private var observers: [NSObjectProtocol] = []
        private let defaults = UserDefaults.standard
        private static let frameKey = "LibraryWindowFrame"
        private static let panesKey = "LibraryPaneWidths"         // [sidebar, details]
        private static let sidebarHiddenKey = "LibrarySidebarHidden"
        private static let columnsKey = "LibraryColumns"         // [[title, width]]

        init(firstSize: NSSize) {
            self.firstSize = firstSize
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = window, !started else { return }
            started = true
            #if DEBUG
            if defaults.bool(forKey: "DebugForgetWindow") {
                [Self.frameKey, Self.panesKey, Self.sidebarHiddenKey, Self.columnsKey].forEach(defaults.removeObject)
            }
            #endif
            // After SwiftUI has laid the window out, or it would undo this
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.restore(window)
            }
        }

        // The window

        private func restore(_ window: NSWindow) {
            if let saved = defaults.string(forKey: Self.frameKey) {
                var frame = NSRectFromString(saved)
                // Still on a screen (one may have been unplugged since)
                let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
                if let visible = screen?.visibleFrame {
                    frame.size.width = min(frame.width, visible.width)
                    frame.size.height = min(frame.height, visible.height)
                    frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
                    frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
                }
                window.setFrame(frame, display: true)
            } else {
                window.setContentSize(firstSize)
                window.center()
            }
            // The panes, once the window is its new size
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.restorePanes(in: window)
                self.restoreColumns(in: window)
                self.startSaving(window)
            }
        }

        private func startSaving(_ window: NSWindow) {
            let center = NotificationCenter.default
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.saveFrame(window)
                })
            }
            if let split = Self.splitView(in: window) {
                observers.append(center.addObserver(forName: NSSplitView.didResizeSubviewsNotification,
                                                    object: split, queue: .main) { [weak self] _ in
                    self?.savePanes(split)
                })
            }
            // The list's columns: its table can be replaced, so watch them all
            observers.append(center.addObserver(forName: NSTableView.columnDidResizeNotification, object: nil,
                                                queue: .main) { [weak self] note in
                guard let table = note.object as? NSTableView, table.window === window,
                      table.numberOfColumns > 1 else { return }
                self?.saveColumns(table)
            })
            // A new table (SwiftUI may build another) gets the saved columns
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: nil,
                                                queue: .main) { [weak self] note in
                guard let table = note.object as? NSTableView, table.window === window else { return }
                self?.restoreColumns(in: window)
            })
            // And everything once more on the way out (columns changed other than
            // by dragging their headers send no notice)
            let saveAll: (Notification) -> Void = { [weak self] _ in self?.saveAll(window) }
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                queue: .main, using: saveAll))
            observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                queue: .main, using: saveAll))
            saveFrame(window)
        }

        private func saveAll(_ window: NSWindow) {
            saveFrame(window)
            if let split = Self.splitView(in: window) { savePanes(split) }
            if let table = Self.listTable(in: window) { saveColumns(table) }
        }

        private func saveFrame(_ window: NSWindow) {
            guard window.isVisible, !window.styleMask.contains(.fullScreen) else { return }
            defaults.set(NSStringFromRect(window.frame), forKey: Self.frameKey)
        }

        // The sidebar, list and details panes

        /// The split view holding the three panes.
        private static func splitView(in window: NSWindow) -> NSSplitView? {
            func search(_ v: NSView) -> NSSplitView? {
                if let s = v as? NSSplitView, s.arrangedSubviews.count == 3 { return s }
                for sub in v.subviews { if let s = search(sub) { return s } }
                return nil
            }
            return window.contentView.flatMap(search)
        }

        private func restorePanes(in window: NSWindow) {
            guard let split = Self.splitView(in: window) else { return }
            let widths = (defaults.array(forKey: Self.panesKey) ?? []).compactMap(Self.number)
            // The sidebar's width, then hide it if it was hidden, then the details
            // (the list takes what's left)
            if widths.count == 2 {
                split.setPosition(CGFloat(widths[0]), ofDividerAt: 0)
            }
            if defaults.bool(forKey: Self.sidebarHiddenKey),
               let controller = split.delegate as? NSSplitViewController,
               let sidebar = controller.splitViewItems.first, !sidebar.isCollapsed {
                sidebar.isCollapsed = true
                split.layoutSubtreeIfNeeded()
            }
            if widths.count == 2 {
                split.setPosition(split.bounds.width - CGFloat(widths[1]) - split.dividerThickness, ofDividerAt: 1)
            }
        }

        private func savePanes(_ split: NSSplitView) {
            let panes = split.arrangedSubviews
            guard panes.count == 3, split.window?.isVisible == true else { return }
            let sidebarHidden = split.isSubviewCollapsed(panes[0]) || panes[0].frame.width < 1
            defaults.set(sidebarHidden, forKey: Self.sidebarHiddenKey)
            // A hidden sidebar keeps the width it had
            var widths = (defaults.array(forKey: Self.panesKey) ?? []).compactMap(Self.number)
            if widths.count != 2 { widths = [Double(panes[0].frame.width), Double(panes[2].frame.width)] }
            if !sidebarHidden { widths[0] = Double(panes[0].frame.width) }
            if !split.isSubviewCollapsed(panes[2]) { widths[1] = Double(panes[2].frame.width) }
            defaults.set(widths, forKey: Self.panesKey)
        }

        /// A saved number (as text if it was set with the defaults tool).
        private static func number(_ value: Any) -> Double? {
            (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        }

        // The list's columns

        private static func listTable(in window: NSWindow) -> NSTableView? {
            func search(_ v: NSView) -> NSTableView? {
                if let t = v as? NSTableView, t.numberOfColumns > 1 { return t }
                for sub in v.subviews { if let t = search(sub) { return t } }
                return nil
            }
            return window.contentView.flatMap(search)
        }

        /// Puts back the columns' widths. (Their order isn't: SwiftUI puts the
        /// columns back in its own order whenever the list changes.)
        private func restoreColumns(in window: NSWindow) {
            guard let table = Self.listTable(in: window),
                  !restoredTables.contains(ObjectIdentifier(table)) else { return }
            restoredTables.insert(ObjectIdentifier(table))
            guard let saved = defaults.array(forKey: Self.columnsKey) as? [[Any]] else { return }
            for entry in saved {
                guard entry.count == 2, let title = entry[0] as? String, let width = Self.number(entry[1]),
                      let column = table.tableColumns.first(where: { $0.title == title }) else { continue }
                column.width = min(max(CGFloat(width), column.minWidth), column.maxWidth)
            }
        }

        private func saveColumns(_ table: NSTableView) {
            // Not while it's being set up
            guard restoredTables.contains(ObjectIdentifier(table)) else { return }
            defaults.set(table.tableColumns.map { [$0.title, Double($0.width)] }, forKey: Self.columnsKey)
        }
    }
}
