import AppKit
import ApplicationServices

enum Inserter {
    private static var axFailed = Set<String>()  // bundle ids where AX insert silently does nothing

    static func insert(_ text: String) {
        let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if !axFailed.contains(bid) {
            if axInsert(text) { return }
            axFailed.insert(bid)
        }
        paste(text)
    }

    private static func focused() -> AXUIElement? {
        var f: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &f) == .success,
              let f else { return nil }
        return (f as! AXUIElement)
    }

    private static func value(_ e: AXUIElement) -> String? {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(e, kAXValueAttribute as CFString, &v)
        return v as? String
    }

    private static func axInsert(_ text: String) -> Bool {
        guard let el = focused(), let before = value(el) else { return false }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(el, kAXSelectedTextAttribute as CFString, &settable)
        guard settable.boolValue,
              AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFString) == .success
        else { return false }
        usleep(40_000)  // some apps apply the change async; avoid pasting a duplicate
        return value(el) != before
    }

    private static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [:]) { d, t in if let data = item.data(forType: t) { d[t] = data } }
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        // key code 9 = physical V, independent of keyboard layout
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pb.clearContents()
            let items = saved.map { d -> NSPasteboardItem in
                let item = NSPasteboardItem(); d.forEach { item.setData($1, forType: $0) }; return item
            }
            if !items.isEmpty { pb.writeObjects(items) }
        }
    }

    /// Press one key (51 = delete, 49 = space) in the frontmost app.
    static func key(_ code: CGKeyCode) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            e?.flags = []
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Caret rectangle in Cocoa screen coordinates, if the focused app exposes it.
    static func caretRect() -> NSRect? {
        guard let el = focused() else { return nil }
        var r: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &r) == .success, let r else { return nil }
        var b: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, r, &b) == .success,
              let b, CFGetTypeID(b) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(b as! AXValue, .cgRect, &rect), rect.origin.x.isFinite, rect != .zero else { return nil }
        let h = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: h - rect.maxY, width: rect.width, height: rect.height)
    }
}
