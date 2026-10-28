import AppKit
import SwiftUI

/// Lets you drag packages out of the list onto other apps: the Finder copies the
/// files, Einstein installs them, and so on.
///
/// SwiftUI's Table has no row dragging on macOS 12, so this finds the AppKit
/// table underneath and gives it a data source that hands out each dragged
/// row's file, passing everything else on to SwiftUI's own data source.
/// Drags back onto Newton Library itself are refused, so nothing is re-added.
struct TableDragSupport: NSViewRepresentable {
    /// The packages, in the order the list shows them (their files are looked
    /// up only when one is dragged: the list can have thousands).
    let items: [LibraryItem]

    func makeCoordinator() -> DragDataSource { DragDataSource() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let source = context.coordinator
        source.items = items
        // Once the view is in the window (and again if SwiftUI replaces its data source)
        DispatchQueue.main.async {
            guard let table = Self.findTable(near: view) else { return }
            if table.dataSource !== source {
                source.original = table.dataSource
                table.dataSource = source
                table.setDraggingSourceOperationMask(.copy, forLocal: false)
                table.setDraggingSourceOperationMask([], forLocal: true)
            }
            Self.allowRowDragging(table)
        }
    }

    /// SwiftUI's table classes already patched (see allowRowDragging).
    private static var patchedClasses: Set<String> = []

    /// SwiftUI's table class answers "no" when AppKit asks whether rows can be
    /// dragged (unless SwiftUI's own drag support, which needs macOS 13, is in
    /// use), so no drag ever starts. This patches that method on SwiftUI's
    /// table class, once, to answer "yes" for a table whose data source is a
    /// DragDataSource (which hands out the files); other tables get the
    /// original answer.
    ///
    /// The class itself is patched rather than the table being given a
    /// subclass of its own: changing an object's class breaks when key-value
    /// observing has already changed it (the table then no longer counts as an
    /// NSResponder, and AppKit stops the app when it next adds a row).
    private static func allowRowDragging(_ table: NSTableView) {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "DebugNoDragFix") { return }   // to test without it
        #endif
        // The table's real class, under any class key-value observing made for it
        guard var cls: AnyClass = object_getClass(table) else { return }
        // (named "NSKVONotifying_…", or for a Swift class "..NSKVONotifying_…")
        while NSStringFromClass(cls).contains("NSKVONotifying_"), let superclass = class_getSuperclass(cls) {
            cls = superclass
        }
        let name = NSStringFromClass(cls)
        guard !patchedClasses.contains(name) else { return }
        let selector = #selector(NSTableView.canDragRows(with:at:))
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        typealias CanDrag = @convention(c) (NSTableView, Selector, NSIndexSet, NSPoint) -> Bool
        let original = unsafeBitCast(method_getImplementation(method), to: CanDrag.self)
        let answer: @convention(block) (NSTableView, NSIndexSet, NSPoint) -> Bool = { table, rows, point in
            table.dataSource is DragDataSource || original(table, selector, rows, point)
        }
        let patched = imp_implementationWithBlock(answer)
        // Its own method if it has one, else one added to it (not to NSTableView)
        if !class_addMethod(cls, selector, patched, method_getTypeEncoding(method)) {
            method_setImplementation(method, patched)
        }
        patchedClasses.insert(name)
    }

    /// The package list's table: the nearest table with several columns (the
    /// sidebar has only one). SwiftUI may build it as an outline view.
    private static func findTable(near view: NSView) -> NSTableView? {
        func search(_ v: NSView) -> NSTableView? {
            if let t = v as? NSTableView, t.numberOfColumns > 1 { return t }
            for sub in v.subviews { if let t = search(sub) { return t } }
            return nil
        }
        var ancestor = view.superview
        for _ in 0..<8 {
            guard let a = ancestor else { break }
            if let t = search(a) { return t }
            ancestor = a.superview
        }
        return nil
    }
}

final class DragDataSource: NSObject, NSTableViewDataSource, NSOutlineViewDataSource {
    weak var original: NSTableViewDataSource?
    var items: [LibraryItem] = []
    #if DEBUG
    static var debugLog: [String] = []
    #endif

    /// Each dragged row's file, if it's there.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row >= 0, row < items.count else { return nil }
        let url = items[row].fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        #if DEBUG
        DragDataSource.debugLog.append("drag row \(row): \(url.lastPathComponent)")
        #endif
        return url as NSURL
    }

    /// SwiftUI builds its Table on an outline view, which asks by item instead.
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        tableView(outlineView, pasteboardWriterForRow: outlineView.row(forItem: item))
    }

    // Everything else goes to SwiftUI's data source
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original
    }
}
