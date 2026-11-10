import AppKit
import CoreGraphics

func dlog(_ m: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/InkPad.log")
    let line = "\(Date()) \(m)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

private var gateTap: CFMachPort?
nonisolated(unsafe) private var swallowing = false
nonisolated(unsafe) private var swallowedCount = 0

private func gateCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = gateTap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if swallowing { swallowedCount += 1 }
    return swallowing ? nil : Unmanaged.passUnretained(event)
}

/// While fingers write on the trackpad, drop its pointer events (move, click, scroll) so the cursor stays put
/// and nothing leaks into other apps. Needs Accessibility, which InkPad already asks for.
enum CursorGate {
    @discardableResult
    static func install() -> Bool {
        guard gateTap == nil else { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
                                    .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: gateCallback, userInfo: nil) else {
            dlog("cursor gate: tapCreate FAILED (trusted=\(AXIsProcessTrusted()))")
            return false
        }
        dlog("cursor gate: installed")
        gateTap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        return true
    }

    static func set(_ on: Bool) {
        swallowing = on
        if !on { dlog("gate off, swallowed \(swallowedCount) events so far") }
        if on { install() }
    }
}
