import AppKit
import CRazerUSB
import IOKit.hid
import Foundation

public struct EngineStatus: Equatable {
    public var connected = false
    public var model: String?
    public var firmware: String?
    /// USB product ID of the connected supported keyboard (for its on-screen layout).
    public var productID: UInt16?
    /// A Razer keyboard is connected but isn't a supported model (its USB name).
    public var unsupported: String?
    public var keyTap = false
    public var notifications = "not started"
    /// M1–M5 + Fn are being read (keyboard in driver mode).
    public var mKeysActive = false
    public var mKeysError: String?
    public var gameMode = false
    /// On-the-fly macro recording (Fn+F9): nil, "recording" or "choosing"
    public var recording: String?
    public init() {}
}

/// Runs inside the app: keeps lighting applied across replug/wake/display sleep, renders
/// software effects and alerts, runs macros, and watches notifications.
public final class Engine {
    public var onStatus: ((EngineStatus) -> Void)?
    /// Fn+F11 / Fn+F12 in driver mode: ask the app to change brightness by this many %.
    public var onBrightnessStep: ((Int) -> Void)?
    /// A macro recorded with Fn+F9 was assigned to a key.
    public var onMacroRecorded: ((String, Macro) -> Void)?
    /// The Num Lock key was pressed (the app flips settings.numLock).
    public var onNumLockPressed: (() -> Void)?

    private var kb: RazerKeyboard?
    private var profile: Profile
    private var settings: Store.Settings
    private let animator: Animator
    private let tap = KeyTap()
    private let macros = MacroRunner()
    private let watcher = NotificationWatcher()
    private let bannerWatcher = AXNotificationWatcher()
    private var lastAlert: (kind: Animator.AlertKind, at: Date)?
    private var callBannerID: String?
    private var lastBannerAt: Date?
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
    // on-the-fly recording (main thread)
    private enum RecState { case idle, recording, choosing }
    private var rec = RecState.idle
    private var recActions: [MacroAction] = []
    private var recGroup: [String] = []
    private var recLast: Date?
    private var recTimeout: DispatchWorkItem?
    private var blinkTimer: DispatchSourceTimer?   // queue
    private let lockLights = LockLights()
    private var mainSettings: Store.Settings
    private var lightTicks = 0
    private var razerSenders = Set<UInt64>()
    private var capsState = false
    private var capsSyncAt = Date.distantPast

    public init(profile: Profile, settings: Store.Settings) {
        self.profile = profile
        self.settings = settings
        animator = Animator(profile: profile)
        mainProfile = profile
        mainSettings = settings
    }

    /// Call once from the main thread.
    public func start() {
        log("engine starting (profile '\(profile.name)')")
        log("permissions: accessibility=\(AXIsProcessTrusted()) inputMonitoring=\(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue) fullDisk=\(NotificationWatcher.checkAccess() ?? "ok") path=\(Bundle.main.bundlePath)")
        queue.async { self.reconnect() }

        tap.onKey = { [weak self] vk, down, rep, flags in self?.handleKey(vk, down: down, isRepeat: rep, flags: flags) ?? false }
        tap.onFlagsChanged = { [weak self] vk, _ in if vk == 0x39 { self?.capsLockPressed() } }
        tap.onRawKey = { [weak self] e, down in self?.rewriteNavigation(e, down: down) ?? false }
        razerSenders = RazerKeyboard.senderIDs()
        log("razer key sources: \(razerSenders.map { String(format: "0x%llx", $0) }.sorted())")
        capsState = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        special.onKey = { [weak self] key, pressed in self?.handleSpecial(key, pressed) }
        startTapIfTrusted()
        rebuildSlots()
        syncDriverMode(settings.driverMode)
        // Lock indicators: follow Caps Lock and the emulated Num Lock (re-asserted every 2 s).
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.updateLockLights() }

        let handler: (NotificationWatcher.Note, String) -> Void = { [weak self] n, source in
            guard let self, self.profile.alerts.watchNotifications else { return }
            guard let kind = NotificationWatcher.classify(n, self.profile.alerts) else { return }
            self.queue.async {
                // Both watchers may see the same notification: ignore repeats for 3 s.
                if source == "banner" { self.lastBannerAt = Date() }
                // The database copy arrives late; skip it if a banner was just handled.
                if source == "database", let b = self.lastBannerAt, Date().timeIntervalSince(b) < 15 { return }
                if kind == .call, let id = n.bannerID { self.callBannerID = id }
                if let l = self.lastAlert, l.kind == kind, Date().timeIntervalSince(l.at) < 3 { return }
                self.lastAlert = (kind, Date())
                log("notification (\(source)) from \(n.app) → \(kind.rawValue)")
                self.animator.trigger(kind)
            }
        }
        watcher.onNotification = { handler($0, "database") }
        bannerWatcher.onNotification = { handler($0, "banner") }
        bannerWatcher.onBannerGone = { [weak self] id in
            self?.queue.async {
                guard let self, id == self.callBannerID else { return }
                self.callBannerID = nil
                log("call banner closed → ending call alert")
                self.animator.endAlert(.call)
            }
        }
        watcher.start()
        bannerWatcher.start()

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
            self.mainSettings = s
            self.updateLockLights(force: true)
            self.rebuildSlots()
            if s.driverMode != oldSettings.driverMode { self.syncDriverMode(s.driverMode) }
        }
        guard kb != nil else { return }
        applyRemaps(force: false)
        applyLighting()
    }

    private func applyRemaps(force: Bool) {
        guard let kb else { return }
        let numpadNav = settings.numLockEmulation && !settings.numLock
        let key = "\(profile.remaps.sorted { $0.key < $1.key })|\(profile.macros.keys.sorted())|\(gameMode)|\(numpadNav)"
        if key == appliedRemapKey && !force { return }
        appliedRemapKey = key
        for w in Remapper.apply(profile, model: kb.model, gameMode: gameMode, numpadNav: numpadNav) { log("remap: \(w)") }
    }

    private func reconnect() {
        kb = nil
        guard let k = try? RazerKeyboard() else {
            status.connected = false; status.model = nil; status.firmware = nil; status.productID = nil
            status.unsupported = RazerKeyboard.unsupportedKeyboardName()
            return
        }
        kb = k
        let fw = try? k.firmwareVersion()
        log("connected: \(k.model.name) \(fw ?? "")")
        status.connected = true; status.model = k.model.name; status.firmware = fw
        status.productID = k.model.productID; status.unsupported = nil
        DispatchQueue.main.async {
            self.razerSenders = RazerKeyboard.senderIDs()
            self.lockLights.reload(); self.updateLockLights(force: true)
        }
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
        else if !present { status.unsupported = RazerKeyboard.unsupportedKeyboardName() }
        else if !present && kb != nil {
            log("keyboard unplugged"); kb = nil
            status.connected = false; status.model = nil; status.firmware = nil; status.productID = nil
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
            // This keyboard only displays a new frame after the "custom effect" command.
            try kb.showFrame(f, fast: true)
            softwareActive = true
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

    private enum FnAction { case media(Int32), brightness(Int), gameMode, sleep, record }

    /// Fn + key, as printed on the BlackWidow Chroma.
    private static let fnLayer: [UInt16: FnAction] = [
        0x7A: .media(MediaKeys.mute),      // F1
        0x78: .media(MediaKeys.soundDown), // F2
        0x63: .media(MediaKeys.soundUp),   // F3
        0x60: .media(MediaKeys.previous),  // F5
        0x61: .media(MediaKeys.play),      // F6
        0x62: .media(MediaKeys.next),      // F7
        0x65: .record,                     // F9  on-the-fly macro recording
        0x6D: .gameMode,                   // F10
        0x67: .brightness(-10),            // F11
        0x6F: .brightness(10),             // F12
        0x71: .sleep,                      // Pause
    ]

    private func handleKey(_ vk: UInt16, down: Bool, isRepeat: Bool, flags: CGEventFlags) -> Bool {
        // Fn layer (driver mode only: otherwise the keyboard does this itself)
        if mainDriverActive {
            if down, fnHeld, let action = Self.fnLayer[vk] {
                swallowed.insert(vk)
                switch action {
                case .media(let k): if !isRepeat || k == MediaKeys.soundUp || k == MediaKeys.soundDown { MediaKeys.press(k) }
                case .brightness(let d): onBrightnessStep?(d)
                case .gameMode: if !isRepeat { setGameMode(!status.gameMode) }
                case .sleep: if !isRepeat { _ = Remapper.run("/usr/bin/pmset", ["sleepnow"]) }
                case .record: if !isRepeat { toggleRecording() }
                }
                return true
            }
        }
        if swallowed.contains(vk) {
            if !down { swallowed.remove(vk) }
            return true
        }
        // Num Lock (macOS calls it "Clear", vk 0x47): toggle numbers / navigation.
        if vk == 0x47, mainSettings.numLockEmulation, down {
            if !isRepeat { onNumLockPressed?() }
            swallowed.insert(vk)
            return true
        }
        // Fn+F9 finished: the next key press receives the recorded macro (Esc cancels).
        if rec == .choosing, down, !isRepeat, let k = KeyLayout.key(vk: vk) {
            swallowed.insert(vk)
            if k.name == "esc" { finishRecording(assignTo: nil) } else { finishRecording(assignTo: k.name) }
            return true
        }
        if rec == .recording, down, !isRepeat { recordKey(vk, flags) }
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
            if rec == .choosing { finishRecording(assignTo: name); return }
            if rec == .recording { return }
            animator.keyPressed(KeyLayout.key(name))
            if let m = mainProfile.macros[name] { macros.run(m, name: name) }
            else if let target = mainProfile.remaps[name] { macros.tapCombo(target) }
        case .other(let c):
            if pressed { log(String(format: "unknown special key 0x%02X", c)) }
        }
    }

    // MARK: on-the-fly macro recording (main thread)

    private func toggleRecording() {
        switch rec {
        case .idle: startRecording()
        case .recording: stopRecording()
        case .choosing: finishRecording(assignTo: nil)
        }
    }

    private func startRecording() {
        rec = .recording
        recActions = []; recGroup = []; recLast = nil
        setRecordingStatus("recording")
        queue.async { try? self.kb?.setLED(RazerKeyboard.macroLED, on: true) }
        log("macro recording started")
        scheduleRecordingTimeout(120)
    }

    private func recordKey(_ vk: UInt16, _ flags: CGEventFlags) {
        guard let k = KeyLayout.key(vk: vk) else { return }
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("cmd") }
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskAlternate) { parts.append("alt") }
        if flags.contains(.maskShift) { parts.append("shift") }
        parts.append(k.name)
        let now = Date()
        if let last = recLast {
            let gap = now.timeIntervalSince(last)
            if gap > 0.3 {
                flushGroup()
                recActions.append(MacroAction(type: .delay, value: "\(min(5000, Int((gap * 100).rounded()) * 10))"))
            }
        }
        recGroup.append(parts.joined(separator: "+"))
        recLast = now
    }

    private func flushGroup() {
        guard !recGroup.isEmpty else { return }
        recActions.append(MacroAction(type: .keys, value: recGroup.joined(separator: " ")))
        recGroup = []
    }

    private func stopRecording() {
        flushGroup()
        guard !recActions.isEmpty else { finishRecording(assignTo: nil); return }
        rec = .choosing
        setRecordingStatus("choosing")
        log("macro recorded (\(recActions.count) steps); waiting for a key")
        queue.async { self.startBlink() }
        scheduleRecordingTimeout(20)
    }

    private func finishRecording(assignTo key: String?) {
        if let key, !recActions.isEmpty {
            let macro = Macro(actions: recActions)
            log("recorded macro saved to \(key)")
            onMacroRecorded?(key, macro)
        } else {
            log("macro recording cancelled")
        }
        rec = .idle
        recActions = []; recGroup = []; recLast = nil
        recTimeout?.cancel(); recTimeout = nil
        setRecordingStatus(nil)
        queue.async {
            self.blinkTimer?.cancel(); self.blinkTimer = nil
            try? self.kb?.setLED(RazerKeyboard.macroLED, on: false)
        }
    }

    private func scheduleRecordingTimeout(_ seconds: Double) {
        recTimeout?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.finishRecording(assignTo: nil) }
        recTimeout = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func setRecordingStatus(_ s: String?) { queue.async { self.status.recording = s } }

    /// Blink the M indicator while waiting for a key (on queue).
    private func startBlink() {
        blinkTimer?.cancel()
        var on = true
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 0.35)
        t.setEventHandler { [weak self] in
            on.toggle()
            try? self?.kb?.setLED(RazerKeyboard.macroLED, on: on)
        }
        t.resume()
        blinkTimer = t
    }

    /// Start/stop recording from the app (works without Fn+F9).
    public func toggleRecordingFromApp() { DispatchQueue.main.async { self.toggleRecording() } }

    // MARK: lock indicators (main thread)

    private func updateLockLights(force: Bool = false) {
        guard mainDriverActive || RazerInputListener.hasPermission else { return }
        lightTicks += 1
        let refresh = force || lightTicks % 13 == 0
        let caps = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        reconcileCapsLock(caps)
        lockLights.set(LockLights.caps, caps, force: refresh)
        lockLights.set(LockLights.num, mainSettings.numLockEmulation ? mainSettings.numLock : false, force: refresh)
        lockLights.set(LockLights.scroll, false, force: refresh)
    }

    // MARK: shared Caps Lock (main thread)
    // macOS keeps a separate Caps Lock per keyboard and shows caps if *any* is on, so pressing
    // Caps Lock on the other keyboard can appear to do nothing. Each press flips one shared
    // state, which is then applied to every keyboard.

    private func capsLockPressed() {
        guard mainSettings.shareCapsLock else { return }
        // Our own sync can echo back as a Caps Lock event: ignore those.
        guard Date().timeIntervalSince(capsSyncAt) > 0.3 else { return }
        capsState.toggle()
        capsSyncAt = Date()
        let want = capsState
        // Let the keyboard finish its own toggle first, then make all keyboards agree.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            _ = razer_set_caps_lock(want ? 1 : 0)
            self.updateLockLights(force: true)
        }
    }

    /// Adopt Caps Lock changes made some other way (e.g. another app), once things settle.
    private func reconcileCapsLock(_ actual: Bool) {
        guard mainSettings.shareCapsLock, actual != capsState, Date().timeIntervalSince(capsSyncAt) > 1 else { return }
        capsState = actual
    }

    // MARK: Windows-style navigation keys on the Razer (main thread)

    private static let senderField = CGEventField(rawValue: 87)!   // registry ID of the sending keyboard

    private var navRewrites: [UInt16: (UInt16, CGEventFlags)] = [:]   // decided at key down

    /// In text fields: Home/End → start/end of line (Ctrl: of document); Page Up/Down → move the
    /// cursor. Elsewhere (web pages, documents) the keys pass through and scroll, like on Windows.
    /// Only for the Razer: the MacBook's fn+arrows produce the same keys and keep Mac behavior.
    private func rewriteNavigation(_ e: CGEvent, down: Bool) -> Bool {
        let vk = UInt16(e.getIntegerValueField(.keyboardEventKeycode))
        guard [0x73, 0x77, 0x74, 0x79].contains(vk) else { return false }
        let mapping: (UInt16, CGEventFlags)
        if down {
            guard mainSettings.windowsNavigation,
                  razerSenders.contains(UInt64(bitPattern: e.getIntegerValueField(Self.senderField))),
                  e.getIntegerValueField(.keyboardEventAutorepeat) != 0 ? navRewrites[vk] != nil : Self.textFieldHasFocus()
            else { navRewrites[vk] = nil; return false }
            let flags = e.flags
            let ctrl = flags.contains(.maskControl)
            var out: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]
            if flags.contains(.maskShift) { out.insert(.maskShift) }
            let newVK: UInt16
            switch vk {
            case 0x73: newVK = ctrl ? 0x7E : 0x7B; out.insert(.maskCommand)   // Home → ⌘← (Ctrl: ⌘↑)
            case 0x77: newVK = ctrl ? 0x7D : 0x7C; out.insert(.maskCommand)   // End  → ⌘→ (Ctrl: ⌘↓)
            case 0x74: newVK = 0x74; out.insert(.maskAlternate)               // Page Up   → ⌥Page Up (moves the cursor)
            default:   newVK = 0x79; out.insert(.maskAlternate)               // Page Down → ⌥Page Down
            }
            mapping = (newVK, out)
            navRewrites[vk] = mapping
        } else {
            guard let m = navRewrites.removeValue(forKey: vk) else { return false }
            mapping = m
        }
        guard let ne = CGEvent(keyboardEventSource: nil, virtualKey: mapping.0, keyDown: down) else { return false }
        ne.flags = mapping.1
        ne.setIntegerValueField(.keyboardEventAutorepeat, value: e.getIntegerValueField(.keyboardEventAutorepeat))
        ne.setIntegerValueField(.eventSourceUserData, value: MacroRunner.marker)
        ne.post(tap: .cgSessionEventTap)
        return true
    }

    /// True if the focused UI element is something you type into.
    static func textFieldHasFocus() -> Bool {
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.15)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() else { return false }
        let el = f as! AXUIElement
        AXUIElementSetMessagingTimeout(el, 0.15)
        var role: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        if let r = role as? String, ["AXTextArea", "AXTextField", "AXComboBox"].contains(r) { return true }
        // Editable web content (contenteditable) reports an editable ancestor.
        var editable: AnyObject?
        return AXUIElementCopyAttributeValue(el, "AXEditableAncestor" as CFString, &editable) == .success && editable != nil
    }
}
