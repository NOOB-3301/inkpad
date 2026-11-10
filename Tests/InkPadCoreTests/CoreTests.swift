import Testing
import CoreGraphics
import CoreText
import Foundation
@testable import InkPadCore

@Suite struct GestureTests {
    private func frames(_ fingers: Int, land: Double = 0.03, hold: Double = 0.1, move: Float = 0, t0: Double = 0) -> [TouchFrame] {
        func ts(_ n: Int, _ dx: Float) -> [TouchPoint] { (0..<n).map { TouchPoint(id: $0, x: 0.3 + Float($0) * 0.1 + dx, y: 0.5) } }
        var out: [TouchFrame] = []
        for n in 1...fingers { out.append(TouchFrame(time: t0 + land * Double(n) / Double(fingers), touches: ts(n, 0))) }
        out.append(TouchFrame(time: t0 + land + hold / 2, touches: ts(fingers, move)))
        out.append(TouchFrame(time: t0 + land + hold, touches: []))
        return out
    }
    private func run(_ fs: [TouchFrame]) -> Gesture? {
        let d = GestureDetector(); var g: Gesture?
        for f in fs { if let r = d.feed(f) { g = r } }
        return g
    }

    @Test func fourFingerTap() { #expect(run(frames(4)) == .tap(fingers: 4)) }
    @Test func twoFingerTap() { #expect(run(frames(2)) == .tap(fingers: 2)) }
    @Test func swipeIsNotTap() { #expect(run(frames(4, move: 0.3)) == .swipe(fingers: 4, dx: 0.3)) }
    @Test func slowPressIsNotTap() { #expect(run(frames(4, hold: 0.8)) == nil) }
    @Test func slowLandingIsNotTap() { #expect(run(frames(4, land: 0.4)) == nil) }
    @Test func twoFingerSwipeLeft() {
        let g = run(frames(2, hold: 0.3, move: -0.25))
        guard case .swipe(2, let dx)? = g else { Issue.record("got \(String(describing: g))"); return }
        #expect(dx < -0.2)
    }
    @Test func resetsBetweenGestures() {
        let d = GestureDetector(); var gs: [Gesture] = []
        for f in frames(4) + frames(2, t0: 5) { if let g = d.feed(f) { gs.append(g) } }
        #expect(gs == [.tap(fingers: 4), .tap(fingers: 2)])
    }
}

@Suite struct LogicTests {
    @Test func spacing() {
        #expect(Spacing.join(previous: nil, next: "hello") == "hello")
        #expect(Spacing.join(previous: "hello", next: "world") == " world")
        #expect(Spacing.join(previous: "hello", next: ".") == ".")
        #expect(Spacing.join(previous: "こんにちは", next: "世界") == "世界")
        #expect(Spacing.join(previous: "hello", next: "世界") == "世界")
        #expect(Spacing.join(previous: "世界", next: "hello") == "hello")
        #expect(Spacing.join(previous: " ", next: "hello") == "hello")
    }

    @Test func conveyorScrollsOnlyWhenNeeded() {
        var c = Conveyor(padWidth: 520, windowWidth: 240)
        #expect(c.scroll == 0)
        c.advance(inkMaxX: 100)
        #expect(c.origin == 114)
        c.advance(inkMaxX: 400)
        #expect(c.origin == 414)
        #expect(abs(c.scroll - 146) < 0.001)
        c.reset(); #expect(c.scroll == 0)
    }

    @Test func normalizeRemovesSlantAndTilt() {
        // a right-leaning vertical bar: top at x=20, bottom at x=0
        let slanted = Stroke(points: (0...10).map { CGPoint(x: 20 - CGFloat($0) * 2, y: CGFloat($0) * 10) })
        let n = Rasterizer.normalize([slanted])[0].points
        #expect(abs(n.first!.x - n.last!.x) < 1)
        // a line tilted 15 degrees gets rotated flat
        let tilt = Stroke(points: (0...20).map { CGPoint(x: CGFloat($0) * 10, y: CGFloat($0) * 10 * tan(.pi / 12)) })
        let r = Rasterizer.normalize([tilt], deslant: false)[0].points
        #expect(abs(r.first!.y - r.last!.y) < 1)
    }

    @Test func oneEuroSmoothsJitter() {
        var f = OneEuro(); var outs: [Double] = []
        for i in 0..<50 { outs.append(f.filter(100 + (i % 2 == 0 ? 2 : -2), t: Double(i) / 100)) }
        #expect(outs.suffix(10).allSatisfy { abs($0 - 100) < 1.5 })
    }

    @Test func rasterizerProducesImage() {
        let img = Rasterizer.render([Stroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 60)])])
        #expect(img != nil)
        #expect((img?.width ?? 0) > 300)
        #expect(Rasterizer.render([]) == nil)
    }
}

/// Recognition check on text rendered in handwriting-style fonts through the app's recognizer.
/// Real handwriting fixtures (recorded strokes) come later; this guards the pipeline and language handling.
@Suite struct AccuracyTests {
    private func render(_ text: String, font name: String) -> CGImage {
        let font = CTFontCreateWithName(name as CFString, 64, nil)
        let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                                 NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
        let line = CTLineCreateWithAttributedString(attr)
        let b = CTLineGetBoundsWithOptions(line, [])
        let ctx = CGContext(data: nil, width: Int(b.width) + 80, height: Int(b.height) + 80, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        ctx.textPosition = CGPoint(x: 40 - b.minX, y: 40 - b.minY)
        CTLineDraw(line, ctx)
        return ctx.makeImage()!
    }

    private func cer(_ a: String, _ b: String) -> Double {
        let x = Array(a.lowercased().filter { !$0.isWhitespace }), y = Array(b.lowercased().filter { !$0.isWhitespace })
        if x.isEmpty { return y.isEmpty ? 0 : 1 }
        var d = Array(0...y.count)
        for i in 1...x.count {
            var prev = d[0]; d[0] = i
            if y.isEmpty { continue }
            for j in 1...y.count {
                let t = d[j]; d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (x[i - 1] == y[j - 1] ? 0 : 1)); prev = t
            }
        }
        return Double(d[y.count]) / Double(x.count)
    }

    @Test func english() async {
        let samples = ["hello world", "the quick brown fox", "meeting at noon tomorrow", "please send the invoice"]
        for font in ["Noteworthy-Light", "BradleyHandITCTT-Bold"] {
            var total = 0.0
            for s in samples { total += cer(s, await Recognizer.recognize(render(s, font: font), language: .english).first ?? "") }
            #expect(total / Double(samples.count) < 0.15, "English CER too high for \(font)")
        }
    }

    @Test func japanese() async {
        let samples = ["こんにちは", "ありがとうございます", "今日は天気がいい", "日本語を勉強しています"]
        var total = 0.0
        for s in samples { total += cer(s, await Recognizer.recognize(render(s, font: "HiraginoSans-W3"), language: .japanese).first ?? "") }
        #expect(total / Double(samples.count) < 0.15, "Japanese CER too high")
    }

    @Test func autoPicksCorrectLanguage() async {
        let en = await Recognizer.recognize(render("good morning", font: "Noteworthy-Light"), language: .auto).first ?? ""
        let ja = await Recognizer.recognize(render("おはようございます", font: "HiraginoSans-W3"), language: .auto).first ?? ""
        #expect(cer("good morning", en) < 0.2, "got: \(en)")
        #expect(cer("おはようございます", ja) < 0.2, "got: \(ja)")
    }
}

@Suite struct GoogleLiveTests {
    /// Synthetic stroke: a horizontal line should read as 一 in Japanese. Opt-in (network).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPAD_ONLINE"] == "1"))
    func horizontalLineIsIchi() async {
        let s = Stroke(points: (0...20).map { CGPoint(x: 40 + CGFloat($0) * 10, y: 150) }, times: (0...20).map { Double($0) * 0.01 })
        let c = await Recognizer.google([s], area: CGSize(width: 300, height: 300), language: .japanese)
        #expect(c?.first == "一")
    }
}
