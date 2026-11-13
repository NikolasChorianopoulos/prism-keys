import AppKit

func NSEventModifierFlagsRaw(_ v: UInt) -> NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: v) }

func postSystemDefined(flags: NSEvent.ModifierFlags, data1: Int) {
    let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
    ev?.cgEvent?.post(tap: .cghidEventTap)
}
