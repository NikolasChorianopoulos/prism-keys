import Foundation
import IOKit.hid

/// Prints raw HID input from the Razer keyboard (needs Input Monitoring for your terminal app).
public enum KeyTest {
    public static func run(seconds: Double) throws {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let models = RazerKeyboard.supported.map { [kIOHIDVendorIDKey: Int(RazerKeyboard.vendorID), kIOHIDProductIDKey: Int($0.productID)] as [String: Any] }
        IOHIDManagerSetDeviceMatchingMultiple(mgr, models as CFArray)
        IOHIDManagerRegisterInputValueCallback(mgr, { _, _, _, value in
            let el = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(el), usage = IOHIDElementGetUsage(el)
            let v = IOHIDValueGetIntegerValue(value)
            if page == 0x07 && (usage == 0xFFFFFFFF || usage < 4) { return } // rollover noise
            if page == 0x01 || page == 0x09 { return }                        // mouse-ish noise
            if v == 0 && page == 0x07 { return }
            let name = page == 0x07 ? (KeyLayout.keys.first { $0.usage == usage }?.name ?? "?") : ""
            print(String(format: "  page 0x%02X  usage 0x%02X  value %d  %@", page, usage, v, name))
            fflush(stdout)
        }, nil)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess {
            throw ChromaError.io("""
            Can't read the keyboard (0x\(String(UInt32(bitPattern: r), radix: 16))).
            Give your terminal app the Input Monitoring permission:
              System Settings → Privacy & Security → Input Monitoring → enable Terminal (or your terminal app), then reopen it.
            """)
        }
        CFRunLoopRunInMode(.defaultMode, seconds, false)
    }
}
