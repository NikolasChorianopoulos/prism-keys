import Foundation
import IOKit.hid

/// Drives the keyboard's standard lock indicators (HID LED page): 1 = Num, 2 = Caps, 3 = Scroll.
/// Needs Input Monitoring. Call on the main thread.
public final class LockLights {
    public static let num: UInt32 = 1, caps: UInt32 = 2, scroll: UInt32 = 3
    private var manager: IOHIDManager?
    private var elements: [UInt32: [(IOHIDDevice, IOHIDElement)]] = [:]
    private var last: [UInt32: Bool] = [:]

    public init() {}

    /// (Re)discovers the LED elements, e.g. after the keyboard is plugged in.
    public func reload() {
        if manager == nil {
            let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let models = RazerKeyboard.supported.map {
                [kIOHIDVendorIDKey: Int(RazerKeyboard.vendorID), kIOHIDProductIDKey: Int($0.productID)] as [String: Any]
            }
            IOHIDManagerSetDeviceMatchingMultiple(m, models as CFArray)
            guard IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
            manager = m
        }
        elements = [:]; last = [:]
        let devices = (IOHIDManagerCopyDevices(manager!) as? Set<IOHIDDevice>) ?? []
        for d in devices {
            let els = (IOHIDDeviceCopyMatchingElements(d, [kIOHIDElementUsagePageKey: kHIDPage_LEDs] as CFDictionary,
                                                      IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []
            for e in els { elements[IOHIDElementGetUsage(e), default: []].append((d, e)) }
        }
    }

    /// Sets an indicator. `force` re-sends even if unchanged (macOS sometimes rewrites the LEDs).
    public func set(_ usage: UInt32, _ on: Bool, force: Bool = false) {
        if !force, last[usage] == on { return }
        if elements.isEmpty { reload() }
        guard let list = elements[usage] else { return }
        for (d, e) in list {
            let v = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, e, mach_absolute_time(), on ? 1 : 0)
            IOHIDDeviceSetValue(d, e, v)
        }
        last[usage] = on
    }
}
