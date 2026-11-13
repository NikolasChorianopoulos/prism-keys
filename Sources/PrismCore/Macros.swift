import AppKit
import ApplicationServices
import Foundation

/// Runs macro actions by synthesizing keyboard events / launching things.
public final class MacroRunner {
    public static let marker: Int64 = 0x50_52_53_4D // "PRSM": tags our own synthetic events
    private let queue = DispatchQueue(label: "prismkeys.macros")
    private let source = CGEventSource(stateID: .hidSystemState)

    public init() {}

    public func run(_ m: Macro, name: String) {
        queue.async { [self] in
            log("macro \(name): \(m.actions.map(\.description).joined(separator: " "))")
            for a in m.actions {
                switch a.type {
                case .text: typeText(a.value)
                case .keys: for combo in a.value.split(separator: " ") { pressCombo(String(combo)) }
                case .delay: usleep(UInt32(max(0, min(60_000, Int(a.value) ?? 100))) * 1000)
                case .app: openApp(a.value)
                case .url: if let u = URL(string: a.value) { NSWorkspace.shared.open(u) }
                case .shell: _ = shell(a.value)
                }
                usleep(15_000)
            }
        }
    }

    private func post(_ e: CGEvent?) {
        guard let e else { return }
        e.setIntegerValueField(.eventSourceUserData, value: MacroRunner.marker)
        e.post(tap: .cghidEventTap)
    }

    func typeText(_ s: String) {
        let utf16 = Array(s.utf16)
        var i = 0
        while i < utf16.count {
            let chunk = Array(utf16[i..<min(i + 16, utf16.count)])
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                e?.flags = []
                chunk.withUnsafeBufferPointer { e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
                post(e)
            }
            usleep(8000)
            i += 16
        }
    }

    /// "cmd+shift+4", "ctrl+left", "f5", "enter"
    public static func parseCombo(_ combo: String) -> (vk: UInt16, flags: CGEventFlags)? {
        var flags: CGEventFlags = []
        var vk: UInt16?
        for part in combo.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command", "win", "super": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "opt", "option": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default:
                if let k = KeyLayout.key(part), let v = k.vk { vk = v }
                else if let x = KeyLayout.extraTargets[part], x.vk != 0xFFFF { vk = x.vk }
                else { return nil }
            }
        }
        guard let v = vk else { return nil }
        return (v, flags)
    }

    public func tapCombo(_ combo: String) { queue.async { self.pressCombo(combo) } }

    func pressCombo(_ combo: String) {
        guard let (vk, flags) = MacroRunner.parseCombo(combo) else { log("macro: can't parse '\(combo)'"); return }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: down)
            e?.flags = flags
            post(e)
            usleep(6000)
        }
    }

    func openApp(_ name: String) {
        let isBundle = name.contains(".") && !name.contains(" ") && !name.hasSuffix(".app")
        _ = Remapper.run("/usr/bin/open", isBundle ? ["-b", name] : ["-a", name])
    }

    func shell(_ cmd: String) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", cmd]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        return 0
    }
}

/// Global keyboard event tap: runs macros for slot keys and feeds keypresses to the animator.
/// Requires the Accessibility permission.
public final class KeyTap {
    /// (keycode, isDown, isRepeat) -> swallow the event?
    /// (keycode, isDown, isRepeat, modifier flags) -> swallow the event?
    public var onKey: ((UInt16, Bool, Bool, CGEventFlags) -> Bool)?
    /// Modifier/lock key changes (e.g. Caps Lock pressed on any keyboard).
    public var onFlagsChanged: ((UInt16, CGEventFlags) -> Void)?
    fileprivate var tap: CFMachPort?

    public init() {}

    public static func isTrusted(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    public func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: keyTapCallback, userInfo: refcon) else {
            return false
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}

private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let me = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if event.getIntegerValueField(.eventSourceUserData) == MacroRunner.marker { return Unmanaged.passUnretained(event) }
    let vk = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    if type == .flagsChanged {
        me.onFlagsChanged?(vk, event.flags)
        return Unmanaged.passUnretained(event)
    }
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    if me.onKey?(vk, type == .keyDown, isRepeat, event.flags) == true { return nil }
    return Unmanaged.passUnretained(event)
}

private let logLock = NSLock()
public func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "[\(f.string(from: Date()))] \(s)\n"
    print(line, terminator: "")
    logLock.lock(); defer { logLock.unlock() }
    let url = Store.shared.logURL
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.data(using: .utf8)!.write(to: url)
    }
}
