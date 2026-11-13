import Foundation

/// Key remapping scoped to the Razer keyboard only, using macOS's built-in `hidutil`
/// (no permissions needed; does not affect the MacBook's built-in keyboard).
///
/// Keys bound to macros are remapped to otherwise-unused "slot" keys (F16–F20 etc.).
/// The background service catches those slot keys and runs the macro.
public enum Remapper {
    public struct Slot { public let name: String; public let vk: UInt16; public let usage: UInt32 }

    /// Keys that no normal keyboard in this setup produces. F13–F15 are avoided because
    /// macOS reports Print Screen / Scroll Lock / Pause as F13–F15.
    public static let slots: [Slot] = [
        Slot(name: "f16", vk: 0x6A, usage: 0x6B), Slot(name: "f17", vk: 0x40, usage: 0x6C),
        Slot(name: "f18", vk: 0x4F, usage: 0x6D), Slot(name: "f19", vk: 0x50, usage: 0x6E),
        Slot(name: "f20", vk: 0x5A, usage: 0x6F), Slot(name: "kp_equals", vk: 0x51, usage: 0x67),
        Slot(name: "jis_yen", vk: 0x5D, usage: 0x89), Slot(name: "jis_ro", vk: 0x5E, usage: 0x87),
        Slot(name: "kp_comma", vk: 0x5F, usage: 0x85),
    ]

    /// Source HID usage for a key. M1–M5 have none: the engine reads them directly.
    public static func sourceUsage(_ key: Key) -> UInt32? { key.usage }

    /// Keys macOS never sees (M1–M5): macros/remaps on them are handled by the engine.
    public static func isDirect(_ name: String) -> Bool { KeyLayout.key(name)?.usage == nil }

    /// Macro key name -> slot, in a stable order.
    public static func slotAssignments(_ p: Profile) -> [String: Slot] {
        var out: [String: Slot] = [:]
        for (i, name) in p.macros.keys.filter({ !isDirect($0) }).sorted().enumerated() where i < slots.count {
            out[KeyLayout.key(name)?.name ?? name] = slots[i]
        }
        return out
    }

    public static func mappings(_ p: Profile, includeMacros: Bool = true, gameMode: Bool = false) -> (pairs: [(UInt32, UInt32)], warnings: [String]) {
        var pairs: [(UInt32, UInt32)] = []
        var warnings: [String] = []
        let assigned = includeMacros ? slotAssignments(p) : [:]
        if p.macros.count > slots.count { warnings.append("Only \(slots.count) macros can be active at once; extra ones are ignored.") }
        for (from, to) in p.remaps.sorted(by: { $0.key < $1.key }) where assigned[from] == nil && !isDirect(from) {
            guard let fk = KeyLayout.key(from), let src = sourceUsage(fk) else { continue }
            let dst: UInt32
            if let tk = KeyLayout.key(to), let u = tk.usage { dst = u }
            else if let x = KeyLayout.extraTargets[to.lowercased()] { dst = x.usage }
            else { warnings.append("Unknown remap target '\(to)'."); continue }
            pairs.append((src, dst))
        }
        for (name, slot) in assigned {
            guard let k = KeyLayout.key(name), let src = sourceUsage(k) else {
                warnings.append("Macro on '\(name)' can't fire yet: the keyboard doesn't report this key to macOS (use the M-key setup in Settings → Keys & Macros).")
                continue
            }
            pairs.append((src, slot.usage))
        }
        return (pairs, warnings)
    }

    @discardableResult
    public static func apply(_ p: Profile, model: DeviceModel, includeMacros: Bool = true, gameMode: Bool = false) -> [String] {
        let (pairs, warnings) = mappings(p, includeMacros: includeMacros, gameMode: gameMode)
        let items = pairs.map {
            String(format: "{\"HIDKeyboardModifierMappingSrc\":0x7%08X,\"HIDKeyboardModifierMappingDst\":0x7%08X}", $0.0, $0.1)
        }
        let set = "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"
        let match = String(format: "{\"VendorID\":0x%04X,\"ProductID\":0x%04X}", RazerKeyboard.vendorID, model.productID)
        let (status, out) = run("/usr/bin/hidutil", ["property", "--matching", match, "--set", set])
        var w = warnings
        if status != 0 { w.append("hidutil failed: \(out)") }
        return w
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
