import Foundation

/// 24-bit RGB color. Encodes to/decodes from "#rrggbb" in JSON.
public struct RGB: Codable, Hashable, Equatable, CustomStringConvertible {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(255, 255, 255)

    public static let named: [String: RGB] = [
        "black": RGB(0, 0, 0), "off": RGB(0, 0, 0), "white": RGB(255, 255, 255),
        "red": RGB(255, 0, 0), "green": RGB(0, 255, 0), "blue": RGB(0, 0, 255),
        "yellow": RGB(255, 200, 0), "orange": RGB(255, 80, 0), "purple": RGB(140, 0, 255),
        "pink": RGB(255, 40, 140), "magenta": RGB(255, 0, 255), "cyan": RGB(0, 255, 255),
        "teal": RGB(0, 160, 128), "razer": RGB(0, 255, 0), "gold": RGB(255, 170, 0),
        "violet": RGB(180, 60, 255), "lime": RGB(140, 255, 0), "amber": RGB(255, 120, 0),
        "ice": RGB(120, 200, 255), "warm": RGB(255, 140, 60),
    ]

    /// Parses "#ff8800", "ff8800", "f80", "255,136,0" or a color name.
    public init?(parse s: String) {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if let n = RGB.named[t] { self = n; return }
        if t.contains(",") {
            let p = t.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard p.count == 3, p.allSatisfy({ (0...255).contains($0) }) else { return nil }
            self = RGB(UInt8(p[0]), UInt8(p[1]), UInt8(p[2])); return
        }
        var h = t.hasPrefix("#") ? String(t.dropFirst()) : t
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self = RGB(UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "#%02x%02x%02x", r, g, b) }
    public var description: String { hex }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let c = RGB(parse: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad color \(s)"))
        }
        self = c
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(hex)
    }

    /// h in 0..<1, s,v in 0...1
    public static func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let hh = (h - floor(h)) * 6
        let i = Int(hh), f = hh - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double)
        switch i % 6 {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return RGB(UInt8(clamping: Int(r * 255)), UInt8(clamping: Int(g * 255)), UInt8(clamping: Int(b * 255)))
    }

    public func scaled(_ k: Double) -> RGB {
        let k = max(0, min(1, k))
        return RGB(UInt8(Double(r) * k), UInt8(Double(g) * k), UInt8(Double(b) * k))
    }

    public func mix(_ o: RGB, _ t: Double) -> RGB {
        let t = max(0, min(1, t))
        func m(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8(Double(a) + (Double(b) - Double(a)) * t) }
        return RGB(m(r, o.r), m(g, o.g), m(b, o.b))
    }

    public func adding(_ o: RGB) -> RGB {
        RGB(UInt8(clamping: Int(r) + Int(o.r)), UInt8(clamping: Int(g) + Int(o.g)), UInt8(clamping: Int(b) + Int(o.b)))
    }
}
