import AppKit
import InkPadCore

final class PadController {
    static let size = NSSize(width: 520, height: 188)
    static let stripH: CGFloat = 40  // header; the ink area below keeps its 148 pt height
    static let inkH: CGFloat = size.height - stripH
    static let windowW: CGFloat = inkH * 1.55  // trackpad aspect, so letters keep their shape

    private let settings = Settings.shared
    private let panel: PadPanel
    private let ink = InkView()
    private let label = NSTextField(labelWithString: "")
    private let candStack = NSStackView()
    private let ring = WaitRing(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
    private let langPill = NSTextField(labelWithString: "")
    private let pillBg = NSView()
    private let detector = GestureDetector()
    private var conveyor = Conveyor(padWidth: size.width, windowWidth: windowW)

    private var strokes: [Stroke] = []
    private var current: Stroke?
    private var fx = OneEuro(), fy = OneEuro()
    private var glide: CGFloat = 0
    private var lastNorm: CGPoint?
    private var fingers = 0
    private var suppressUntilLift = false
    private var frozen = false
    private var lastTouchEnd = Date.distantPast
    private var shiftTimer: Timer?, commitTimer: Timer?, previewTimer: Timer?
    private var gen = 0
    private var candidates: [String] = []
    private var candidatesFor = -1  // strokes.count the candidates belong to
    private var selected = 0
    private var chain: Task<Void, Never>?
    private var lastInserted: String?
    private var keyIDs: [UInt32] = []
    private(set) var lastStrokes: [Stroke] = []

    private(set) var isOpen = false
    private var touchActive: Bool { fingers > 0 || Date().timeIntervalSince(lastTouchEnd) < 0.3 }
    private var manualCommit: Bool { settings.pickMode }

    init() {
        panel = PadPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        // White card, warm hairline border; light appearance so system label colours stay dark.
        let fxv = NSView(frame: NSRect(origin: .zero, size: Self.size))
        fxv.appearance = NSAppearance(named: .aqua)
        fxv.wantsLayer = true
        fxv.layer?.backgroundColor = Palette.card.cgColor
        fxv.layer?.cornerRadius = 16; fxv.layer?.masksToBounds = true
        fxv.layer?.borderWidth = 1; fxv.layer?.borderColor = Palette.rule.cgColor
        panel.contentView = fxv

        ink.frame = NSRect(x: 0, y: 0, width: Self.size.width, height: Self.inkH)
        ink.controller = self
        fxv.addSubview(ink)

        // Header: mark · InkPad · status/candidates · wait ring · language pill
        let cy = Self.inkH + Self.stripH / 2
        let logo = LogoView(frame: NSRect(x: 14, y: cy - 9, width: 18, height: 18))
        fxv.addSubview(logo)
        let title = NSTextField(labelWithString: "InkPad")
        title.font = .systemFont(ofSize: 14, weight: .semibold); title.textColor = Palette.ink
        title.sizeToFit(); title.setFrameOrigin(NSPoint(x: 40, y: cy - title.frame.height / 2))
        fxv.addSubview(title)

        langPill.font = .systemFont(ofSize: 12, weight: .medium); langPill.textColor = Palette.mist
        pillBg.wantsLayer = true; pillBg.layer?.backgroundColor = Palette.pill.cgColor; pillBg.layer?.cornerRadius = 11
        fxv.addSubview(pillBg)
        fxv.addSubview(langPill)
        ring.setFrameOrigin(NSPoint(x: 0, y: cy - 9))
        fxv.addSubview(ring)
        layoutHeader()

        let statusX = title.frame.maxX + 12
        label.frame = NSRect(x: statusX, y: cy - 8, width: ring.frame.minX - 10 - statusX, height: 16)
        label.font = .systemFont(ofSize: 12); label.textColor = Palette.mist
        label.lineBreakMode = .byTruncatingHead
        fxv.addSubview(label)

        candStack.orientation = .horizontal; candStack.spacing = 6; candStack.alignment = .centerY
        candStack.frame = NSRect(x: statusX - 4, y: cy - 12, width: ring.frame.minX - 6 - statusX, height: 24)
        candStack.isHidden = true
        fxv.addSubview(candStack)
        resetInk(); showHint()
    }

    // MARK: open / close
    func toggle() { isOpen ? close(commit: true) : open() }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        place()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        keyIDs = [HotKeyCenter.shared.register(code: 53, mods: 0) { [weak self] in self?.close(commit: false) },
                  HotKeyCenter.shared.register(code: 36, mods: 0) { [weak self] in self?.insertNow() }]
        layoutHeader()  // language may have changed in the menu since last open
        showHint()
    }

    func close(commit: Bool) {
        guard isOpen else { return }
        dropCurrent()
        if commit { commitNow() } else { discard() }
        isOpen = false
        keyIDs.forEach(HotKeyCenter.shared.unregister); keyIDs = []
        unfreeze()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.1; panel.animator().alphaValue = 0 },
                                             completionHandler: { [weak self] in if self?.isOpen == false { self?.panel.orderOut(nil) } })
        lastInserted = nil
    }

    private func place() {
        var origin: NSPoint
        let screen: NSScreen
        if let caret = Inserter.caretRect() {
            screen = NSScreen.screens.first { $0.frame.contains(caret.origin) } ?? NSScreen.main!
            origin = NSPoint(x: caret.minX, y: caret.minY - Self.size.height - 10)
            if origin.y < screen.visibleFrame.minY { origin.y = caret.maxY + 10 }
        } else {
            screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
            origin = NSPoint(x: screen.visibleFrame.midX - Self.size.width / 2, y: screen.visibleFrame.minY + 60)
        }
        let v = screen.visibleFrame
        origin.x = min(max(origin.x, v.minX + 8), v.maxX - Self.size.width - 8)
        origin.y = min(max(origin.y, v.minY + 8), v.maxY - Self.size.height - 8)
        panel.setFrameOrigin(origin)
    }

    // MARK: trackpad
    func handle(_ f: TouchFrame) {
        if let g = detector.feed(f) { gesture(g); if case .tap(let n) = g, n == settings.gestureFingers { return } }
        guard isOpen else { return }
        let n = f.touches.count
        if n > 0 { freeze() }
        if n >= 2 { suppressUntilLift = true; dropCurrent() }
        if n == 1, !suppressUntilLift, let t = f.touches.first {
            let nx = CGFloat(t.x), ny = CGFloat(t.y)
            if let l = lastNorm {
                glide += hypot(nx - l.x, ny - l.y)
                if glide > 0.035 { glide = 0; Haptics.shared.play(0) }
            }
            lastNorm = CGPoint(x: nx, y: ny)
            if current == nil { fx.reset(); fy.reset() }
            let x = fx.filter(Double(conveyor.origin + nx * Self.windowW), t: f.time)
            let y = fy.filter(Double((1 - ny) * Self.inkH), t: f.time)
            let p = CGPoint(x: x, y: y)
            if current == nil { beginStroke(p) } else { extendStroke(p) }
        }
        if n == 0 {
            suppressUntilLift = false; lastNorm = nil
            endStroke()
            lastTouchEnd = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                if self?.fingers == 0 { self?.unfreeze() }
            }
        }
        fingers = n
    }

    private func gesture(_ g: Gesture) {
        switch g {
        case .tap(let n) where n == settings.gestureFingers: toggle()
        case .tap(2) where isOpen: insertNow()
        case .tap(3) where isOpen && !candidates.isEmpty: select((selected + 1) % candidates.count)
        case .swipe(2, let dx) where isOpen && dx < 0:
            if !strokes.isEmpty { undo() } else { backspace(max(1, Int(-dx / 0.15))) }
        case .swipe(2, let dx) where isOpen && dx > 0:
            if !strokes.isEmpty { insertNow(thenSpace: true) } else { typeSpace() }
        default: break
        }
    }

    // Pointer events from the trackpad are dropped while fingers write (see CursorGate).
    private func freeze() {
        guard !frozen else { return }
        frozen = true
        CursorGate.set(true)
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    func unfreeze() {
        guard frozen else { return }
        frozen = false
        CursorGate.set(false)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: pen / mouse
    private var penT0 = Date()
    private var penTime: Double { Date().timeIntervalSince(penT0) }
    func penDown(_ p: CGPoint) { guard isOpen, !touchActive else { return }; beginStroke(p, t: penTime) }
    func penMove(_ p: CGPoint) { guard isOpen, !touchActive else { return }; extendStroke(p, t: penTime) }
    func penUp() { guard isOpen, !touchActive else { return }; endStroke() }

    // MARK: strokes
    private func beginStroke(_ p: CGPoint, t: Double? = nil) {
        shiftTimer?.invalidate(); commitTimer?.invalidate(); ring.idle(); previewTimer?.invalidate()
        current = Stroke(points: [p], times: [t ?? CACurrentMediaTime()])
        ink.current = current; ink.needsDisplay = true
    }

    private func extendStroke(_ p: CGPoint, t: Double? = nil) {
        guard var c = current, let l = c.points.last, hypot(p.x - l.x, p.y - l.y) >= 0.6 else { return }
        c.points.append(p); c.times.append(t ?? CACurrentMediaTime())
        current = c; ink.current = c; ink.needsDisplay = true
    }

    private func dropCurrent() { current = nil; ink.current = nil; ink.needsDisplay = true }

    private func endStroke() {
        guard let c = current else { return }
        strokes.append(c); current = nil
        ink.current = nil; ink.strokes = strokes; ink.needsDisplay = true
        scheduleTimers()
    }

    private func scheduleTimers() {
        let w = settings.wait
        shiftTimer = .scheduledTimer(withTimeInterval: 0.6 * w, repeats: false) { [weak self] _ in self?.shift() }
        if !manualCommit {
            commitTimer = .scheduledTimer(withTimeInterval: w, repeats: false) { [weak self] _ in self?.commitNow() }
            ring.run(w)
        }
        previewTimer = .scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in self?.preview() }
    }

    private func shift() {
        let maxX = strokes.flatMap(\.points).map(\.x).max() ?? 0
        conveyor.advance(inkMaxX: maxX)
        ink.windowRect = CGRect(x: conveyor.origin, y: 4, width: Self.windowW, height: Self.inkH - 8)
        ink.targetScroll = conveyor.scroll
        ink.needsDisplay = true
    }

    func undo() {
        guard !strokes.isEmpty else { return }
        shiftTimer?.invalidate(); commitTimer?.invalidate(); ring.idle()
        strokes.removeLast(); ink.strokes = strokes; ink.needsDisplay = true
        Haptics.shared.play(1)
        if strokes.isEmpty { resetInk(); showCandidates([]) } else { scheduleTimers() }
    }

    func insertNow(thenSpace: Bool = false) {
        shiftTimer?.invalidate(); commitTimer?.invalidate(); ring.idle()
        commitNow()
        if thenSpace { typeSpace() }
    }

    private func discard() {
        shiftTimer?.invalidate(); commitTimer?.invalidate(); ring.idle(); previewTimer?.invalidate()
        gen += 1; resetInk(); showCandidates([]); showHint()
    }

    private func resetInk() {
        strokes = []; ink.strokes = []; conveyor.reset()
        ink.windowRect = CGRect(x: conveyor.origin, y: 4, width: Self.windowW, height: Self.inkH - 8)
        ink.snapScroll(0)
    }

    // MARK: recognition
    private var area: CGSize { CGSize(width: max(Self.size.width, (strokes.flatMap(\.points).map(\.x).max() ?? 0) + 20), height: Self.inkH) }

    private func preview() {
        gen += 1; let g = gen, snap = strokes, lang = settings.language, online = settings.online, a = area
        Task { @MainActor in
            let c = await Recognizer.candidates(snap, area: a, language: lang, online: online)
            guard g == self.gen, self.strokes.count == snap.count else { return }
            self.candidatesFor = snap.count
            self.showCandidates(c.isEmpty ? [] : Array(c.prefix(3)))
            if c.isEmpty { self.label.stringValue = "…" }
        }
    }

    private func commitNow(text: String? = nil) {
        shiftTimer?.invalidate(); commitTimer?.invalidate(); ring.idle(); previewTimer?.invalidate()
        guard !strokes.isEmpty else { return }
        let snap = strokes, lang = settings.language, online = settings.online, a = area
        let ready = text ?? (candidatesFor == strokes.count && !candidates.isEmpty ? candidates[selected] : nil)
        lastStrokes = snap
        resetInk(); gen += 1; showCandidates([])
        enqueue { [weak self] in
            guard let self else { return }
            var t = ready
            if t == nil { t = await Recognizer.candidates(snap, area: a, language: lang, online: online).first }
            guard let t, !t.isEmpty else { self.label.stringValue = "Couldn't read that — try again"; return }
            Inserter.insert(Spacing.join(previous: self.lastInserted, next: t))
            self.lastInserted = t
            Haptics.shared.play(1)
            self.label.stringValue = "✓ " + t
        }
    }

    /// Insertions, backspaces and spaces run strictly in order.
    private func enqueue(_ work: @escaping () async -> Void) {
        let prev = chain
        chain = Task { @MainActor in await prev?.value; await work() }
    }

    private func backspace(_ n: Int) {
        enqueue { [weak self] in
            for _ in 0..<min(n, 30) { Inserter.key(51) }
            self?.lastInserted = nil
            Haptics.shared.play(1)
            self?.label.stringValue = "⌫ ×\(n)"
        }
    }

    private func typeSpace() {
        enqueue { [weak self] in Inserter.key(49); self?.lastInserted = " " }
    }

    // MARK: candidate strip
    private func showCandidates(_ c: [String]) {
        candidates = c; selected = 0
        candStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, s) in c.enumerated() {
            let b = NSButton(title: s, target: self, action: #selector(pick(_:)))
            b.tag = i; b.isBordered = false; b.font = .systemFont(ofSize: 13, weight: .medium)
            b.wantsLayer = true; b.layer?.cornerRadius = 6
            candStack.addArrangedSubview(b)
        }
        if manualCommit && !c.isEmpty {
            let hint = NSTextField(labelWithString: "2-finger tap inserts · 3-finger tap next")
            hint.font = .systemFont(ofSize: 11); hint.textColor = Palette.mist
            candStack.addArrangedSubview(hint)
        }
        candStack.isHidden = c.isEmpty
        label.isHidden = !c.isEmpty
        select(0)
    }

    private func select(_ i: Int) {
        selected = i
        for case let b as NSButton in candStack.arrangedSubviews {
            b.layer?.backgroundColor = b.tag == i ? Palette.pill.cgColor : nil
            b.contentTintColor = b.tag == i ? Palette.ink : Palette.mist
        }
    }

    @objc private func pick(_ b: NSButton) {
        guard b.tag < candidates.count else { return }
        let t = candidates[b.tag]
        commitNow(text: t)
    }

    /// Right-aligns the language pill and the ring to its left.
    private func layoutHeader() {
        let cy = Self.inkH + Self.stripH / 2
        langPill.stringValue = settings.language == .auto ? "Auto" : settings.language.title
        langPill.sizeToFit()
        let t = langPill.frame.size, w = t.width + 20
        pillBg.frame = NSRect(x: Self.size.width - 14 - w, y: cy - 11, width: w, height: 22)
        langPill.setFrameOrigin(NSPoint(x: pillBg.frame.minX + 10, y: cy - t.height / 2))
        ring.setFrameOrigin(NSPoint(x: pillBg.frame.minX - 10 - ring.frame.width, y: cy - ring.frame.height / 2))
    }

    private func showHint() {
        label.isHidden = false
        label.stringValue = "2-finger swipe: ← delete, → space"
    }
}

extension PadController {
    /// Debug: what the offline (Vision) path sees for the last inserted ink.
    func showLastInk() {
        guard let img = Rasterizer.render(Rasterizer.normalize(lastStrokes, deslant: settings.language != .japanese)) else { NSSound.beep(); return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("inkpad-last.png")
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        NSWorkspace.shared.open(url)
    }
}
