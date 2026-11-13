import CRazerUSB
import Foundation

public struct DeviceModel {
    public let productID: UInt16
    public let name: String
    public let rows: Int
    public let cols: Int
    public let transactionID: UInt8
    public let hasMacroKeys: Bool
}

public enum ChromaError: Error, CustomStringConvertible {
    case noDevice
    case usb(String)
    case invalid(String)
    case io(String)
    public var description: String {
        switch self {
        case .noDevice: return "No supported Razer keyboard found. Is it plugged in?"
        case .usb(let s): return "USB error: \(s)"
        case .invalid(let s): return s
        case .io(let s): return s
        }
    }
}

/// Talks to a Razer keyboard via HID feature reports sent as raw USB control transfers.
/// This approach needs no special macOS permissions (no Input Monitoring required).
public final class RazerKeyboard {
    public static let vendorID: UInt16 = 0x1532
    public static let supported: [DeviceModel] = [
        DeviceModel(productID: 0x0203, name: "Razer BlackWidow Chroma", rows: 6, cols: 22, transactionID: 0xFF, hasMacroKeys: true),
        DeviceModel(productID: 0x0209, name: "Razer BlackWidow Chroma Tournament Edition", rows: 6, cols: 22, transactionID: 0xFF, hasMacroKeys: false),
        DeviceModel(productID: 0x0211, name: "Razer BlackWidow Chroma (Overwatch)", rows: 6, cols: 22, transactionID: 0xFF, hasMacroKeys: true),
    ]

    public let model: DeviceModel
    private let handle: OpaquePointer
    private let interfaceIndex: UInt16 = 1
    private let lock = NSLock()

    public static func isConnected() -> Bool {
        supported.contains { razer_usb_count(vendorID, $0.productID) > 0 }
    }

    public init() throws {
        for m in RazerKeyboard.supported {
            if let h = razer_usb_open(RazerKeyboard.vendorID, m.productID) {
                self.model = m
                self.handle = h
                return
            }
        }
        throw ChromaError.noDevice
    }

    deinit { razer_usb_close(handle) }

    // MARK: - Low level

    private func makeReport(_ cls: UInt8, _ id: UInt8, _ args: [UInt8], size: Int? = nil) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 90)
        b[0] = 0x00                 // status (new command)
        b[1] = model.transactionID  // transaction id
        b[5] = UInt8(size ?? args.count)
        b[6] = cls
        b[7] = id
        for (i, a) in args.prefix(80).enumerated() { b[8 + i] = a }
        var crc: UInt8 = 0
        for i in 2..<88 { crc ^= b[i] }
        b[88] = crc
        return b
    }

    /// Sends a command and (optionally) reads back the response.
    @discardableResult
    public func command(_ cls: UInt8, _ id: UInt8, _ args: [UInt8], size: Int? = nil, readResponse: Bool = true) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        var req = makeReport(cls, id, args, size: size)
        let s = razer_usb_set_report(handle, interfaceIndex, &req, 90)
        if s != 0 { throw ChromaError.usb(String(format: "set report failed (0x%x)", UInt32(bitPattern: Int32(s)))) }
        guard readResponse else { usleep(1000); return [] }
        var resp = [UInt8](repeating: 0, count: 90)
        // The device needs a moment to process; poll for a non-busy status.
        for _ in 0..<10 {
            usleep(4000)
            let g = razer_usb_get_report(handle, interfaceIndex, &resp, 90)
            if g != 0 { throw ChromaError.usb(String(format: "get report failed (0x%x)", UInt32(bitPattern: Int32(g)))) }
            if resp[0] != 0x01 { break } // 0x01 = busy
        }
        switch resp[0] {
        case 0x02, 0x00: return resp
        case 0x03: throw ChromaError.usb("device reported failure for command \(String(format: "%02x:%02x", cls, id))")
        case 0x05: throw ChromaError.usb("command not supported by this device")
        default: return resp
        }
    }

    // MARK: - Info

    public func firmwareVersion() throws -> String {
        let r = try command(0x00, 0x81, [], size: 0x02)
        return "v\(r[8]).\(r[9])"
    }

    public func serial() throws -> String {
        let r = try command(0x00, 0x82, [], size: 0x16)
        let bytes = r[8..<(8 + 22)].prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Brightness (0...255)

    public func brightness() throws -> UInt8 {
        let r = try command(0x03, 0x83, [0x01, 0x05, 0x00])
        return r[10]
    }

    public func setBrightness(_ v: UInt8) throws {
        try command(0x03, 0x03, [0x01, 0x05, v])
    }

    // MARK: - Hardware effects (run on the keyboard itself, persist until power loss)

    public func effectNone() throws { try command(0x03, 0x0A, [0x00]) }
    public func effectStatic(_ c: RGB) throws { try command(0x03, 0x0A, [0x06, c.r, c.g, c.b]) }
    public func effectSpectrum() throws { try command(0x03, 0x0A, [0x04]) }
    /// direction 1 = left→right, 2 = right→left
    public func effectWave(direction: UInt8) throws { try command(0x03, 0x0A, [0x01, direction]) }
    /// speed 1 (fast) ... 4 (slow)
    public func effectReactive(_ c: RGB, speed: UInt8) throws { try command(0x03, 0x0A, [0x02, speed, c.r, c.g, c.b]) }
    public func effectBreathing(_ colors: [RGB]) throws {
        switch colors.count {
        case 0: try command(0x03, 0x0A, [0x03, 0x03])                                   // random
        case 1: try command(0x03, 0x0A, [0x03, 0x01, colors[0].r, colors[0].g, colors[0].b])
        default:
            let a = colors[0], b = colors[1]
            try command(0x03, 0x0A, [0x03, 0x02, a.r, a.g, a.b, b.r, b.g, b.b])
        }
    }

    // MARK: - Custom per-key frame

    /// Switches the keyboard into "custom frame" mode (show what was last written by `writeFrame`).
    public func effectCustom() throws { try command(0x03, 0x0A, [0x05, 0x01]) }

    /// Writes a full frame of colors. `fast` skips reading responses (for animations).
    public func writeFrame(_ frame: Frame, fast: Bool = false) throws {
        for row in 0..<model.rows {
            var args: [UInt8] = [0xFF, UInt8(row), 0, UInt8(model.cols - 1)]
            for col in 0..<model.cols {
                let c = frame[row, col]
                args += [c.r, c.g, c.b]
            }
            try command(0x03, 0x0B, args, readResponse: !fast)
        }
    }

    /// Writes a frame and makes sure the keyboard displays it.
    public func showFrame(_ frame: Frame, fast: Bool = false) throws {
        try writeFrame(frame, fast: fast)
        try command(0x03, 0x0A, [0x05, 0x01], readResponse: !fast)
    }

    // MARK: - Indicator LEDs (game mode 0x08, macro recording 0x07)
    public static let gameLED: UInt8 = 0x08
    public static let macroLED: UInt8 = 0x07
    public func setLED(_ led: UInt8, on: Bool) throws { try command(0x03, 0x00, [0x01, led, on ? 1 : 0]) }

    // MARK: - Device mode
    /// 0x00 = normal (firmware handles everything), 0x03 = driver mode.
    public func setDeviceMode(_ mode: UInt8) throws { try command(0x00, 0x04, [mode, 0x00]) }
    public func deviceMode() throws -> UInt8 { try command(0x00, 0x84, [0x00, 0x00])[8] }
}

/// A grid of colors matching the keyboard's LED matrix.
public struct Frame {
    public let rows: Int, cols: Int
    public var pixels: [RGB]
    public init(rows: Int = 6, cols: Int = 22, fill: RGB = .black) {
        self.rows = rows; self.cols = cols
        pixels = Array(repeating: fill, count: rows * cols)
    }
    public subscript(r: Int, c: Int) -> RGB {
        get { pixels[r * cols + c] }
        set { if r >= 0, r < rows, c >= 0, c < cols { pixels[r * cols + c] = newValue } }
    }
}
