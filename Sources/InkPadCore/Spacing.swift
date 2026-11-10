import Foundation

public enum Spacing {
    static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains {
            switch $0.value {
            case 0x3000...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xFF00...0xFFEF, 0xAC00...0xD7AF: return true
            default: return false
            }
        }
    }

    /// Text to insert so consecutive pieces join naturally: space between latin words, none around CJK/punctuation.
    public static func join(previous: String?, next: String) -> String {
        guard let last = previous?.last, let first = next.first else { return next }
        if last.isWhitespace || first.isWhitespace { return next }
        if isCJK(last) || isCJK(first) { return next }
        if ".,!?;:)]}%".contains(first) { return next }
        if "([{".contains(last) { return next }
        return " " + next
    }
}
