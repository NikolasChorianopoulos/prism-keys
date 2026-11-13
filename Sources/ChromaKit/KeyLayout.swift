import Foundation

/// One physical key: its LED matrix position, macOS virtual keycode, and USB HID usage.
public struct Key {
    public let name: String
    public let aliases: [String]
    public let row: Int
    public let col: Int
    /// macOS virtual key code (kVK_*), nil if macOS never sees this key (Fn, logo, M-keys in normal mode).
    public let vk: UInt16?
    /// USB HID keyboard usage (page 0x07), used for per-device remapping with hidutil.
    public let usage: UInt32?
}

/// US/ISO layout of the Razer BlackWidow Chroma (6 x 22 LED matrix).
public enum KeyLayout {
    public static let keys: [Key] = {
        var k: [Key] = []
        func add(_ n: String, _ r: Int, _ c: Int, vk: UInt16?, hid: UInt32?, _ a: [String] = []) {
            k.append(Key(name: n, aliases: a, row: r, col: c, vk: vk, usage: hid))
        }
        // Row 0
        add("esc", 0, 1, vk: 0x35, hid: 0x29, ["escape"])
        let fvk: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        for i in 0..<12 { add("f\(i + 1)", 0, 3 + i, vk: fvk[i], hid: 0x3A + UInt32(i)) }
        add("printscreen", 0, 15, vk: 0x69, hid: 0x46, ["prtsc", "print"])
        add("scrolllock", 0, 16, vk: 0x6B, hid: 0x47, ["scrlk"])
        add("pause", 0, 17, vk: 0x71, hid: 0x48, ["break"])
        add("logo", 0, 20, vk: nil, hid: nil, ["razer"])
        // Row 1
        add("m1", 1, 0, vk: nil, hid: nil)
        add("grave", 1, 1, vk: 0x32, hid: 0x35, ["`", "tilde", "backtick"])
        let numvk: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]
        for i in 0..<10 { add(i == 9 ? "0" : "\(i + 1)", 1, 2 + i, vk: numvk[i], hid: 0x1E + UInt32(i)) }
        add("minus", 1, 12, vk: 0x1B, hid: 0x2D, ["-"])
        add("equal", 1, 13, vk: 0x18, hid: 0x2E, ["=", "equals"])
        add("backspace", 1, 14, vk: 0x33, hid: 0x2A, ["bksp"])
        add("insert", 1, 15, vk: 0x72, hid: 0x49, ["ins", "help"])
        add("home", 1, 16, vk: 0x73, hid: 0x4A)
        add("pageup", 1, 17, vk: 0x74, hid: 0x4B, ["pgup"])
        add("numlock", 1, 18, vk: 0x47, hid: 0x53, ["clear"])
        add("kp_divide", 1, 19, vk: 0x4B, hid: 0x54, ["kp/"])
        add("kp_multiply", 1, 20, vk: 0x43, hid: 0x55, ["kp*"])
        add("kp_minus", 1, 21, vk: 0x4E, hid: 0x56, ["kp-"])
        // Row 2
        add("m2", 2, 0, vk: nil, hid: nil)
        add("tab", 2, 1, vk: 0x30, hid: 0x2B)
        let r2 = Array("qwertyuiop"); let r2vk: [UInt16] = [0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x10, 0x20, 0x22, 0x1F, 0x23]
        let hid: (Character) -> UInt32 = { 0x04 + UInt32($0.asciiValue! - 97) }
        for i in 0..<10 { add(String(r2[i]), 2, 2 + i, vk: r2vk[i], hid: hid(r2[i])) }
        add("lbracket", 2, 12, vk: 0x21, hid: 0x2F, ["["])
        add("rbracket", 2, 13, vk: 0x1E, hid: 0x30, ["]"])
        add("backslash", 2, 14, vk: 0x2A, hid: 0x31, ["\\"])
        add("delete", 2, 15, vk: 0x75, hid: 0x4C, ["del"])
        add("end", 2, 16, vk: 0x77, hid: 0x4D)
        add("pagedown", 2, 17, vk: 0x79, hid: 0x4E, ["pgdn"])
        add("kp7", 2, 18, vk: 0x59, hid: 0x5F); add("kp8", 2, 19, vk: 0x5B, hid: 0x60); add("kp9", 2, 20, vk: 0x5C, hid: 0x61)
        add("kp_plus", 2, 21, vk: 0x45, hid: 0x57, ["kp+"])
        // Row 3
        add("m3", 3, 0, vk: nil, hid: nil)
        add("capslock", 3, 1, vk: 0x39, hid: 0x39, ["caps"])
        let r3 = Array("asdfghjkl"); let r3vk: [UInt16] = [0x00, 0x01, 0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25]
        for i in 0..<9 { add(String(r3[i]), 3, 2 + i, vk: r3vk[i], hid: hid(r3[i])) }
        add("semicolon", 3, 11, vk: 0x29, hid: 0x33, [";"])
        add("quote", 3, 12, vk: 0x27, hid: 0x34, ["'", "apostrophe"])
        add("iso_hash", 3, 13, vk: nil, hid: 0x32)
        add("enter", 3, 14, vk: 0x24, hid: 0x28, ["return"])
        add("kp4", 3, 18, vk: 0x56, hid: 0x5C); add("kp5", 3, 19, vk: 0x57, hid: 0x5D); add("kp6", 3, 20, vk: 0x58, hid: 0x5E)
        // Row 4
        add("m4", 4, 0, vk: nil, hid: nil)
        add("lshift", 4, 1, vk: 0x38, hid: 0xE1, ["shift"])
        add("iso_backslash", 4, 2, vk: 0x0A, hid: 0x64)
        let r4 = Array("zxcvbnm"); let r4vk: [UInt16] = [0x06, 0x07, 0x08, 0x09, 0x0B, 0x2D, 0x2E]
        for i in 0..<7 { add(String(r4[i]), 4, 3 + i, vk: r4vk[i], hid: hid(r4[i])) }
        add("comma", 4, 10, vk: 0x2B, hid: 0x36, [","])
        add("period", 4, 11, vk: 0x2F, hid: 0x37, ["."])
        add("slash", 4, 12, vk: 0x2C, hid: 0x38, ["/"])
        add("rshift", 4, 14, vk: 0x3C, hid: 0xE5)
        add("up", 4, 16, vk: 0x7E, hid: 0x52)
        add("kp1", 4, 18, vk: 0x53, hid: 0x59); add("kp2", 4, 19, vk: 0x54, hid: 0x5A); add("kp3", 4, 20, vk: 0x55, hid: 0x5B)
        add("kp_enter", 4, 21, vk: 0x4C, hid: 0x58)
        // Row 5
        add("m5", 5, 0, vk: nil, hid: nil)
        add("lctrl", 5, 1, vk: 0x3B, hid: 0xE0, ["ctrl", "control"])
        add("lwin", 5, 2, vk: 0x37, hid: 0xE3, ["win", "lcmd", "cmd", "command"])
        add("lalt", 5, 3, vk: 0x3A, hid: 0xE2, ["alt", "lopt", "option", "opt"])
        add("space", 5, 7, vk: 0x31, hid: 0x2C)
        add("ralt", 5, 11, vk: 0x3D, hid: 0xE6, ["ropt"])
        add("fn", 5, 12, vk: nil, hid: nil)
        add("menu", 5, 13, vk: 0x6E, hid: 0x65, ["app", "context"])
        add("rctrl", 5, 14, vk: 0x3E, hid: 0xE4)
        add("left", 5, 15, vk: 0x7B, hid: 0x50)
        add("down", 5, 16, vk: 0x7D, hid: 0x51)
        add("right", 5, 17, vk: 0x7C, hid: 0x4F)
        add("kp0", 5, 19, vk: 0x52, hid: 0x62)
        add("kp_decimal", 5, 20, vk: 0x41, hid: 0x63, ["kp."])
        return k
    }()

    /// Keys macOS can type/send but that do not exist on this keyboard (remap targets / macro output).
    public static let extraTargets: [String: (vk: UInt16, usage: UInt32)] = [
        "f13": (0x69, 0x68), "f14": (0x6B, 0x69), "f15": (0x71, 0x6A), "f16": (0x6A, 0x6B),
        "f17": (0x40, 0x6C), "f18": (0x4F, 0x6D), "f19": (0x50, 0x6E), "f20": (0x5A, 0x6F),
        "rcmd": (0x36, 0xE7), "rwin": (0x36, 0xE7),
        "volumeup": (0x48, 0x80), "volumedown": (0x49, 0x81), "mute": (0x4A, 0x7F),
        "none": (0xFFFF, 0x00),
    ]

    private static let index: [String: Key] = {
        var d: [String: Key] = [:]
        for k in keys {
            d[k.name] = k
            for a in k.aliases where d[a] == nil { d[a] = k }
        }
        return d
    }()

    public static func key(_ name: String) -> Key? { index[name.lowercased()] }

    public static func key(vk: UInt16) -> Key? { keys.first { $0.vk == vk } }

    public static let groups: [String: [String]] = {
        var g: [String: [String]] = [:]
        g["letters"] = "abcdefghijklmnopqrstuvwxyz".map { String($0) }
        g["numbers"] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        g["fkeys"] = (1...12).map { "f\($0)" }
        g["wasd"] = ["w", "a", "s", "d"]
        g["arrows"] = ["up", "down", "left", "right"]
        g["macro"] = ["m1", "m2", "m3", "m4", "m5"]
        g["numpad"] = keys.filter { $0.name.hasPrefix("kp") || $0.name == "numlock" }.map(\.name)
        g["nav"] = ["insert", "home", "pageup", "delete", "end", "pagedown"]
        g["modifiers"] = ["lshift", "rshift", "lctrl", "rctrl", "lalt", "ralt", "lwin", "fn", "menu", "capslock"]
        g["all"] = keys.map(\.name)
        for r in 0..<6 { g["row\(r)"] = keys.filter { $0.row == r }.map(\.name) }
        return g
    }()

    /// Expands "wasd", "f1-f4", "q,w,e" etc. into concrete keys.
    public static func resolve(_ spec: String) throws -> [Key] {
        var out: [Key] = []
        for raw in spec.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) where !raw.isEmpty {
            if let g = groups[raw] { out += g.compactMap { key($0) }; continue }
            if let k = key(raw) { out.append(k); continue }
            // Range like f1-f6 or 1-5 (but not the "-" key itself, or "kp-")
            if raw.count > 2, let dash = raw.firstIndex(of: "-"), dash != raw.startIndex {
                let a = String(raw[..<dash]), b = String(raw[raw.index(after: dash)...])
                if let ka = key(a), let kb = key(b), ka.row == kb.row {
                    let lo = min(ka.col, kb.col), hi = max(ka.col, kb.col)
                    out += keys.filter { $0.row == ka.row && $0.col >= lo && $0.col <= hi }
                    continue
                }
            }
            throw ChromaError.invalid("Unknown key or group '\(raw)'. Run `chroma keys` to see names.")
        }
        return out
    }
}
