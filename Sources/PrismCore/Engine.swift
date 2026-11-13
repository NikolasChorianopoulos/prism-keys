import AppKit
import IOKit.hid
import Foundation

public struct EngineStatus: Equatable {
    public var connected = false
    public var model: String?
    public var firmware: String?
    public var keyTap = false
    public var notifications = "not started"
    /// M1–M5 + Fn are being read (keyboard in driver mode).
    public var mKeysActive = false
    public var mKeysError: String?
    public var gameMode = false
    public init() {}
}

/// Runs inside the app: keeps lighting applied across replug/wake/display sleep, renders
/// software effects and alerts, runs macros, and watches notifications.
public final class Engine {
    public var onStatus: ((EngineStatus) -> Void)?
    /// Fn+F11 / Fn+F12 in driver mode: ask the app to change brightness by this many %.
    public var onBrightnessStep: ((Int) -> Void)?

    private var kb: RazerKeyboard?
    private var profile: Profile
    private var settings: Store.Settings
    private let animator: Animator
    private let tap = KeyTap()
    private let macros = MacroRunner()
    private let watcher = NotificationWatcher()
    private let queue = DispatchQueue(label: "prismkeys.engine")
    private var softwareActive = false
    private var lastFrame: [RGB] = []
    private var displayAsleep = false
    private var slotToMacro: [UInt16: String] = [:]
    private var appliedRemapKey = ""
    private var pending: (Profile, Store.Settings)?
    private var status = EngineStatus() { didSet { if status != oldValue { let s = status; DispatchQueue.main.async { self.onStatus?(s) } } } }
    private var timer: DispatchSourceTimer?
    private var holdUntil: Date?
    private var gameMode = false
    private var driverActive = false              // queue
    // main-thread state for key handling
    private let special = RazerInputListener()
    private var mainProfile: Profile
    private var mainDriverActive = false
    private var fnHeld = false
    private var swallowed = Set<UInt16>()

    public init(profile: Profile, settings: Store.Settings) {
        self.profile = profile
        self.settings = settings
        animator = Animator(profile: profile)
        mainProfile = profile
    }

    /// Call once from the main thread.
    public func start() {
        log("engine starting (profile '\(profile.name)')")
        log("permissions: accessibility=\(AXIsProcessTrusted()) inputMonitoring=\(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue) fullDisk=\(NotificationWatcher.checkAccess() ?? "ok") path=\(Bundle.main.bundlePath)")
        queue.async { self.reconnect() }

        tap.onKey = { [weak self] vk, down, rep in self?.handleKey(vk, down: down, isRepeat: rep) ?? false }
        special.onKey = { [weak self] key, pressed in self?.handleSpecial(key, pressed) }
        startTapIfTrusted()
        rebuildSlots()
        syncDriverMode(settings.driverMode)

        watcher.onNotification = { [weak self] n in
            guard let self else { return }
            guard self.profile.alerts.watchNotifications else { return }
            if let kind = NotificationWatcher.classify(n, self.profile.alerts) {
                log("notification from \(n.app) → \(kind.rawValue)")
                self.animator.trigger(kind)
            }
        }
        watcher.start()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            log("system woke"); self?.queue.asyncAfter(deadline: .now() + 2) { self?.reconnect() }
        }
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async {
                guard let self, self.settings.lightsOffWhenDisplaySleeps else { return }
                self.displayAsleep = true
                try? self.kb?.effectNone(); self.softwareActive = false
            }
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { guard let self else { return }; self.displayAsleep = false; self.applyLighting() }
        }

        // 30 fps frame loop; hotplug + permission checks every ~2 s.
        let t = DispatchSource.makeTimerSource(queue: queue)
        var tick = 0
        t.schedule(deadline: .now() + 0.1, repeating: 1.0 / 30)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            tick += 1
            if tick % 60 == 0 {
                self.checkConnection()
                self.status.notifications = self.watcher.status
                if !self.status.keyTap { DispatchQueue.main.async { self.startTapIfTrusted() } }
            }
            self.renderTick()
        }
        t.resume()
        timer = t
    }

    /// Push new settings/profile (coalesced; safe to call rapidly, e.g. from sliders).
    public func update(profile: Profile, settings: Store.Settings) {
        queue.async {
            let first = self.pending == nil
            self.pending = (profile, settings)
            guard first else { return }
            self.queue.asyncAfter(deadline: .now() + 0.03) {
                guard let (p, s) = self.pending else { return }
                self.pending = nil
                self.apply(p, s)
            }
        }
    }

    public func trigger(_ kind: Animator.AlertKind) { animator.trigger(kind) }
    public func clearAlerts() { animator.clearAlerts() }

    /// Call when the app quits: give the keyboard back its own Fn keys and plain remaps.
    public func shutdown() {
        special.stop()
        queue.sync {
            guard let kb else { return }
            if gameMode { try? kb.setLED(RazerKeyboard.gameLED, on: false) }
            try? kb.setDeviceMode(0x00)
            _ = Remapper.apply(profile, model: kb.model, includeMacros: false)
        }
    }

    public func setGameMode(_ on: Bool) {
        queue.async {
            self.gameMode = on
            self.status.gameMode = on
            log("gaming mode \(on ? "on" : "off")")
            try? self.kb?.setLED(RazerKeyboard.gameLED, on: on)
            self.applyRemaps(force: true)
        }
    }

    /// Shows a fixed frame (test pattern) for a while, pausing the normal lighting.
    public func show(_ f: Frame, for seconds: Double) {
        queue.async {
            guard let kb = self.kb else { return }
            try? kb.showFrame(f)
            self.holdUntil = Date().addingTimeInterval(seconds)
            self.softwareActive = true
            self.lastFrame = f.pixels
        }
    }

    /// Runs a hardware command (e.g. a built-in effect) and holds it, pausing the normal lighting.
    public func hold(for seconds: Double, _ body: @escaping (RazerKeyboard) throws -> Void) {
        queue.async {
            guard let kb = self.kb else { return }
            try? body(kb)
            self.holdUntil = Date().addingTimeInterval(seconds)
            self.softwareActive = false
            self.lastFrame = []
        }
    }

    /// Ends a test pattern early and restores the profile's lighting.
    public func endHold() {
        queue.async {
            guard self.holdUntil != nil else { return }
            self.holdUntil = nil; self.softwareActive = false; self.applyLighting()
        }
    }

    /// Lights specific keys for a moment so you can check the layout.
    public func identify(_ keys: [Key], seconds: Double = 2.5) {
        var f = Frame(fill: RGB(0, 0, 30))
        for k in keys { f[k.row, k.col] = .white }
        show(f, for: seconds)
    }

    // MARK: internals (on queue)

    private func apply(_ p: Profile, _ s: Store.Settings) {
        let oldSettings = settings
        profile = p
        settings = s
        animator.setProfile(p)
        DispatchQueue.main.async {
            self.mainProfile = p
            self.rebuildSlots()
            if s.driverMode != oldSettings.driverMode { self.syncDriverMode(s.driverMode) }
        }
        guard kb != nil else { return }
        applyRemaps(force: false)
        applyLighting()
    }

    private func applyRemaps(force: Bool) {
        guard let kb else { return }
        let key = "\(profile.remaps.sorted { $0.key < $1.key })|\(profile.macros.keys.sorted())|\(gameMode)"
        if key == appliedRemapKey && !force { return }
        appliedRemapKey = key
        for w in Remapper.apply(profile, model: kb.model, gameMode: gameMode) { log("remap: \(w)") }
    }

    private func reconnect() {
        kb = nil
        guard let k = try? RazerKeyboard() else {
            status.connected = false; status.model = nil; status.firmware = nil
            return
        }
        kb = k
        let fw = try? k.firmwareVersion()
        log("connected: \(k.model.name) \(fw ?? "")")
        status.connected = true; status.model = k.model.name; status.firmware = fw
        try? k.setDeviceMode(driverActive ? 0x03 : 0x00)
        if driverActive { try? k.setLED(RazerKeyboard.gameLED, on: gameMode) }
        appliedRemapKey = ""
        applyRemaps(force: true)
        softwareActive = false
        applyLighting()
    }

    private func checkConnection() {
        let present = RazerKeyboard.isConnected()
        if present && kb == nil { usleep(400_000); reconnect() }
        else if !present && kb != nil {
            log("keyboard unplugged"); kb = nil
            status.connected = false; status.model = nil; status.firmware = nil
        }
    }

    private func applyLighting() {
        guard let kb, !displayAsleep else { return }
        animator.setProfile(profile)
        do {
            if animator.needsFrames {
                try kb.setBrightness(Lighting.level(profile.brightness, cap: settings.maxBrightness))
                softwareActive = false
                lastFrame = []
            } else {
                try Lighting.applyHardware(profile, to: kb, maxBrightness: settings.maxBrightness)
                softwareActive = false
            }
        } catch { log("apply failed: \(error)"); self.kb = nil; status.connected = false }
    }

    private func renderTick() {
        guard let kb, !displayAsleep else { return }
        if let h = holdUntil {
            if Date() < h { return }
            holdUntil = nil; softwareActive = false; applyLighting(); return
        }
        if !animator.needsFrames {
            if softwareActive { softwareActive = false; applyLighting() }
            return
        }
        let f = animator.render()
        if f.pixels == lastFrame && softwareActive { return }
        do {
            try kb.writeFrame(f, fast: true)
            if !softwareActive { try kb.effectCustom(); softwareActive = true }
            lastFrame = f.pixels
        } catch {
            log("frame write failed: \(error)"); self.kb = nil; status.connected = false
        }
    }

    // MARK: keys (main thread)

    private func startTapIfTrusted() {
        guard !status.keyTap, KeyTap.isTrusted(prompt: false) else { return }
        if tap.start() {
            queue.async { self.status.keyTap = true }
            log("key tap active")
        }
    }

    private func rebuildSlots() {
        slotToMacro = [:]
        for (name, slot) in Remapper.slotAssignments(mainProfile) { slotToMacro[slot.vk] = name }
    }

    /// Driver mode is only switched on once we can actually read Fn/M-keys; otherwise the
    /// keyboard would lose its Fn shortcuts.
    private func syncDriverMode(_ wanted: Bool) {
        var failure: String?
        if wanted && !special.isRunning {
            do { try special.start() } catch { failure = "\(error)" }
        } else if !wanted && special.isRunning {
            special.stop()
        }
        let active = wanted && special.isRunning
        mainDriverActive = active
        fnHeld = false
        queue.async {
            self.driverActive = active
            self.status.mKeysActive = active
            self.status.mKeysError = failure
            if !active && self.gameMode {
                self.gameMode = false; self.status.gameMode = false
                try? self.kb?.setLED(RazerKeyboard.gameLED, on: false)
                self.applyRemaps(force: true)
            }
            try? self.kb?.setDeviceMode(active ? 0x03 : 0x00)
            log("M-keys \(active ? "enabled (driver mode)" : "disabled")\(failure.map { " — \($0)" } ?? "")")
        }
    }

    private enum FnAction { case media(Int32), brightness(Int), gameMode, sleep, none }

    /// Fn + key, as printed on the BlackWidow Chroma.
    private static let fnLayer: [UInt16: FnAction] = [
        0x7A: .media(MediaKeys.mute),      // F1
        0x78: .media(MediaKeys.soundDown), // F2
        0x63: .media(MediaKeys.soundUp),   // F3
        0x60: .media(MediaKeys.previous),  // F5
        0x61: .media(MediaKeys.play),      // F6
        0x62: .media(MediaKeys.next),      // F7
        0x65: .none,                       // F9  (on-the-fly macro recording: not supported)
        0x6D: .gameMode,                   // F10
        0x67: .brightness(-10),            // F11
        0x6F: .brightness(10),             // F12
        0x71: .sleep,                      // Pause
    ]

    private func handleKey(_ vk: UInt16, down: Bool, isRepeat: Bool) -> Bool {
        // Fn layer (driver mode only: otherwise the keyboard does this itself)
        if mainDriverActive {
            if down, fnHeld, let action = Self.fnLayer[vk] {
                swallowed.insert(vk)
                switch action {
                case .media(let k): if !isRepeat || k == MediaKeys.soundUp || k == MediaKeys.soundDown { MediaKeys.press(k) }
                case .brightness(let d): onBrightnessStep?(d)
                case .gameMode: if !isRepeat { setGameMode(!status.gameMode) }
                case .sleep: if !isRepeat { _ = Remapper.run("/usr/bin/pmset", ["sleepnow"]) }
                case .none: break
                }
                return true
            }
            if swallowed.contains(vk) {
                if !down { swallowed.remove(vk) }
                return true
            }
        }
        // Macro slot keys
        if let name = slotToMacro[vk] {
            if down && !isRepeat, let m = mainProfile.macros[name] { macros.run(m, name: name) }
            return true
        }
        if down && !isRepeat { animator.keyPressed(KeyLayout.key(vk: vk)) }
        return false
    }

    private func handleSpecial(_ key: RazerInputListener.SpecialKey, _ pressed: Bool) {
        switch key {
        case .fn:
            fnHeld = pressed
        case .macro(let n):
            guard pressed else { return }
            let name = "m\(n)"
            animator.keyPressed(KeyLayout.key(name))
            if let m = mainProfile.macros[name] { macros.run(m, name: name) }
            else if let target = mainProfile.remaps[name] { macros.tapCombo(target) }
        case .other(let c):
            if pressed { log(String(format: "unknown special key 0x%02X", c)) }
        }
    }
}
