import AppKit
import Foundation

public struct EngineStatus: Equatable {
    public var connected = false
    public var model: String?
    public var firmware: String?
    public var keyTap = false
    public var notifications = "not started"
    public init() {}
}

/// Runs inside the app: keeps lighting applied across replug/wake/display sleep, renders
/// software effects and alerts, runs macros, and watches notifications.
public final class Engine {
    public var onStatus: ((EngineStatus) -> Void)?

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

    public init(profile: Profile, settings: Store.Settings) {
        self.profile = profile
        self.settings = settings
        animator = Animator(profile: profile)
        Remapper.mKeyUsages = settings.mKeyUsages
    }

    /// Call once from the main thread.
    public func start() {
        log("engine starting (profile '\(profile.name)')")
        queue.async { self.reconnect() }

        tap.onKeyDown = { [weak self] vk in self?.handleKey(vk) ?? false }
        startTapIfTrusted()
        rebuildSlots()

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

    /// Temporarily stop rendering (used while the key tester owns the keyboard).
    public func setDriverModeNow(_ on: Bool) {
        queue.async { try? self.kb?.setDeviceMode(on ? 0x03 : 0x00) }
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
        Remapper.mKeyUsages = s.mKeyUsages
        animator.setProfile(p)
        DispatchQueue.main.async { self.rebuildSlots() }
        guard let kb else { return }
        if s.driverMode != oldSettings.driverMode { try? kb.setDeviceMode(s.driverMode ? 0x03 : 0x00) }
        applyRemaps(force: s.mKeyUsages != oldSettings.mKeyUsages)
        applyLighting()
    }

    private func applyRemaps(force: Bool) {
        guard let kb else { return }
        let key = "\(profile.remaps.sorted { $0.key < $1.key })|\(profile.macros.keys.sorted())|\(settings.mKeyUsages.sorted { $0.key < $1.key })"
        if key == appliedRemapKey && !force { return }
        appliedRemapKey = key
        for w in Remapper.apply(profile, model: kb.model) { log("remap: \(w)") }
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
        if settings.driverMode { try? k.setDeviceMode(0x03) }
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
        for (name, slot) in Remapper.slotAssignments(profile) { slotToMacro[slot.vk] = name }
        tap.swallowUp = Set(slotToMacro.keys)
    }

    private func handleKey(_ vk: UInt16) -> Bool {
        if let name = slotToMacro[vk], let m = profile.macros[name] {
            macros.run(m, name: name)
            return true
        }
        animator.keyPressed(KeyLayout.key(vk: vk))
        return false
    }
}
