import Foundation

/// Applies a profile's lighting. Hardware effects are sent once; software effects are
/// rendered frame-by-frame by `Animator` inside the background service.
public enum Lighting {
    /// Applies lighting that the keyboard can run on its own. Returns false if the
    /// effect needs the background service (software animation).
    @discardableResult
    public static func applyHardware(_ p: Profile, to kb: RazerKeyboard, maxBrightness: Int = 100) throws -> Bool {
        try kb.setBrightness(level(p.brightness, cap: maxBrightness))
        if p.needsServiceForLighting { return false }
        let e = p.effect
        switch e.type {
        case .off:
            if p.keyColors.isEmpty { try kb.effectNone() } else { try kb.showFrame(staticFrame(p, base: .black)) }
        case .static:
            let c = e.color ?? .white
            if p.keyColors.isEmpty { try kb.effectStatic(c) } else { try kb.showFrame(staticFrame(p, base: c)) }
        case .breathing: try kb.effectBreathing(e.colors ?? (e.color.map { [$0] } ?? []))
        case .spectrum: try kb.effectSpectrum()
        case .wave: try kb.effectWave(direction: e.direction == "left" ? 2 : 1)
        case .reactive:
            try kb.effectReactive(e.color ?? RGB(0, 255, 0), speed: UInt8(max(1, min(4, e.speed ?? 2))))
        default: return false
        }
        return true
    }

    /// Profile brightness (%) limited by the power cap (%), as a 0...255 device value.
    public static func level(_ brightness: Int, cap: Int) -> UInt8 {
        let b = max(0, min(100, brightness)), c = max(10, min(100, cap))
        return UInt8(b * c * 255 / 10_000)
    }

    static func staticFrame(_ p: Profile, base: RGB) -> Frame {
        var f = Frame(fill: base)
        for (name, color) in p.keyColors {
            if let k = KeyLayout.key(name) { f[k.row, k.col] = color }
        }
        return f
    }
}

/// Software renderer for animated effects and alert overlays.
public final class Animator {
    public enum AlertKind: String { case notify, call }

    struct ActiveAlert {
        let kind: AlertKind
        let style: AlertStyle
        let keys: [Key]
        let start: Date
    }

    private let lock = NSLock()
    private var profile: Profile
    private var start = Date()
    private var ripples: [(row: Int, col: Int, t: Date)] = []
    private var reactiveHits: [Int: Date] = [:]   // matrix index -> press time
    private var heat = [Double](repeating: 0, count: 6 * 22)
    private var stars: [Int: (color: RGB, t: Date, life: Double)] = [:]
    private var alert: ActiveAlert?
    private var indicator: (keys: [Key], color: RGB)?

    public init(profile: Profile) { self.profile = profile }

    public func setProfile(_ p: Profile) {
        lock.lock(); defer { lock.unlock() }
        profile = p
    }

    /// True when software frames must be pushed (animated effect, alert or indicator active).
    public var needsFrames: Bool {
        lock.lock(); defer { lock.unlock() }
        return profile.needsServiceForLighting || alert != nil || indicator != nil
    }

    public var hasAlert: Bool { lock.lock(); defer { lock.unlock() }; return alert != nil || indicator != nil }

    // MARK: events

    public func keyPressed(_ key: Key?) {
        lock.lock(); defer { lock.unlock() }
        if let a = alert, profile.alerts.dismissOnKeypress, Date().timeIntervalSince(a.start) > 0.4 {
            alert = nil
        }
        indicator = nil
        guard let k = key else { return }
        let now = Date()
        ripples.append((k.row, k.col, now))
        if ripples.count > 24 { ripples.removeFirst(ripples.count - 24) }
        reactiveHits[k.row * 22 + k.col] = now
        heat[k.row * 22 + k.col] = min(1, heat[k.row * 22 + k.col] + 0.06)
    }

    public func trigger(_ kind: AlertKind) {
        lock.lock(); defer { lock.unlock() }
        let style = kind == .call ? profile.alerts.call : profile.alerts.notification
        // A call always wins over a notification that is already running.
        if let a = alert, a.kind == .call, kind == .notify { return }
        let keys = (try? KeyLayout.resolve(style.keys)) ?? KeyLayout.keys
        alert = ActiveAlert(kind: kind, style: style, keys: keys, start: Date())
    }

    public func clearAlerts() {
        lock.lock(); defer { lock.unlock() }
        alert = nil; indicator = nil
    }

    // MARK: rendering

    public func render(now: Date = Date()) -> Frame {
        lock.lock(); defer { lock.unlock() }
        var f = Frame()
        let t = now.timeIntervalSince(start)
        let e = profile.effect
        let speed = Double(max(1, min(10, e.speed ?? 5)))

        switch e.type {
        case .off: break
        case .static:
            f = Frame(fill: e.color ?? .white)
        case .breathing:
            let cols = e.colors ?? (e.color.map { [$0] } ?? [])
            let period = 4.0
            let cycle = Int(t / period)
            let phase = (t.truncatingRemainder(dividingBy: period)) / period
            let level = 0.5 - 0.5 * cos(phase * 2 * .pi)
            let c = cols.isEmpty ? RGB.hsv(Double(cycle) * 0.37, 1, 1) : cols[cycle % cols.count]
            f = Frame(fill: c.scaled(level))
        case .spectrum:
            f = Frame(fill: RGB.hsv(t * 0.05, 1, 1))
        case .wave:
            let dir = e.direction == "left" ? -1.0 : 1.0
            for r in 0..<6 { for c in 0..<22 { f[r, c] = RGB.hsv(Double(c) / 22 - dir * t * 0.25, 1, 1) } }
        case .rainbow:
            for r in 0..<6 { for c in 0..<22 { f[r, c] = RGB.hsv(Double(c + r) / 26 - t * speed * 0.04, 1, 1) } }
        case .gradient:
            let cols = (e.colors?.count ?? 0) >= 2 ? e.colors! : [RGB(255, 0, 120), RGB(0, 120, 255)]
            for c in 0..<22 {
                let x = Double(c) / 21 * Double(cols.count - 1)
                let i = min(Int(x), cols.count - 2)
                let col = cols[i].mix(cols[i + 1], x - Double(i))
                for r in 0..<6 { f[r, c] = col }
            }
        case .reactive:
            let bg = e.background ?? .black
            f = Frame(fill: bg)
            let life = [0.3, 0.6, 1.2, 2.0][max(1, min(4, e.speed ?? 2)) - 1]
            let c = e.color ?? RGB(0, 255, 0)
            for (idx, pt) in reactiveHits {
                let age = now.timeIntervalSince(pt)
                if age > life { reactiveHits[idx] = nil; continue }
                f.pixels[idx] = bg.mix(c, 1 - age / life)
            }
        case .ripple:
            let bg = e.background ?? .black
            f = Frame(fill: bg)
            let c = e.color ?? RGB(0, 200, 255)
            let v = 4 + speed * 2.5 // keys per second
            ripples.removeAll { now.timeIntervalSince($0.t) > 2.5 }
            for rp in ripples {
                let radius = now.timeIntervalSince(rp.t) * v
                let fade = 1 - now.timeIntervalSince(rp.t) / 2.5
                for r in 0..<6 {
                    for col in 0..<22 {
                        let d = hypot(Double(col - rp.col), Double(r - rp.row) * 1.2)
                        let w = max(0, 1 - abs(d - radius) / 1.2) * fade
                        if w > 0 { f[r, col] = f[r, col].mix(c, w) }
                    }
                }
            }
        case .starlight:
            let bg = e.background ?? .black
            f = Frame(fill: bg)
            let palette = e.colors ?? []
            let spawnPerSec = speed * 1.5
            if Double.random(in: 0..<1) < spawnPerSec / 30 {
                let k = KeyLayout.keys.randomElement()!
                let c = palette.randomElement() ?? RGB.hsv(Double.random(in: 0..<1), 0.8, 1)
                stars[k.row * 22 + k.col] = (c, now, Double.random(in: 1.0...2.5))
            }
            for (idx, s) in stars {
                let age = now.timeIntervalSince(s.t)
                if age > s.life { stars[idx] = nil; continue }
                f.pixels[idx] = bg.mix(s.color, sin(age / s.life * .pi))
            }
        case .heatmap:
            for i in 0..<heat.count {
                heat[i] = max(0, heat[i] - 0.0004)
                let h = heat[i]
                f.pixels[i] = h <= 0.001 ? RGB(0, 0, 25) : RGB.hsv(0.66 - 0.66 * h, 1, 0.25 + 0.75 * min(1, h * 2))
            }
        }

        // Per-key overlay
        for (name, color) in profile.keyColors {
            if let k = KeyLayout.key(name) { f[k.row, k.col] = color }
        }

        // Unread indicator
        if let ind = indicator {
            let level = 0.35 + 0.35 * (0.5 + 0.5 * sin(t * 2))
            for k in ind.keys { f[k.row, k.col] = ind.color.scaled(level) }
        }

        // Alert overlay
        if let a = alert {
            let age = now.timeIntervalSince(a.start)
            if age > a.style.duration {
                if a.style.persist, let keys = try? KeyLayout.resolve(a.style.persistKeys) {
                    indicator = (keys, a.style.color)
                }
                alert = nil
            } else {
                drawAlert(a, age: age, into: &f)
            }
        }
        return f
    }

    private func drawAlert(_ a: ActiveAlert, age: Double, into f: inout Frame) {
        let s = a.style
        let keys = a.keys.sorted { ($0.col, $0.row) < ($1.col, $1.row) }
        switch s.pattern {
        case .solid:
            for k in keys { f[k.row, k.col] = s.color }
        case .flash:
            let on = Int(age * 3) % 2 == 0
            for k in keys { f[k.row, k.col] = on ? s.color : .black }
        case .pulse:
            let level = 0.5 - 0.5 * cos(age * 2 * .pi / 1.2)
            let c2 = s.secondColor ?? .black
            for k in keys { f[k.row, k.col] = c2.scaled(0.25).mix(s.color, level) }
        case .strobe:
            let on = Int(age * 8) % 2 == 0
            for k in keys { f[k.row, k.col] = on ? s.color : (s.secondColor ?? .black) }
        case .sweep:
            // A bright head runs across the keys, leaving a fading trail; repeats.
            let n = max(1, keys.count)
            let pass = 0.9
            let pos = (age.truncatingRemainder(dividingBy: pass) / pass) * Double(n + 4)
            for (i, k) in keys.enumerated() {
                let d = pos - Double(i)
                let w: Double = d < 0 ? 0 : max(0, 1 - d / 4)
                f[k.row, k.col] = f[k.row, k.col].scaled(0.3).mix(s.color, max(w, 0.15))
            }
        }
    }
}
