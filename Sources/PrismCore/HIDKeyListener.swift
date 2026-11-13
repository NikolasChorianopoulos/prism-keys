import Foundation
import IOKit.hid

/// Reads the keyboard's vendor "report 4", which in driver mode carries the keys macOS can't
/// see: Fn (0x01) and M1–M5 (0x20–0x24). Needs the Input Monitoring permission.
public final class RazerInputListener {
    public enum SpecialKey: Equatable {
        case fn
        case macro(Int)       // 1...5
        case other(UInt8)
    }
    public var onKey: ((SpecialKey, Bool) -> Void)?   // (key, pressed)

    private var manager: IOHIDManager?
    private var held = Set<UInt8>()
    private var buffer = [UInt8](repeating: 0, count: 64)

    public init() {}

    public static var hasPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
    public static func requestPermission() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    public var isRunning: Bool { manager != nil }

    /// Must be called on the main thread.
    public func start() throws {
        guard manager == nil else { return }
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let models = RazerKeyboard.supported.map {
            [kIOHIDVendorIDKey: Int(RazerKeyboard.vendorID), kIOHIDProductIDKey: Int($0.productID)] as [String: Any]
        }
        IOHIDManagerSetDeviceMatchingMultiple(mgr, models as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputReportCallback(mgr, { ctx, _, _, _, reportID, report, length in
            guard let ctx, length >= 2, report[0] == 0x04 else { return }
            let me = Unmanaged<RazerInputListener>.fromOpaque(ctx).takeUnretainedValue()
            var now = Set<UInt8>()
            for i in 1..<min(length, 16) where report[i] != 0 { now.insert(report[i]) }
            me.update(now)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            throw ChromaError.io("Input Monitoring permission is needed to read the M-keys.")
        }
        manager = mgr
    }

    public func stop() {
        if let m = manager {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        for c in held { onKey?(Self.decode(c), false) }
        held = []
    }

    private func update(_ now: Set<UInt8>) {
        for c in now.subtracting(held) { onKey?(Self.decode(c), true) }
        for c in held.subtracting(now) { onKey?(Self.decode(c), false) }
        held = now
    }

    static func decode(_ c: UInt8) -> SpecialKey {
        switch c {
        case 0x01: return .fn
        case 0x20...0x24: return .macro(Int(c - 0x20) + 1)
        default: return .other(c)
        }
    }
}

/// Sends media / system keys (volume, play/pause…) the way Apple keyboards do.
public enum MediaKeys {
    public static let soundUp: Int32 = 0, soundDown: Int32 = 1, mute: Int32 = 7
    public static let play: Int32 = 16, next: Int32 = 17, previous: Int32 = 18

    public static func press(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEventModifierFlagsRaw(down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            postSystemDefined(flags: flags, data1: data1)
        }
    }
}
