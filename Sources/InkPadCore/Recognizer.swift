import Foundation
import Vision
import CoreGraphics

public enum RecognitionLanguage: String, CaseIterable, Sendable {
    case english, japanese, auto
    public var title: String { self == .auto ? "Auto (English + Japanese)" : rawValue.capitalized }
}

public enum Recognizer {
    /// Best-first candidates. Google stroke recognizer when `online`, Apple Vision otherwise or on failure.
    public static func candidates(_ strokes: [Stroke], area: CGSize, language: RecognitionLanguage, online: Bool) async -> [String] {
        guard !strokes.isEmpty else { return [] }
        if online, let g = await google(strokes, area: area, language: language), !g.isEmpty { return g }
        return await vision(strokes, language: language)
    }

    // MARK: Google (unofficial Input Tools endpoint; same engine as Gboard handwriting)
    public static func google(_ strokes: [Stroke], area: CGSize, language: RecognitionLanguage) async -> [String]? {
        switch language {
        case .english: return await googleRequest(strokes, area: area, lang: "en")
        case .japanese: return await googleRequest(strokes, area: area, lang: "ja")
        case .auto:
            async let en = googleRequest(strokes, area: area, lang: "en")
            async let ja = googleRequest(strokes, area: area, lang: "ja")
            let (e, j) = await (en, ja)
            if let j, let top = j.first, top.contains(where: { Spacing.isCJK($0) }) { return j }
            return e ?? j
        }
    }

    static func googleRequest(_ strokes: [Stroke], area: CGSize, lang: String) async -> [String]? {
        var req = URLRequest(url: URL(string: "https://inputtools.google.com/request?ime=handwriting&app=inkpad&cs=1&oe=UTF-8")!,
                             timeoutInterval: 1.2)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let t0 = strokes.first?.times.first ?? 0
        let ink: [[[Int]]] = strokes.map { s in
            [s.points.map { Int($0.x.rounded()) }, s.points.map { Int($0.y.rounded()) },
             s.times.map { Int((($0 - t0) * 1000).rounded()) }]
        }
        let body: [String: Any] = ["requests": [["writing_guide": ["writing_area_width": Int(area.width), "writing_area_height": Int(area.height)],
                                                 "ink": ink, "language": lang, "max_num_results": 5, "max_completions": 0]]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.first as? String == "SUCCESS",
              let results = json.dropFirst().first as? [Any],
              let first = results.first as? [Any], first.count > 1,
              let cands = first[1] as? [String] else { return nil }
        return cands
    }

    // MARK: Vision (offline)
    public static func vision(_ strokes: [Stroke], language: RecognitionLanguage) async -> [String] {
        let norm = Rasterizer.normalize(strokes, deslant: language != .japanese)
        guard let img = Rasterizer.render(norm) else { return [] }
        return await recognize(img, language: language)
    }

    public static func recognize(_ image: CGImage, language: RecognitionLanguage) async -> [String] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = true
                req.minimumTextHeight = 0
                switch language {
                case .english: req.recognitionLanguages = ["en-US"]
                case .japanese: req.recognitionLanguages = ["ja-JP", "en-US"]
                case .auto: req.recognitionLanguages = ["en-US", "ja-JP"]; req.automaticallyDetectsLanguage = true
                }
                try? VNImageRequestHandler(cgImage: image).perform([req])
                let obs = (req.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                let out: [String]
                if obs.count == 1 { out = obs[0].topCandidates(3).map(\.string) }
                else { out = [obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")] }
                cont.resume(returning: out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            }
        }
    }
}
