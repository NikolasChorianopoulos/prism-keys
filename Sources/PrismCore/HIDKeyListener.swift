import Foundation
import IOKit.hid

/// Listens to raw HID input from the Razer keyboard. Used to discover what the M1–M5
/// keys send. Needs the Input Monitoring permission.
public final class HIDKeyListener {
    public typealias Handler = (_ page: UInt32, _ usage: UInt32, _ pressed: Bool) -> Void
    private var manager: IOHIDManager?
    private var handler: Handler?

    public init() {}

    public static var hasPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    public static func requestPermission() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    public func start(_ handler: @escaping Handler) throws {
        stop()
        self.handler = handler
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let models = RazerKeyboard.supported.map {
            [kIOHIDVendorIDKey: Int(RazerKeyboard.vendorID), kIOHIDProductIDKey: Int($0.productID)] as [String: Any]
        }
        IOHIDManagerSetDeviceMatchingMultiple(mgr, models as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, _, value in
            guard let ctx else { return }
            let me = Unmanaged<HIDKeyListener>.fromOpaque(ctx).takeUnretainedValue()
            let el = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(el), usage = IOHIDElementGetUsage(el)
            let v = IOHIDValueGetIntegerValue(value)
            if page == 0x07 && (usage == 0xFFFFFFFF || usage < 4) { return }
            if page == 0x01 || page == 0x09 { return }
            me.handler?(page, usage, v != 0)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            throw ChromaError.io("Prism Keys needs the Input Monitoring permission to read the M-keys.")
        }
        manager = mgr
    }

    public func stop() {
        if let m = manager {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        handler = nil
    }
}
