import AppKit
import Foundation

/// The background service: keeps lighting applied across replug/wake, renders software
/// effects and alerts, runs macros, and watches notifications.
public final class Service {
    private let store = Store.shared
    private var kb: RazerKeyboard?
    private var profile: Profile
    private let animator: Animator
    private let tap = KeyTap()
    private let macros = MacroRunner()
    private let watcher = NotificationWatcher()
    private let frameQueue = DispatchQueue(label: "chroma.frames")
    private var softwareActive = false
    private var lastFrame: [RGB] = []
    private var displayAsleep = false
    private var slotToMacro: [UInt16: String] = [:]
    private var tapOK = false

    public init() throws {
        profile = try store.activeProfile()
        animator = Animator(profile: profile)
    }

    public func run() -> Never {
        log("service starting (profile '\(profile.name)')")
        connect()

        // Keyboard events → macros + reactive lighting
        tapOK = KeyTap.isTrusted(prompt: true) && tap.start()
        if !tapOK { log("key tap unavailable: grant Accessibility to \(CommandLine.arguments[0]) (macros & typing effects disabled)") }
        tap.onKeyDown = { [weak self] vk in self?.handleKey(vk) ?? false }
        rebuildSlots()

        // Notifications
        watcher.onNotification = { [weak self] n in
            guard let self else { return }
            guard self.profile.alerts.watchNotifications else { return }
            if n.app.lowercased().hasPrefix("com.apple.screencapture") { return }
            if let kind = NotificationWatcher.classify(n, self.profile.alerts) {
                log("notification from \(n.app) → \(kind.rawValue)")
                self.animator.trigger(kind)
            }
        }
        watcher.start()

        // IPC
        do { try IPC.serve { [weak self] req in self?.handle(req) ?? ["ok": "false"] } }
        catch { log("IPC unavailable: \(error)") }

        // Wake / display sleep
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            log("system woke"); self?.frameQueue.asyncAfter(deadline: .now() + 2) { self?.reconnect() }
        }
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: nil) { [weak self] _ in
            self?.frameQueue.async {
                guard let self, self.store.settings().lightsOffWhenDisplaySleeps else { return }
                self.displayAsleep = true
                try? self.kb?.effectNone(); self.softwareActive = false
            }
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.frameQueue.async { guard let self else { return }; self.displayAsleep = false; self.applyLighting() }
        }

        // Frame loop (30 fps) + hotplug check (every ~2 s)
        let timer = DispatchSource.makeTimerSource(queue: frameQueue)
        var tick = 0
        timer.schedule(deadline: .now() + 0.1, repeating: 1.0 / 30)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            tick += 1
            if tick % 60 == 0 { self.checkConnection() }
            self.renderTick()
        }
        timer.resume()

        signal(SIGTERM) { _ in exit(0) }
        RunLoop.main.run()
        exit(0)
    }

    // MARK: device

    private func connect() {
        frameQueue.async { self.reconnect() }
    }

    private func reconnect() {
        kb = nil
        guard let k = try? RazerKeyboard() else { log("keyboard not connected; waiting"); return }
        kb = k
        log("connected: \(k.model.name) \((try? k.firmwareVersion()) ?? "")")
        if store.settings().driverMode { try? k.setDeviceMode(0x03) }
        for w in Remapper.apply(profile, model: k.model) { log("remap: \(w)") }
        softwareActive = false
        applyLighting()
    }

    private func checkConnection() {
        let present = RazerKeyboard.isConnected()
        if present && kb == nil { log("keyboard plugged in"); usleep(500_000); reconnect() }
        else if !present && kb != nil { log("keyboard unplugged"); kb = nil }
    }

    /// Must run on frameQueue.
    private func applyLighting() {
        guard let kb, !displayAsleep else { return }
        animator.setProfile(profile)
        do {
            if animator.needsFrames {
                try kb.setBrightness(UInt8(max(0, min(100, profile.brightness)) * 255 / 100))
                softwareActive = false // force custom-mode switch on next frame
                lastFrame = []
            } else {
                try Lighting.applyHardware(profile, to: kb)
                softwareActive = false
            }
        } catch { log("apply failed: \(error)"); self.kb = nil }
    }

    private func renderTick() {
        guard let kb, !displayAsleep else { return }
        let wanted = animator.needsFrames
        if !wanted {
            if softwareActive { softwareActive = false; applyLighting() } // alert ended → restore hardware effect
            return
        }
        let f = animator.render()
        if f.pixels == lastFrame && softwareActive { return }
        do {
            try kb.writeFrame(f, fast: true)
            if !softwareActive { try kb.effectCustom(); softwareActive = true }
            lastFrame = f.pixels
        } catch {
            log("frame write failed: \(error)"); self.kb = nil
        }
    }

    // MARK: keys

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

    // MARK: IPC

    private func handle(_ req: [String: String]) -> [String: String] {
        switch req["cmd"] ?? "" {
        case "reload":
            return frameQueue.sync {
                do {
                    profile = try store.activeProfile()
                    animator.setProfile(profile)
                    DispatchQueue.main.async { self.rebuildSlots() }
                    var warnings: [String] = []
                    if let kb {
                        warnings = Remapper.apply(profile, model: kb.model)
                        let dm = store.settings().driverMode
                        try? kb.setDeviceMode(dm ? 0x03 : 0x00)
                    }
                    applyLighting()
                    log("reloaded profile '\(profile.name)'")
                    return ["ok": "true", "warnings": warnings.joined(separator: "\n")]
                } catch { return ["ok": "false", "error": "\(error)"] }
            }
        case "alert":
            let kind = Animator.AlertKind(rawValue: req["kind"] ?? "notify") ?? .notify
            animator.trigger(kind)
            return ["ok": "true"]
        case "clear":
            animator.clearAlerts()
            return ["ok": "true"]
        case "status":
            return ["ok": "true", "profile": profile.name, "keyboard": kb?.model.name ?? "not connected",
                    "keytap": tapOK ? "ok" : "no Accessibility permission", "notifications": watcher.status,
                    "pid": "\(getpid())"]
        default:
            return ["ok": "false", "error": "unknown command"]
        }
    }
}

/// Manages the launchd agent that starts the service at login.
public enum LaunchAgent {
    public static let label = "local.chroma-cli.service"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    public static func install(binary: String) throws {
        let log = Store.shared.logURL.path
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binary, "service", "run"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 5,
            "ProcessType": "Interactive",
            "StandardOutPath": log,
            "StandardErrorPath": log,
        ]
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        _ = Remapper.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        try data.write(to: plistURL, options: .atomic)
        let (s, out) = Remapper.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
        if s != 0 { throw ChromaError.io("launchctl bootstrap failed: \(out)") }
    }

    public static func uninstall() {
        _ = Remapper.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    public static func restart() -> Bool {
        Remapper.run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(label)"]).0 == 0
    }

    public static func stop() {
        _ = Remapper.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
    }

    public static func start() -> Bool {
        Remapper.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path]).0 == 0
    }
}
