import Foundation
import CoreGraphics

public struct Stroke: Codable {
    public var points: [CGPoint]
    public var times: [Double]  // seconds, same length as points
    public init(points: [CGPoint] = [], times: [Double] = []) { self.points = points; self.times = times }

    /// Smooth path through midpoints (quadratic curves). A single point becomes a dot.
    public var path: CGPath {
        let p = CGMutablePath()
        guard let f = points.first else { return p }
        if points.count == 1 { p.addEllipse(in: CGRect(x: f.x - 1, y: f.y - 1, width: 2, height: 2)); return p }
        p.move(to: f)
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            if i == 1 { p.addLine(to: mid) } else { p.addQuadCurve(to: mid, control: a) }
        }
        p.addLine(to: points.last!)
        return p
    }
}

/// Where the trackpad "window" sits on the (scrolling) pad. Writing always happens at the same
/// physical place; after a pause the window jumps to just past the ink and the pad scrolls to keep it visible.
public struct Conveyor {
    public var padWidth: CGFloat
    public var windowWidth: CGFloat
    public var gap: CGFloat
    public private(set) var origin: CGFloat
    private let margin: CGFloat = 12

    public init(padWidth: CGFloat, windowWidth: CGFloat, gap: CGFloat = 14) {
        self.padWidth = padWidth; self.windowWidth = windowWidth; self.gap = gap; self.origin = margin
    }

    public var scroll: CGFloat { max(0, origin + windowWidth + margin - padWidth) }

    public mutating func advance(inkMaxX: CGFloat) { origin = max(origin, inkMaxX + gap) }
    public mutating func reset() { origin = margin }
}

/// One-Euro filter: removes trackpad jitter when slow, stays responsive when fast.
public struct OneEuro {
    public var minCutoff = 2.0, beta = 0.05, dCutoff = 1.0
    private var x: Double?, t: Double?, dx = 0.0
    public init() {}
    public mutating func filter(_ v: Double, t now: Double) -> Double {
        guard let px = x, let pt = t, now > pt else { x = v; t = now; return v }
        let dt = now - pt
        func alpha(_ c: Double) -> Double { let r = 2 * Double.pi * c * dt; return r / (r + 1) }
        dx += alpha(dCutoff) * ((v - px) / dt - dx)
        let nx = px + alpha(minCutoff + beta * abs(dx)) * (v - px)
        x = nx; t = now
        return nx
    }
    public mutating func reset() { x = nil; t = nil; dx = 0 }
}
