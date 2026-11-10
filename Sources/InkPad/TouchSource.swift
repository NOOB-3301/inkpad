import Foundation
import InkPadCore

private typealias MTCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

private func mtFrame(_ device: UnsafeMutableRawPointer?, _ data: UnsafeMutableRawPointer?, _ count: Int32, _ ts: Double, _ frame: Int32) -> Int32 {
    var touches: [TouchPoint] = []
    if let data, count > 0 {
        for i in 0..<Int(count) {
            let p = data + i * 96  // MTTouch struct is 96 bytes
            let state = p.load(fromByteOffset: 20, as: Int32.self)
            guard state == 3 || state == 4 else { continue }  // making touch / touching
            touches.append(TouchPoint(id: Int(p.load(fromByteOffset: 16, as: Int32.self)),
                                      x: p.load(fromByteOffset: 32, as: Float.self),
                                      y: p.load(fromByteOffset: 36, as: Float.self)))
        }
    }
    let dev = Int(bitPattern: device)
    let f = TouchFrame(time: ts, touches: touches)
    DispatchQueue.main.async { TouchSource.shared.deliver(f, device: dev) }
    return 0
}

/// Raw global trackpad touches via Apple's private MultitouchSupport.framework (no public API does this).
final class TouchSource {
    static let shared = TouchSource()
    var onFrame: ((TouchFrame) -> Void)?
    private var devices: CFArray?
    private var activeDevice: Int?
    private var started = false

    func start() {
        guard !started else { return }
        guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let createList = dlsym(h, "MTDeviceCreateList"),
              let register = dlsym(h, "MTRegisterContactFrameCallback"),
              let startDev = dlsym(h, "MTDeviceStart")
        else { NSLog("InkPad: MultitouchSupport unavailable"); return }
        typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
        typealias Register = @convention(c) (UnsafeMutableRawPointer, MTCallback) -> Void
        typealias StartDev = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
        guard let list = unsafeBitCast(createList, to: CreateList.self)()?.takeRetainedValue() else { return }
        devices = list
        Haptics.shared.setup(handle: h, devices: list)
        for i in 0..<CFArrayGetCount(list) {
            let d = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, i))!
            unsafeBitCast(register, to: Register.self)(d, mtFrame)
            unsafeBitCast(startDev, to: StartDev.self)(d, 0)
        }
        started = true
        NSLog("InkPad: listening to %ld multitouch device(s)", CFArrayGetCount(list))
    }

    /// Wake from sleep: devices stop delivering; start them again.
    func restart() { started = false; start() }

    fileprivate func deliver(_ f: TouchFrame, device: Int) {
        // With several trackpads, follow only the one currently touched.
        if f.touches.isEmpty {
            guard activeDevice == nil || activeDevice == device else { return }
            activeDevice = nil
        } else {
            if activeDevice == nil { activeDevice = device }
            guard activeDevice == device else { return }
        }
        onFrame?(f)
    }
}

import AppKit
import IOKit

/// Trackpad taps. Private MTActuator works even when our app is in the background; NSHaptic is the fallback.
final class Haptics {
    static let shared = Haptics()
    private typealias Actuate = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32
    private var actuator: CFTypeRef?
    private var actuate: Actuate?

    private typealias Create = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias Open = @convention(c) (CFTypeRef) -> Int32
    private var create: Create?, open: Open?
    private var deviceID: UInt64 = 0

    /// Same approach as HapticKey: actuator id = IORegistry "Multitouch ID" of the built-in, actuation-capable trackpad.
    func setup(handle h: UnsafeMutableRawPointer, devices: CFArray) {
        guard actuator == nil, let c = dlsym(h, "MTActuatorCreateFromDeviceID"),
              let o = dlsym(h, "MTActuatorOpen"), let a = dlsym(h, "MTActuatorActuate") else { return }
        create = unsafeBitCast(c, to: Create.self); open = unsafeBitCast(o, to: Open.self)
        actuate = unsafeBitCast(a, to: Actuate.self)
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &it) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(it) }
        while case let svc = IOIteratorNext(it), svc != 0 {
            defer { IOObjectRelease(svc) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let d = props?.takeRetainedValue() as? [String: Any],
                  (d["ActuationSupported"] as? Bool) == true,
                  let id = (d["Multitouch ID"] as? NSNumber)?.uint64Value else { continue }
            deviceID = id
            if openActuator() { NSLog("InkPad: haptic actuator ready (%@)", d["Product"] as? String ?? "?"); return }
        }
        NSLog("InkPad: no haptic actuator, using NSHapticFeedbackManager")
    }

    private func openActuator() -> Bool {
        guard deviceID != 0, let create, let open, let act = create(deviceID)?.takeRetainedValue(), open(act) == 0 else { return false }
        actuator = act
        return true
    }

    /// strength: 0 = glide tick, 1 = event (insert / delete)
    func play(_ strength: Int) {
        let level = Settings.shared.haptics
        guard level > 0 else { return }
        if let actuator, let actuate {
            let id: Int32 = strength == 0 ? (level == 1 ? 3 : 4) : 6
            if actuate(actuator, id, 0, 0, 0) != 0, openActuator(), let a = self.actuator { _ = actuate(a, id, 0, 0, 0) }
        } else {
            NSHapticFeedbackManager.defaultPerformer.perform(strength == 0 ? .alignment : .levelChange, performanceTime: .now)
        }
    }
}
