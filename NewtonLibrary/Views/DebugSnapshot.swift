#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: launched with -SnapshotPath <file.png>, the app saves a
/// picture of its window there every second, plus a list of its scroll views
/// and where they're scrolled to, for checking the layout from scripts.
enum DebugSnapshot {
    static func startIfAsked() {
        // -SelectSidebarRow N selects row N of the sidebar, as a click would
        let row = UserDefaults.standard.integer(forKey: "SelectSidebarRow")
        if row > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                func find(_ v: NSView) -> NSTableView? {
                    if let t = v as? NSTableView { return t }
                    for s in v.subviews { if let t = find(s) { return t } }
                    return nil
                }
                guard let content = NSApp.windows.first(where: { $0.isVisible })?.contentView,
                      let sidebar = find(content) else { return }
                sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
        // -DebugAdd <folder> adds each file in it, as if they'd been dropped together;
        // -DebugCancelAfter <seconds> then clicks the progress sheet's Cancel
        if let folder = UserDefaults.standard.string(forKey: "DebugAdd") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let urls = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted()
                    .map { URL(fileURLWithPath: folder).appendingPathComponent($0) }
                LibraryStore.shared.add(urls)
                let after = UserDefaults.standard.double(forKey: "DebugCancelAfter")
                if after > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + after) { LibraryStore.shared.cancelAdding() }
                }
            }
        }
        // -DebugAddFolder <folder> adds that folder, as if it had been dropped by itself
        if let folder = UserDefaults.standard.string(forKey: "DebugAddFolder") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NSApp.activate(ignoringOtherApps: true)
                LibraryStore.shared.add([URL(fileURLWithPath: folder)])
            }
        }
        // -DebugSelect <title> selects that package
        if let title = UserDefaults.standard.string(forKey: "DebugSelect") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if let item = LibraryStore.shared.items.first(where: { $0.title == title }) {
                    LibraryStore.shared.select(item.id)
                }
            }
        }
        // -DebugDrag <file> writes what dragging the first rows would hand out
        if let out = UserDefaults.standard.string(forKey: "DebugDrag") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                func tables(_ v: NSView) -> [NSTableView] {
                    ((v as? NSTableView).map { [$0] } ?? []) + v.subviews.flatMap(tables)
                }
                guard let content = NSApp.windows.first(where: { $0.isVisible })?.contentView else { return }
                var lines: [String] = []
                for t in tables(content) {
                    lines.append("\(type(of: t)) columns=\(t.numberOfColumns) rows=\(t.numberOfRows) "
                                 + "dataSource=\(type(of: t.dataSource as AnyObject))")
                    for row in 0..<min(3, t.numberOfRows) {
                        var writer = t.dataSource?.tableView?(t, pasteboardWriterForRow: row)
                        if let o = t as? NSOutlineView, let item = o.item(atRow: row),
                           let ds = o.dataSource, ds.responds(to: #selector(NSOutlineViewDataSource.outlineView(_:pasteboardWriterForItem:))) {
                            writer = ds.outlineView?(o, pasteboardWriterForItem: item)
                        }
                        lines.append("  row \(row): \((writer as? NSURL)?.path ?? "nil")")
                    }
                }
                // Drag-related methods SwiftUI's table classes override
                for t in tables(content) where t.numberOfColumns > 1 {
                    lines.append("isa: \(NSStringFromClass(object_getClass(t)!)) canDrag row 0: "
                                 + "\(t.canDragRows(with: IndexSet(integer: 0), at: .zero))")
                    var cls: AnyClass? = type(of: t)
                    while let c = cls, c != NSTableView.self {
                        var count: UInt32 = 0
                        if let methods = class_copyMethodList(c, &count) {
                            let names = (0..<Int(count)).map { NSStringFromSelector(method_getName(methods[$0])) }
                                .filter { $0.lowercased().contains("drag") || $0.contains("mouseDown") || $0.contains("Pasteboard") }
                            lines.append("class \(c): \(names.sorted().joined(separator: ", "))")
                            free(methods)
                        }
                        cls = class_getSuperclass(c)
                    }
                    if let d = t.delegate {
                        var count: UInt32 = 0
                        if let methods = class_copyMethodList(type(of: d), &count) {
                            let names = (0..<Int(count)).map { NSStringFromSelector(method_getName(methods[$0])) }
                                .filter { $0.lowercased().contains("drag") || $0.contains("Pasteboard") }
                            lines.append("delegate \(type(of: d)): \(names.sorted().joined(separator: ", "))")
                            free(methods)
                        }
                    }
                    if let o = (t.dataSource as? DragDataSource)?.original {
                        var count: UInt32 = 0
                        if let methods = class_copyMethodList(type(of: o), &count) {
                            let names = (0..<Int(count)).map { NSStringFromSelector(method_getName(methods[$0])) }
                                .filter { $0.lowercased().contains("drag") || $0.contains("Pasteboard") || $0.contains("writeItems") }
                            lines.append("original dataSource \(type(of: o)): \(names.sorted().joined(separator: ", "))")
                            free(methods)
                        }
                    }
                }
                try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            }
        }
        // -DebugMouseDrag <file> fakes dragging row 1 of the list, and writes
        // what the drag handed out
        if let out = UserDefaults.standard.string(forKey: "DebugMouseDrag") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                func tables(_ v: NSView) -> [NSTableView] {
                    ((v as? NSTableView).map { [$0] } ?? []) + v.subviews.flatMap(tables)
                }
                guard let window = NSApp.windows.first(where: { $0.isVisible }), let content = window.contentView,
                      let table = tables(content).first(where: { $0.numberOfColumns > 1 }) else { return }
                // Clicks only reach a window in front
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                let rect = table.rect(ofRow: 1)
                let start = table.convert(NSPoint(x: rect.midX - 100, y: rect.midY), to: nil)
                func event(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent? {
                    NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    try? (DragDataSource.debugLog.isEmpty ? ["no drag started"] : DragDataSource.debugLog)
                        .joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
                }
                for i in 1...12 {
                    if let e = event(.leftMouseDragged, NSPoint(x: start.x + CGFloat(i * 8), y: start.y - CGFloat(i * 6))) {
                        NSApp.postEvent(e, atStart: false)
                    }
                }
                if let up = event(.leftMouseUp, NSPoint(x: start.x + 96, y: start.y - 72)) { NSApp.postEvent(up, atStart: false) }
                if let down = event(.leftMouseDown, start) { window.sendEvent(down) }
            }
        }
        // -DebugCanDrag <file> asks the list what AppKit asks when a drag starts
        // (can row 1 be dragged, and what file does it hand out), and whether the
        // table is still its own class and an NSResponder
        if let out = UserDefaults.standard.string(forKey: "DebugCanDrag") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                func tables(_ v: NSView) -> [NSTableView] {
                    ((v as? NSTableView).map { [$0] } ?? []) + v.subviews.flatMap(tables)
                }
                guard let content = NSApp.windows.first(where: { $0.isVisible })?.contentView,
                      let table = tables(content).first(where: { $0.numberOfColumns > 1 }) else { return }
                // The selected rows (row 1 if none)
                let rows = table.selectedRowIndexes.isEmpty ? IndexSet(integer: 1) : table.selectedRowIndexes
                let canDrag = table.canDragRows(with: rows, at: table.rect(ofRow: rows.first!).origin)
                let files = rows.map { row -> String in
                    let writer = (table.dataSource as? DragDataSource)?.tableView(table, pasteboardWriterForRow: row)
                    return (writer as? URL)?.lastPathComponent ?? "none"
                }
                let lines = ["canDrag: \(canDrag)",
                             "rows: \(rows.map(String.init).joined(separator: ", "))",
                             "files: \(files.joined(separator: ", "))",
                             "class: \(NSStringFromClass(object_getClass(table)!))",
                             "isResponder: \(table.isKind(of: NSResponder.self))"]
                try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            }
        }
        // -DebugPrefs <file.png> draws the Preferences view in a window and saves a picture of it
        if let out = UserDefaults.standard.string(forKey: "DebugPrefs") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let host = NSHostingView(rootView: PreferencesView(store: LibraryStore.shared))
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                window.orderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
            }
        }
        // -DebugMainPackage "<title>|<title>…" selects those packages and opens Set Main
        // Package… for them; -DebugMainSearch <text> is then typed in its search field, and
        // -DebugMainReturn YES presses Return
        if let titles = UserDefaults.standard.string(forKey: "DebugMainPackage") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let wanted = Set(titles.components(separatedBy: "|"))
                let store = LibraryStore.shared
                store.selection = Set(store.items.filter { wanted.contains($0.title) }.map(\.id))
                store.chooseMainPackage()
            }
            if UserDefaults.standard.bool(forKey: "DebugMainReturn") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                    guard let sheet = NSApp.windows.first(where: { $0.isVisible })?.attachedSheet else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    sheet.makeKey()
                    for type in [NSEvent.EventType.keyDown, .keyUp] {
                        if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                                    windowNumber: sheet.windowNumber, context: nil, characters: "\r",
                                                    charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
                            NSApp.postEvent(e, atStart: false)
                        }
                    }
                }
            }
        }
        // -DebugOrganize YES runs Library > Organize Library Folder after launch
        if UserDefaults.standard.bool(forKey: "DebugOrganize") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { LibraryStore.shared.organizeAll() }
        }
        guard let path = UserDefaults.standard.string(forKey: "SnapshotPath"), !path.isEmpty else { return }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            // An open sheet goes in <file>-sheet.png
            if let sheet = window.attachedSheet, let sheetView = sheet.contentView?.superview ?? sheet.contentView,
               let sheetRep = sheetView.bitmapImageRepForCachingDisplay(in: sheetView.bounds) {
                sheetView.cacheDisplay(in: sheetView.bounds, to: sheetRep)
                try? sheetRep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: (path as NSString).deletingPathExtension + "-sheet.png"))
            }

            var lines = ["window \(NSStringFromRect(window.frame))"]
            func walk(_ v: NSView) {
                if let s = v as? NSSplitView {
                    lines.append("panes " + s.arrangedSubviews.map { "\(Int($0.frame.width))" }.joined(separator: " "))
                }
                if let t = v as? NSTableView, t.numberOfColumns > 1 {
                    lines.append("columns " + t.tableColumns.map { "\($0.title)=\(Int($0.width))" }.joined(separator: " "))
                }
                if let s = v as? NSScrollView {
                    let frame = s.convert(s.bounds, to: nil)
                    lines.append("scroll x=\(Int(frame.minX)) w=\(Int(frame.width)) h=\(Int(frame.height)) "
                                 + "visibleTop=\(Int(s.documentVisibleRect.minY)) insetTop=\(Int(s.contentInsets.top)) "
                                 + "docHeight=\(Int(s.documentView?.frame.height ?? 0))")
                }
                v.subviews.forEach(walk)
            }
            walk(view)
            try? lines.joined(separator: "\n").write(toFile: path + ".txt", atomically: true, encoding: .utf8)
        }
    }
}
#endif
