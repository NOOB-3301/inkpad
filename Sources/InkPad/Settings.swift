import Foundation
import InkPadCore

final class Settings {
    static let shared = Settings()
    private let ud = UserDefaults.standard

    var gestureFingers: Int {
        get { ud.integer(forKey: "gestureFingers") == 5 ? 5 : 4 }
        set { ud.set(newValue, forKey: "gestureFingers") }
    }
    var wait: Double {
        get { let v = ud.double(forKey: "wait"); return v == 0 ? 1.0 : v }
        set { ud.set(newValue, forKey: "wait") }
    }
    var language: RecognitionLanguage {
        get { RecognitionLanguage(rawValue: ud.string(forKey: "language") ?? "") ?? .english }
        set { ud.set(newValue.rawValue, forKey: "language") }
    }
    var online: Bool {
        get { ud.object(forKey: "online") as? Bool ?? true }
        set { ud.set(newValue, forKey: "online") }
    }
    /// false = auto-insert after pause, true = pick from candidates
    var pickMode: Bool {
        get { ud.bool(forKey: "pickMode") }
        set { ud.set(newValue, forKey: "pickMode") }
    }
    /// 0 off, 1 light, 2 strong
    var haptics: Int {
        get { ud.object(forKey: "haptics") as? Int ?? 1 }
        set { ud.set(newValue, forKey: "haptics") }
    }
    // Carbon key code + modifiers. Default ⌃⌥Space.
    var hotKey: (code: UInt32, mods: UInt32, name: String) {
        get {
            guard ud.object(forKey: "hkCode") != nil else { return (49, 4096 | 2048, "⌃⌥Space") }
            return (UInt32(ud.integer(forKey: "hkCode")), UInt32(ud.integer(forKey: "hkMods")), ud.string(forKey: "hkName") ?? "?")
        }
        set { ud.set(Int(newValue.code), forKey: "hkCode"); ud.set(Int(newValue.mods), forKey: "hkMods"); ud.set(newValue.name, forKey: "hkName") }
    }
}
