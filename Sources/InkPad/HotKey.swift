import Carbon.HIToolbox
import AppKit

final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { HotKeyCenter.shared.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    @discardableResult
    func register(code: UInt32, mods: UInt32, _ handler: @escaping () -> Void) -> UInt32 {
        let id = nextID; nextID += 1
        var ref: EventHotKeyRef?
        RegisterEventHotKey(code, mods, EventHotKeyID(signature: OSType(0x494E4B50), id: id), GetApplicationEventTarget(), 0, &ref)
        if let ref { refs[id] = ref; handlers[id] = handler }
        return id
    }

    func unregister(_ id: UInt32) {
        if let r = refs.removeValue(forKey: id) { UnregisterEventHotKey(r) }
        handlers[id] = nil
    }

    static func carbonMods(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        return m
    }
}

/// Small window that captures the next modifier+key combo.
final class HotkeyRecorder {
    private var window: NSPanel?
    private var monitor: Any?

    func run(done: @escaping ((code: UInt32, mods: UInt32, name: String)) -> Void) {
        let label = NSTextField(labelWithString: "Press the new shortcut (needs ⌃, ⌥ or ⌘)\nEsc to cancel")
        label.alignment = .center
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Set InkPad hotkey"
        label.frame = NSRect(x: 10, y: 20, width: 280, height: 40)
        w.contentView?.addSubview(label)
        w.center(); window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 { self.finish(); return nil }
            let f = e.modifierFlags.intersection([.command, .control, .option, .shift])
            guard !f.intersection([.command, .control, .option]).isEmpty else { NSSound.beep(); return nil }
            var name = ""
            if f.contains(.control) { name += "⌃" }
            if f.contains(.option) { name += "⌥" }
            if f.contains(.shift) { name += "⇧" }
            if f.contains(.command) { name += "⌘" }
            name += e.keyCode == 49 ? "Space" : (e.charactersIgnoringModifiers ?? "?").uppercased()
            done((UInt32(e.keyCode), HotKeyCenter.carbonMods(f), name))
            self.finish()
            return nil
        }
    }

    private func finish() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        window?.orderOut(nil); window = nil; monitor = nil
    }
}
