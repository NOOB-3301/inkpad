import AppKit
import InkPadCore
import ApplicationServices

final class MenuAction: NSMenuItem {
    private let block: () -> Void
    init(_ title: String, checked: Bool = false, _ block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self; state = checked ? .on : .off
    }
    required init(coder: NSCoder) { fatalError() }
    @objc func run() { block() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pad = PadController()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let recorder = HotkeyRecorder()
    private var hotKeyID: UInt32?
    private let s = Settings.shared

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.image = LogoView.menuBarImage; item.button?.setAccessibilityLabel("InkPad")
        registerHotKey(); rebuildMenu()
        TouchSource.shared.onFrame = { [pad] in pad.handle($0) }
        TouchSource.shared.start()
        dlog("launch trusted=\(AXIsProcessTrusted())")
        if AXIsProcessTrusted() { CursorGate.install() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { TouchSource.shared.restart() }
        }
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }

    func applicationWillTerminate(_ n: Notification) { pad.unfreeze() }

    private func registerHotKey() {
        if let id = hotKeyID { HotKeyCenter.shared.unregister(id) }
        let hk = s.hotKey
        hotKeyID = HotKeyCenter.shared.register(code: hk.code, mods: hk.mods) { [pad] in pad.toggle() }
    }

    private func rebuildMenu() {
        let m = NSMenu()
        m.addItem(MenuAction("Open / Close Pad   \(s.hotKey.name)") { [pad] in pad.toggle() })
        m.addItem(.separator())
        let g = NSMenu()
        for n in [4, 5] { g.addItem(MenuAction("\(n)-finger tap", checked: s.gestureFingers == n) { [self] in s.gestureFingers = n; rebuildMenu() }) }
        let gi = NSMenuItem(title: "Open/close gesture", action: nil, keyEquivalent: ""); gi.submenu = g; m.addItem(gi)
        let l = NSMenu()
        for lang in RecognitionLanguage.allCases { l.addItem(MenuAction(lang.title, checked: s.language == lang) { [self] in s.language = lang; rebuildMenu() }) }
        let li = NSMenuItem(title: "Language", action: nil, keyEquivalent: ""); li.submenu = l; m.addItem(li)
        let w = NSMenu()
        for v in [0.6, 1.0, 1.5, 2.0, 3.0] { w.addItem(MenuAction("\(v) s", checked: s.wait == v) { [self] in s.wait = v; rebuildMenu() }) }
        let wi = NSMenuItem(title: "Wait before inserting", action: nil, keyEquivalent: ""); wi.submenu = w; m.addItem(wi)
        m.addItem(MenuAction("Online recognition (Google)", checked: s.online) { [self] in s.online.toggle(); rebuildMenu() })
        let mo = NSMenu()
        mo.addItem(MenuAction("Auto-insert after pause", checked: !s.pickMode) { [self] in s.pickMode = false; rebuildMenu() })
        mo.addItem(MenuAction("Pick from candidates", checked: s.pickMode) { [self] in s.pickMode = true; rebuildMenu() })
        let moi = NSMenuItem(title: "Insert mode", action: nil, keyEquivalent: ""); moi.submenu = mo; m.addItem(moi)
        let h = NSMenu()
        for (i, t) in ["Off", "Light", "Strong"].enumerated() { h.addItem(MenuAction(t, checked: s.haptics == i) { [self] in s.haptics = i; rebuildMenu() }) }
        let hi = NSMenuItem(title: "Haptic feedback", action: nil, keyEquivalent: ""); hi.submenu = h; m.addItem(hi)
        m.addItem(MenuAction("Set Hotkey…") { [self] in
            recorder.run { [self] hk in s.hotKey = hk; registerHotKey(); rebuildMenu() }
        })
        m.addItem(.separator())
        m.addItem(.separator())
        if !AXIsProcessTrusted() {
            m.addItem(.separator())
            m.addItem(MenuAction("⚠︎ Grant Accessibility access…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            })
        }
        m.addItem(.separator())
        m.addItem(MenuAction("Quit InkPad") { NSApp.terminate(nil) })
        item.menu = m
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
