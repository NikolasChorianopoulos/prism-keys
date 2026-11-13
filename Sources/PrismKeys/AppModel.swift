import AppKit
import Combine
import PrismCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let store = Store.shared
    let engine: Engine

    @Published var profile: Profile
    @Published var settings: Store.Settings
    @Published private(set) var profileNames: [String] = []
    @Published var status = EngineStatus()
    @Published var errorMessage: String?

    /// Remembered so the power toggle can bring the lights back.
    private var lastOnEffect: Effect?
    private var bag = Set<AnyCancellable>()
    private var saveWork: DispatchWorkItem?

    private init() {
        let s = store.settings()
        let p = (try? store.load(s.activeProfile)) ?? Profile(name: "default")
        settings = s
        profile = p
        engine = Engine(profile: p, settings: s)
        profileNames = store.profileNames()
        if profileNames.isEmpty { try? store.save(p); profileNames = [p.name] }

        engine.onStatus = { [weak self] st in self?.status = st }
        engine.onMacroRecorded = { [weak self] key, macro in
            self?.profile.remaps[key] = nil
            self?.profile.macros[key] = macro
        }
        engine.onBrightnessStep = { [weak self] d in
            guard let self else { return }
            self.profile.brightness = max(0, min(100, self.profile.brightness + d))
        }
        Publishers.CombineLatest($profile, $settings)
            .dropFirst()
            .sink { [weak self] p, s in
                guard let self else { return }
                self.engine.update(profile: p, settings: s)
                self.scheduleSave(p, s)
            }
            .store(in: &bag)
        engine.start()
    }

    private func scheduleSave(_ p: Profile, _ s: Store.Settings) {
        saveWork?.cancel()
        let w = DispatchWorkItem { [store] in
            try? store.save(p)
            try? store.saveSettings(s)
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    // MARK: lighting helpers

    var lightsOn: Bool { profile.effect.type != .off }

    func setLights(_ on: Bool) {
        if on { profile.effect = lastOnEffect ?? Effect(type: .spectrum) }
        else { lastOnEffect = profile.effect; profile.effect = Effect(type: .off) }
    }

    func selectEffect(_ t: EffectType) {
        var e = profile.effect
        if e.type != .off { lastOnEffect = e }
        e.type = t
        switch t {
        case .static, .reactive, .ripple: if e.color == nil { e.color = t == .ripple ? RGB(0, 200, 255) : RGB(0, 255, 0) }
        case .gradient: if (e.colors?.count ?? 0) < 2 { e.colors = [RGB(255, 0, 120), RGB(0, 120, 255)] }
        default: break
        }
        profile.effect = e
    }

    /// The "main" color of the current effect, for the quick color picker.
    var primaryColor: RGB? {
        get {
            switch profile.effect.type {
            case .static, .reactive, .ripple: return profile.effect.color
            case .breathing, .starlight: return profile.effect.colors?.first ?? profile.effect.color
            default: return nil
            }
        }
        set {
            guard let c = newValue else { return }
            switch profile.effect.type {
            case .static, .reactive, .ripple: profile.effect.color = c
            case .breathing, .starlight: profile.effect.colors = [c]
            default: break
            }
        }
    }

    // MARK: profiles

    func refreshProfiles() { profileNames = store.profileNames() }

    func switchProfile(_ name: String) {
        flushSave()
        do {
            let p = try store.load(name)
            settings.activeProfile = name
            profile = p
            lastOnEffect = nil
        } catch { errorMessage = "\(error)" }
    }

    func createProfile(_ name: String, duplicate: Bool) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        guard !store.exists(n) else { errorMessage = "A profile named “\(n)” already exists."; return }
        flushSave()
        var p = duplicate ? profile : Profile(name: n)
        p.name = n
        try? store.save(p)
        refreshProfiles()
        switchProfile(n)
    }

    func renameProfile(_ old: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != old else { return }
        guard !store.exists(n) else { errorMessage = "A profile named “\(n)” already exists."; return }
        flushSave()
        do {
            var p = try store.load(old); p.name = n
            try store.save(p); try store.delete(old)
            if settings.activeProfile == old { settings.activeProfile = n; profile = p }
            refreshProfiles()
        } catch { errorMessage = "\(error)" }
    }

    func deleteProfile(_ name: String) {
        guard name != settings.activeProfile else { errorMessage = "Switch to another profile before deleting this one."; return }
        try? store.delete(name)
        refreshProfiles()
    }

    func flushSave() {
        saveWork?.cancel()
        try? store.save(profile)
        try? store.saveSettings(settings)
    }

    func exportProfiles(_ names: [String]?) {
        flushSave()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = names?.count == 1 ? "\(names![0]).prismkeys.json" : "Prism Keys Profiles.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { _ = try store.export(names: names, to: url) } catch { errorMessage = "Export failed: \(error)" }
    }

    func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        var imported: [String] = []
        for url in panel.urls {
            do { imported += try store.importBundle(from: url, overwrite: false, activate: false) }
            catch { errorMessage = "\(url.lastPathComponent): \(error)" }
        }
        refreshProfiles()
        if let first = imported.first { switchProfile(first) }
    }

    // MARK: launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { errorMessage = "Couldn't change login item: \(error.localizedDescription)" }
        }
    }

    // MARK: URL scheme

    func handleURL(_ url: URL) {
        guard url.scheme == "prismkeys" else { return }
        let host = url.host ?? ""
        let arg = url.pathComponents.dropFirst().first ?? ""
        switch host {
        case "alert":
            switch arg {
            case "call": engine.trigger(.call)
            case "clear": engine.clearAlerts()
            default: engine.trigger(.notify)
            }
        case "profile": if profileNames.contains(arg) { switchProfile(arg) }
        case "effect": if let t = EffectType(rawValue: arg) { selectEffect(t) }
        case "lights": setLights(arg != "off")
        case "gamemode": engine.setGameMode(arg != "off")
        case "diagnose": if arg == "ax" { AXTree.dumpStructure() } else { NotificationWatcher.diagnose() }
        case "settings": WindowRouter.openSettings?()
        case "identify":
            if let keys = try? KeyLayout.resolve(arg) { engine.identify(keys, seconds: 20) }
        case "test":
            switch arg {
            case "white": engine.show(TestPattern.allKeys(), for: 300)
            case "rainbow": engine.show(TestPattern.rainbow(), for: 300)
            case "matrix": engine.show(TestPattern.matrix(), for: 300)
            case "white50": engine.show(TestPattern.allKeys(level: 0.5), for: 300)
            case "static-white": engine.hold(for: 300) { try $0.effectStatic(.white) }
            default: engine.endHold()
            }
        default: break
        }
    }
}

// MARK: - Permissions

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var fullDiskAccess: Bool { NotificationWatcher.checkAccess() == nil }
    static var inputMonitoring: Bool { RazerInputListener.hasPermission }

    static func requestAccessibility() {
        _ = KeyTap.isTrusted(prompt: true)
        open("Privacy_Accessibility")
    }
    static func open(_ pane: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(u) }
    }
}

// MARK: - Color bridging

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    init(_ c: Color) {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .white
        self.init(UInt8(clamping: Int((ns.redComponent * 255).rounded())),
                  UInt8(clamping: Int((ns.greenComponent * 255).rounded())),
                  UInt8(clamping: Int((ns.blueComponent * 255).rounded())))
    }
}

extension Binding where Value == RGB {
    var color: Binding<Color> {
        Binding<Color>(get: { wrappedValue.color }, set: { wrappedValue = RGB($0) })
    }
}

extension EffectType {
    var title: String {
        switch self {
        case .off: return "Off"
        case .static: return "Static"
        case .breathing: return "Breathing"
        case .spectrum: return "Spectrum"
        case .wave: return "Wave"
        case .reactive: return "Reactive"
        case .rainbow: return "Rainbow"
        case .ripple: return "Ripple"
        case .starlight: return "Starlight"
        case .heatmap: return "Heatmap"
        case .gradient: return "Gradient"
        }
    }
    var symbol: String {
        switch self {
        case .off: return "power"
        case .static: return "circle.fill"
        case .breathing: return "wind"
        case .spectrum: return "paintpalette"
        case .wave: return "water.waves"
        case .reactive: return "hand.tap"
        case .rainbow: return "rainbow"
        case .ripple: return "dot.radiowaves.left.and.right"
        case .starlight: return "sparkles"
        case .heatmap: return "flame"
        case .gradient: return "circle.lefthalf.filled"
        }
    }
    var summary: String {
        switch self {
        case .off: return "All lights off."
        case .static: return "One solid color. Runs on the keyboard itself."
        case .breathing: return "Fades in and out. Up to two colors, or none for random."
        case .spectrum: return "The whole keyboard slowly cycles through every color."
        case .wave: return "A rainbow that sweeps across the keyboard."
        case .reactive: return "Keys light up briefly when you press them."
        case .rainbow: return "A diagonal rainbow that flows across the keys."
        case .ripple: return "Ripples spread out from every key you press."
        case .starlight: return "Random keys twinkle on and off."
        case .heatmap: return "Keys glow warmer the more you use them."
        case .gradient: return "A smooth gradient across the keyboard."
        }
    }
    var usesTyping: Bool { self == .ripple || self == .heatmap }
    var hasSpeed: Bool { [.rainbow, .ripple, .starlight, .reactive].contains(self) }
}

/// Patterns for checking that every key's LED position is right.
enum TestPattern {
    /// Every known key white, everything else off: a dark key = wrong/missing LED position.
    static func allKeys(level: Double = 1) -> Frame {
        var f = Frame()
        for k in KeyLayout.keys { f[k.row, k.col] = RGB.white.scaled(level) }
        return f
    }
    /// Smooth rainbow by physical position: a key with the "wrong" color is in the wrong place.
    static func rainbow() -> Frame {
        var f = Frame()
        for cap in VisualLayout.caps {
            guard let k = KeyLayout.key(cap.id) else { continue }
            f[k.row, k.col] = RGB.hsv((cap.x + cap.w / 2) / VisualLayout.width * 0.8, 1, 1)
        }
        return f
    }
    /// Every LED in the matrix lit (including unmapped ones): shows LEDs we don't know about.
    static func matrix() -> Frame {
        var f = Frame(fill: RGB(255, 0, 0))
        for k in KeyLayout.keys { f[k.row, k.col] = RGB(0, 40, 0) }
        return f
    }
}

// MARK: - Alert color clashes

extension RGB {
    /// True if two colors look about the same on the keyboard (perceptually weighted RGB distance).
    func looksLike(_ o: RGB) -> Bool {
        let dr = Double(r) - Double(o.r), dg = Double(g) - Double(o.g), db = Double(b) - Double(o.b)
        return (2 * dr * dr + 4 * dg * dg + 3 * db * db).squareRoot() < 110
    }
}

extension AppModel {
    /// Warnings for alert colors that would be hard to see against the current lighting.
    var alertColorClashes: [String] {
        guard profile.alerts.watchNotifications else { return [] }
        var out: [String] = []
        let alerts: [(String, AlertStyle)] = [("Notification", profile.alerts.notification), ("Incoming call", profile.alerts.call)]
        for (name, style) in alerts {
            if profile.effect.type == .static, let c = profile.effect.color, c.looksLike(style.color) {
                out.append("\(name) alerts use \(c == style.color ? "the same color as" : "almost the same color as") your Static color, so you may not notice them.")
                continue
            }
            let keys = Set(((try? KeyLayout.resolve(style.keys)) ?? []).map(\.name))
            let clashing = keys.filter { profile.keyColors[$0]?.looksLike(style.color) == true }
            if !clashing.isEmpty {
                let names = clashing.sorted().prefix(4).map { VisualLayout.label($0) }.joined(separator: ", ")
                out.append("\(name) alerts use the same color as your custom color on \(names)\(clashing.count > 4 ? " and \(clashing.count - 4) more" : ""), so you may not notice them there.")
            }
        }
        return out
    }
}

struct AlertClashWarning: View {
    @EnvironmentObject var model: AppModel
    var showAlertsHint = true
    var body: some View {
        let clashes = model.alertColorClashes
        if !clashes.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(clashes, id: \.self) { Text($0) }
                    if showAlertsHint {
                        Text("Pick a different lighting color, or change the alert color in the Alerts tab.").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.6), lineWidth: 1))
        }
    }
}
