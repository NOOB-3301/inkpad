import CoreGraphics

public enum Rasterizer {
    /// Straighten tilted lines (PCA baseline) and remove letter slant (shear) before image recognition.
    public static func normalize(_ strokes: [Stroke], deslant: Bool = true) -> [Stroke] {
        let pts = strokes.flatMap(\.points)
        guard pts.count > 2 else { return strokes }
        let n = CGFloat(pts.count)
        let cx = pts.map(\.x).reduce(0, +) / n, cy = pts.map(\.y).reduce(0, +) / n
        var sxx: CGFloat = 0, sxy: CGFloat = 0, syy: CGFloat = 0
        for p in pts { let dx = p.x - cx, dy = p.y - cy; sxx += dx * dx; sxy += dx * dy; syy += dy * dy }
        var a = 0.5 * atan2(2 * sxy, sxx - syy)
        if abs(a) > .pi / 6 || sxx < 1.5 * syy { a = 0 }  // only clearly horizontal writing
        let c = cos(-a), s = sin(-a)
        var out = strokes.map { st in
            Stroke(points: st.points.map { p in
                let x = p.x - cx, y = p.y - cy
                return CGPoint(x: cx + x * c - y * s, y: cy + x * s + y * c)
            }, times: st.times)
        }
        guard deslant else { return out }
        var num: CGFloat = 0, den: CGFloat = 0
        for st in out where st.points.count > 1 {
            for i in 1..<st.points.count {
                let dx = st.points[i].x - st.points[i - 1].x, dy = st.points[i].y - st.points[i - 1].y
                if abs(dy) > 2 * abs(dx), abs(dy) > 0.5 { num += dx * (dy > 0 ? 1 : -1); den += abs(dy) }
            }
        }
        guard den > 0 else { return out }
        let k = max(-0.8, min(0.8, num / den))
        out = out.map { st in Stroke(points: st.points.map { CGPoint(x: $0.x - k * ($0.y - cy), y: $0.y) }, times: st.times) }
        return out
    }

    /// Black ink on white, cropped to the ink with a margin. Same image feeds the app and the tests.
    public static func render(_ strokes: [Stroke], scale: CGFloat = 3, margin: CGFloat = 18, lineWidth: CGFloat = 3.5) -> CGImage? {
        let pts = strokes.flatMap(\.points)
        guard let f = pts.first else { return nil }
        var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
        for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        let inkH = max(maxY - minY, 50)
        let lineWidth = max(lineWidth, (maxY - minY) / 16)
        let w = (maxX - minX) + 2 * margin, h = inkH + 2 * margin
        guard let ctx = CGContext(data: nil, width: Int(w * scale), height: Int(h * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w * scale, height: h * scale))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: margin - minX, y: h - margin + minY - (inkH - (maxY - minY)) / 2)
        ctx.scaleBy(x: 1, y: -1)  // world y points down
        ctx.setStrokeColor(gray: 0, alpha: 1)
        ctx.setLineWidth(lineWidth); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for s in strokes { ctx.addPath(s.path); ctx.strokePath() }
        return ctx.makeImage()
    }
}
