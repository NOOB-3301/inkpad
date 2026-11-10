import AppKit
import InkPadCore

final class InkView: NSView {
    weak var controller: PadController?
    var strokes: [Stroke] = [] { didSet { cached = CGMutablePath(); strokes.forEach { cached.addPath($0.path) } } }
    var current: Stroke?
    var windowRect: CGRect?
    var scroll: CGFloat = 0
    var targetScroll: CGFloat = 0 { didSet { animate() } }
    private var cached = CGMutablePath()
    private var timer: Timer?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawSheet(ctx)
        ctx.translateBy(x: -scroll, y: 0)
        if let w = windowRect {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.6).cgColor)
            ctx.addPath(CGPath(roundedRect: w, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.fillPath()
        }
        ctx.setStrokeColor(Palette.ink.cgColor)
        ctx.setLineWidth(3); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addPath(cached); ctx.strokePath()
        if let c = current { ctx.addPath(c.path); ctx.strokePath() }
    }

    /// Writing sheet: an off-white inset with genkō yōshi squares (rows of cells, a thin gap row between them).
    private func drawSheet(_ ctx: CGContext) {
        let sheet = bounds.insetBy(dx: 12, dy: 0).divided(atDistance: bounds.height - 12, from: .minYEdge).slice
        let clip = CGPath(roundedRect: sheet, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.saveGState()
        ctx.addPath(clip); ctx.clip()
        ctx.setFillColor(Palette.sheet.cgColor); ctx.fill(sheet)
        ctx.setStrokeColor(Palette.rule.cgColor); ctx.setLineWidth(1)
        let cell: CGFloat = 46, gap: CGFloat = 12
        var y = sheet.minY
        while y < sheet.maxY {
            ctx.move(to: CGPoint(x: sheet.minX, y: y + cell + 0.5)); ctx.addLine(to: CGPoint(x: sheet.maxX, y: y + cell + 0.5))
            ctx.move(to: CGPoint(x: sheet.minX, y: y + cell + gap + 0.5)); ctx.addLine(to: CGPoint(x: sheet.maxX, y: y + cell + gap + 0.5))
            var x = sheet.minX + cell
            while x < sheet.maxX { ctx.move(to: CGPoint(x: x + 0.5, y: y)); ctx.addLine(to: CGPoint(x: x + 0.5, y: y + cell)); x += cell }
            y += cell + gap
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    func snapScroll(_ s: CGFloat) { timer?.invalidate(); timer = nil; scroll = s; targetScroll = s; needsDisplay = true }

    private func animate() {
        guard timer == nil, abs(targetScroll - scroll) > 0.5 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.scroll += (self.targetScroll - self.scroll) * 0.25
            if abs(self.targetScroll - self.scroll) < 0.5 { self.scroll = self.targetScroll; t.invalidate(); self.timer = nil }
            self.needsDisplay = true
        }
    }

    // Mouse + tablet pen (tablet drivers deliver absolute mouse events).
    private func world(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        return CGPoint(x: p.x + scroll, y: p.y)
    }
    override func mouseDown(with e: NSEvent) { controller?.penDown(world(e)) }
    override func mouseDragged(with e: NSEvent) { controller?.penMove(world(e)) }
    override func mouseUp(with e: NSEvent) { controller?.penUp() }
}

/// Paper, sumi ink and one vermilion accent; matches the website.
enum Palette {
    static let card = NSColor.white
    static let sheet = NSColor(srgbRed: 0.969, green: 0.965, blue: 0.949, alpha: 1)   // #F7F6F2
    static let rule = NSColor(srgbRed: 0.890, green: 0.878, blue: 0.847, alpha: 1)    // #E3E0D8
    static let pill = NSColor(srgbRed: 0.937, green: 0.929, blue: 0.906, alpha: 1)    // #EFEDE7
    static let ink = NSColor(srgbRed: 0.090, green: 0.090, blue: 0.102, alpha: 1)     // #17171A
    static let mist = NSColor(srgbRed: 0.361, green: 0.357, blue: 0.341, alpha: 1)    // #5C5B57
    static let red = NSColor(srgbRed: 0.843, green: 0.188, blue: 0.122, alpha: 1)     // #D7301F
}

/// The InkPad mark: one red stroke inside a rounded square (same path as the site's Seal.svg).
final class LogoView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Self.draw(ctx, size: bounds.size, frame: Palette.ink)
    }

    /// Menu bar icon. Frame follows the menu bar's text colour (light or dark menu bar); the stroke stays red.
    static let menuBarImage = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { r in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        draw(ctx, size: r.size, frame: .labelColor)
        return true
    }

    /// Drawn in the site's 28×28 SVG units (flipped, y down).
    static func draw(_ ctx: CGContext, size: CGSize, frame: NSColor) {
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.scaleBy(x: size.width / 28, y: size.height / 28)
        ctx.setStrokeColor(frame.cgColor); ctx.setLineWidth(1.6)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 1, y: 1, width: 26, height: 26), cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.strokePath()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 7.5, y: 18.5))
        p.addCurve(to: CGPoint(x: 12.5, y: 10.9), control1: CGPoint(x: 9.7, y: 17.1), control2: CGPoint(x: 12.1, y: 13.4))
        p.addCurve(to: CGPoint(x: 10.6, y: 10.1), control1: CGPoint(x: 12.8, y: 9.0), control2: CGPoint(x: 11.3, y: 8.5))
        p.addCurve(to: CGPoint(x: 12.0, y: 18.7), control1: CGPoint(x: 9.4, y: 13.0), control2: CGPoint(x: 10.0, y: 17.4))
        p.addCurve(to: CGPoint(x: 18.4, y: 15.5), control1: CGPoint(x: 13.8, y: 19.9), control2: CGPoint(x: 16.5, y: 18.1))
        p.addCurve(to: CGPoint(x: 20.6, y: 12.4), control1: CGPoint(x: 19.4, y: 14.1), control2: CGPoint(x: 20.0, y: 13.1))
        ctx.setStrokeColor(Palette.red.cgColor); ctx.setLineWidth(1.9); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addPath(p); ctx.strokePath()
    }
}

/// Red ring in the header. Idle: a full ring. While a pause is counting down to insert, it refills clockwise from the top.
final class WaitRing: NSView {
    private let track = CAShapeLayer(), arc = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let c = CGPoint(x: bounds.midX, y: bounds.midY), r = bounds.width / 2 - 1.5
        let path = CGMutablePath()
        path.addArc(center: c, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for l in [track, arc] {
            l.path = path; l.fillColor = nil; l.strokeColor = Palette.red.cgColor; l.lineWidth = 2; l.lineCap = .round
            layer?.addSublayer(l)
        }
        arc.strokeEnd = 0
    }
    required init?(coder: NSCoder) { fatalError() }

    func run(_ seconds: TimeInterval) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.opacity = 0.22; arc.removeAllAnimations(); arc.strokeEnd = 1
        CATransaction.commit()
        let a = CABasicAnimation(keyPath: "strokeEnd")
        a.fromValue = 0; a.toValue = 1; a.duration = seconds
        arc.add(a, forKey: "wait")
    }

    func idle() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        arc.removeAllAnimations(); arc.strokeEnd = 0; track.opacity = 1
        CATransaction.commit()
    }
}

final class PadPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
