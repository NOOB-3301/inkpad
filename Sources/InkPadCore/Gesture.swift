import Foundation

public struct TouchPoint {
    public var id: Int
    public var x: Float  // normalized 0...1, origin bottom-left
    public var y: Float
    public init(id: Int, x: Float, y: Float) { self.id = id; self.x = x; self.y = y }
}

public struct TouchFrame {
    public var time: Double
    public var touches: [TouchPoint]
    public init(time: Double, touches: [TouchPoint]) { self.time = time; self.touches = touches }
}

public enum Gesture: Equatable { case tap(fingers: Int); case swipe(fingers: Int, dx: Float) }

/// Detects multi-finger taps from raw touch frames. A tap = all fingers land within
/// `maxLandSpread`, barely move, and all lift within `maxDuration`.
public final class GestureDetector {
    public var maxDuration = 0.35
    public var maxLandSpread = 0.15
    public var maxMove: Float = 0.05

    private var start: Double?
    private var reachedMaxAt = 0.0
    private var maxCount = 0
    private var first: [Int: (Float, Float)] = [:]
    private var moved: Float = 0
    private var last: [Int: (Float, Float)] = [:]
    public var minSwipe: Float = 0.08

    public init() {}

    public func feed(_ f: TouchFrame) -> Gesture? {
        if f.touches.isEmpty {
            defer { reset() }
            guard let s = start, maxCount > 0 else { return nil }
            let dur = f.time - s, landed = reachedMaxAt - s <= maxLandSpread
            if dur <= maxDuration && landed && moved <= maxMove { return .tap(fingers: maxCount) }
            // swipe: average horizontal travel of all fingers, mostly horizontal
            let ids = first.keys.filter { last[$0] != nil }
            guard maxCount >= 2, !ids.isEmpty, dur <= 1.2 else { return nil }
            let dx = ids.map { last[$0]!.0 - first[$0]!.0 }.reduce(0, +) / Float(ids.count)
            let dy = ids.map { last[$0]!.1 - first[$0]!.1 }.reduce(0, +) / Float(ids.count)
            return abs(dx) >= minSwipe && abs(dx) > 2 * abs(dy) ? .swipe(fingers: maxCount, dx: dx) : nil
        }
        if start == nil { start = f.time }
        for t in f.touches {
            last[t.id] = (t.x, t.y)
            if let p = first[t.id] {
                moved = max(moved, hypot(t.x - p.0, t.y - p.1))
            } else {
                first[t.id] = (t.x, t.y)
            }
        }
        if f.touches.count > maxCount { maxCount = f.touches.count; reachedMaxAt = f.time }
        return nil
    }

    private func reset() { start = nil; maxCount = 0; first = [:]; last = [:]; moved = 0; reachedMaxAt = 0 }
}
