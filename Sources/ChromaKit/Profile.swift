import Foundation

public enum EffectType: String, Codable, CaseIterable {
    // Run by the keyboard's firmware (work without the background service)
    case off, `static`, breathing, spectrum, wave, reactive
    // Rendered in software by the background service
    case rainbow, ripple, starlight, heatmap, gradient

    public var isHardware: Bool {
        switch self {
        case .off, .static, .breathing, .spectrum, .wave, .reactive: return true
        default: return false
        }
    }

    public var help: String {
        switch self {
        case .off: return "All LEDs off"
        case .static: return "One solid color            --color"
        case .breathing: return "Fade in/out                --colors (0 = random, 1 or 2 colors)"
        case .spectrum: return "Whole keyboard cycles through all colors"
        case .wave: return "Rainbow wave               --direction left|right"
        case .reactive: return "Keys light up when pressed --color --speed 1-4 (1 = short)"
        case .rainbow: return "Diagonal flowing rainbow   --speed 1-10   [service]"
        case .ripple: return "Ripples spread from keys   --color --speed --background [service]"
        case .starlight: return "Random twinkling keys      --colors --speed --background [service]"
        case .heatmap: return "Keys glow by how often you use them  [service]"
        case .gradient: return "Static gradient left→right --colors (2+)  [service]"
        }
    }
}

public struct Effect: Codable, Equatable {
    public var type: EffectType
    public var color: RGB?
    public var colors: [RGB]?
    public var background: RGB?
    public var speed: Int?
    public var direction: String?

    public init(type: EffectType, color: RGB? = nil, colors: [RGB]? = nil, background: RGB? = nil, speed: Int? = nil, direction: String? = nil) {
        self.type = type; self.color = color; self.colors = colors; self.background = background; self.speed = speed; self.direction = direction
    }
}

public struct MacroAction: Codable, Equatable, CustomStringConvertible {
    public enum Kind: String, Codable, CaseIterable {
        case text      // type a string
        case keys      // press a shortcut like cmd+shift+4
        case delay     // wait N milliseconds
        case app       // open/focus an app by name or bundle id
        case shell     // run a shell command
        case url       // open a URL
    }
    public var type: Kind
    public var value: String
    public init(type: Kind, value: String) { self.type = type; self.value = value }
    public var description: String { "\(type.rawValue):\(value)" }
}

public struct Macro: Codable, Equatable {
    public var actions: [MacroAction]
    public init(actions: [MacroAction]) { self.actions = actions }
}

public enum AlertPattern: String, Codable, CaseIterable {
    case sweep   // light the keys one after another
    case flash   // blink on/off
    case pulse   // smooth fade in/out
    case strobe  // fast alternating with a second color
    case solid   // just turn them on
}

public struct AlertStyle: Codable, Equatable {
    /// Keys to light: names/groups, e.g. "f1-f12" or "logo,esc"
    public var keys: String
    public var color: RGB
    public var secondColor: RGB?
    public var pattern: AlertPattern
    /// How long the animation plays (seconds)
    public var duration: Double
    /// After the animation, keep a small indicator lit until you press a key
    public var persist: Bool
    public var persistKeys: String
}

public struct AlertSettings: Codable, Equatable {
    /// Watch macOS notifications (needs Full Disk Access for the service)
    public var watchNotifications: Bool = true
    public var notification = AlertStyle(keys: "f1-f12", color: RGB(0, 180, 255), secondColor: nil,
                                         pattern: .sweep, duration: 4, persist: true, persistKeys: "logo")
    public var call = AlertStyle(keys: "all", color: RGB(0, 255, 60), secondColor: RGB(0, 40, 255),
                                 pattern: .pulse, duration: 25, persist: false, persistKeys: "logo")
    /// Apps whose notifications always count as calls
    public var callApps: [String] = ["com.apple.facetime", "com.apple.mobilephone", "com.apple.telephonyutilities", "com.apple.inCallService"]
    /// Notification text that marks a call (case-insensitive), from any app (WhatsApp, Teams, Zoom, ...)
    public var callKeywords: [String] = ["incoming call", "incoming video call", "incoming voice call", "is calling", "calling you", "incoming audio call", "κλήση"]
    /// Apps whose notifications are ignored
    public var ignoreApps: [String] = []
    /// Apps that should alert (empty = all apps)
    public var onlyApps: [String] = []
    /// Press any key to stop an alert
    public var dismissOnKeypress: Bool = true

    public init() {}

    public init(from decoder: Decoder) throws {
        // Tolerant decoding so older/partial exports still load.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertSettings()
        watchNotifications = try c.decodeIfPresent(Bool.self, forKey: .watchNotifications) ?? d.watchNotifications
        notification = try c.decodeIfPresent(AlertStyle.self, forKey: .notification) ?? d.notification
        call = try c.decodeIfPresent(AlertStyle.self, forKey: .call) ?? d.call
        callApps = try c.decodeIfPresent([String].self, forKey: .callApps) ?? d.callApps
        callKeywords = try c.decodeIfPresent([String].self, forKey: .callKeywords) ?? d.callKeywords
        ignoreApps = try c.decodeIfPresent([String].self, forKey: .ignoreApps) ?? d.ignoreApps
        onlyApps = try c.decodeIfPresent([String].self, forKey: .onlyApps) ?? d.onlyApps
        dismissOnKeypress = try c.decodeIfPresent(Bool.self, forKey: .dismissOnKeypress) ?? d.dismissOnKeypress
    }
}

public struct Profile: Codable, Equatable {
    public var name: String
    /// 0...100 %
    public var brightness: Int = 100
    public var effect: Effect = Effect(type: .spectrum)
    /// Per-key colors drawn on top of the effect, e.g. {"w": "#ff0000"}
    public var keyColors: [String: RGB] = [:]
    /// Key remaps for this keyboard only, e.g. {"capslock": "esc"}
    public var remaps: [String: String] = [:]
    /// Macros bound to keys, e.g. {"m1": {...}}
    public var macros: [String: Macro] = [:]
    public var alerts = AlertSettings()

    public init(name: String) { self.name = name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        brightness = try c.decodeIfPresent(Int.self, forKey: .brightness) ?? 100
        effect = try c.decodeIfPresent(Effect.self, forKey: .effect) ?? Effect(type: .spectrum)
        keyColors = try c.decodeIfPresent([String: RGB].self, forKey: .keyColors) ?? [:]
        remaps = try c.decodeIfPresent([String: String].self, forKey: .remaps) ?? [:]
        macros = try c.decodeIfPresent([String: Macro].self, forKey: .macros) ?? [:]
        alerts = try c.decodeIfPresent(AlertSettings.self, forKey: .alerts) ?? AlertSettings()
    }

    /// True if this profile needs the background service for its lighting.
    public var needsServiceForLighting: Bool {
        if !effect.type.isHardware { return true }
        if !keyColors.isEmpty && effect.type != .static && effect.type != .off { return true }
        return false
    }
}
