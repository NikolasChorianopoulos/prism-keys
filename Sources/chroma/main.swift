import ChromaKit
import Foundation

// MARK: - tiny argument helpers

struct Args {
    var items: [String]
    init(_ a: [String]) { items = a }
    mutating func next() -> String? { items.isEmpty ? nil : items.removeFirst() }
    mutating func require(_ what: String) throws -> String {
        guard let v = next() else { throw ChromaError.invalid("Missing \(what).") }
        return v
    }
    /// Removes and returns `--name value` (or `--name=value`).
    mutating func option(_ name: String) -> String? {
        if let i = items.firstIndex(where: { $0 == "--\(name)" }), i + 1 < items.count {
            let v = items[i + 1]; items.removeSubrange(i...(i + 1)); return v
        }
        if let i = items.firstIndex(where: { $0.hasPrefix("--\(name)=") }) {
            let v = String(items[i].dropFirst(name.count + 3)); items.remove(at: i); return v
        }
        return nil
    }
    mutating func flag(_ name: String) -> Bool {
        if let i = items.firstIndex(of: "--\(name)") { items.remove(at: i); return true }
        return false
    }
}

let store = Store.shared
let tty = isatty(1) != 0
func bold(_ s: String) -> String { tty ? "\u{1B}[1m\(s)\u{1B}[0m" : s }
func dim(_ s: String) -> String { tty ? "\u{1B}[2m\(s)\u{1B}[0m" : s }
func swatch(_ c: RGB) -> String { tty ? "\u{1B}[48;2;\(c.r);\(c.g);\(c.b)m   \u{1B}[0m \(c.hex)" : c.hex }
func color(_ s: String) throws -> RGB {
    guard let c = RGB(parse: s) else { throw ChromaError.invalid("Unknown color '\(s)'. Use a name (red, cyan…), #rrggbb or r,g,b.") }
    return c
}
func onOff(_ s: String) throws -> Bool {
    switch s.lowercased() {
    case "on", "true", "yes", "1": return true
    case "off", "false", "no", "0": return false
    default: throw ChromaError.invalid("Expected on/off, got '\(s)'.")
    }
}

var serviceRunning: Bool { IPC.send(["cmd": "status"], timeout: 1) != nil }

/// Saves happened already; push the active profile to the keyboard.
func commit(quiet: Bool = false) throws {
    let p = try store.activeProfile()
    if let r = IPC.send(["cmd": "reload"]) {
        if r["ok"] != "true" { throw ChromaError.io(r["error"] ?? "service error") }
        if let w = r["warnings"], !w.isEmpty { print("⚠️  \(w)") }
        return
    }
    let kb = try RazerKeyboard()
    if store.settings().driverMode { try? kb.setDeviceMode(0x03) }
    let ok = try Lighting.applyHardware(p, to: kb)
    for w in Remapper.apply(p, model: kb.model) { print("⚠️  \(w)") }
    if !quiet {
        if !ok { print("⚠️  This effect is animated by the background service, which isn't running. Start it with `chroma service install`.") }
        if !p.macros.isEmpty { print("⚠️  Macros need the background service: `chroma service install`.") }
    }
}

// MARK: - commands

func cmdStatus() throws {
    if let kb = try? RazerKeyboard() {
        print("\(bold("Keyboard:"))  \(kb.model.name)  firmware \((try? kb.firmwareVersion()) ?? "?")")
        if let b = try? kb.brightness() { print("\(bold("Brightness:")) \(Int(b) * 100 / 255)%") }
    } else {
        print("\(bold("Keyboard:"))  not connected")
    }
    let p = try store.activeProfile()
    print("\(bold("Profile:"))   \(p.name)  (\(store.profileNames().count) total)")
    print("\(bold("Effect:"))    \(describe(p.effect))")
    if let s = IPC.send(["cmd": "status"]) {
        print("\(bold("Service:"))   running (pid \(s["pid"] ?? "?"))")
        print("           key tap: \(s["keytap"] ?? "?")")
        print("           notifications: \(s["notifications"] ?? "?")")
    } else {
        print("\(bold("Service:"))   \(LaunchAgent.isInstalled ? "installed but not running" : "not installed") \(dim("(chroma service install)"))")
    }
    print("\(bold("Data:"))      \(store.baseDir.path)")
}

func describe(_ e: Effect) -> String {
    var parts = [e.type.rawValue]
    if let c = e.color { parts.append("color \(c.hex)") }
    if let cs = e.colors, !cs.isEmpty { parts.append("colors \(cs.map(\.hex).joined(separator: ","))") }
    if let b = e.background { parts.append("background \(b.hex)") }
    if let s = e.speed { parts.append("speed \(s)") }
    if let d = e.direction { parts.append("direction \(d)") }
    return parts.joined(separator: "  ")
}

func cmdEffect(_ a: inout Args) throws {
    guard let name = a.next(), name != "list" else {
        print(bold("Effects") + dim("   ([service] = animated by the background service)"))
        for t in EffectType.allCases { print("  \(t.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)) \(t.help)") }
        print("\nExamples:\n  chroma effect static --color purple\n  chroma effect breathing --colors red,blue\n  chroma effect wave --direction left\n  chroma effect ripple --color cyan --background 0,0,40")
        return
    }
    guard let type = EffectType(rawValue: name.lowercased()) else { throw ChromaError.invalid("Unknown effect '\(name)'. Run `chroma effect list`.") }
    var e = Effect(type: type)
    if let c = a.option("color") { e.color = try color(c) }
    if let cs = a.option("colors") { e.colors = try cs.split(separator: ",").map { try color(String($0)) } }
    if let b = a.option("background") { e.background = try color(b) }
    if let s = a.option("speed") { guard let v = Int(s) else { throw ChromaError.invalid("Bad speed") }; e.speed = v }
    if let d = a.option("direction") { e.direction = d.lowercased() }
    if let rest = a.next() { // allow `chroma effect static red`
        if type == .breathing || type == .gradient || type == .starlight { e.colors = try rest.split(separator: ",").map { try color(String($0)) } }
        else { e.color = try color(rest) }
    }
    if type == .static && e.color == nil { e.color = .white }
    try store.updateActive { $0.effect = e }
    try commit()
    print("Effect: \(describe(e))")
}

func cmdBrightness(_ a: inout Args) throws {
    guard let v = a.next() else {
        let kb = try RazerKeyboard()
        print("\(Int(try kb.brightness()) * 100 / 255)%"); return
    }
    guard let n = Int(v.replacingOccurrences(of: "%", with: "")), (0...100).contains(n) else { throw ChromaError.invalid("Brightness must be 0-100.") }
    try store.updateActive { $0.brightness = n }
    try commit()
    print("Brightness: \(n)%")
}

func cmdKey(_ a: inout Args) throws {
    let sub = a.next() ?? "list"
    switch sub {
    case "set":
        let spec = try a.require("keys (e.g. wasd, f1-f4, q,e)")
        let c = try color(try a.require("color"))
        let keys = try KeyLayout.resolve(spec)
        try store.updateActive { p in for k in keys { p.keyColors[k.name] = c } }
        try commit()
        print("Set \(keys.count) key(s) to \(swatch(c))")
    case "clear":
        let spec = a.next() ?? "all"
        let keys = try KeyLayout.resolve(spec)
        try store.updateActive { p in if spec == "all" { p.keyColors = [:] } else { for k in keys { p.keyColors[k.name] = nil } } }
        try commit()
        print("Cleared key colors (\(spec)).")
    case "list":
        let p = try store.activeProfile()
        if p.keyColors.isEmpty { print("No per-key colors in '\(p.name)'. Try: chroma key set wasd red"); return }
        for (k, c) in p.keyColors.sorted(by: { $0.key < $1.key }) { print("  \(k.padding(toLength: 14, withPad: " ", startingAt: 0)) \(swatch(c))") }
    default:
        // shorthand: chroma key wasd red
        let c = try color(try a.require("color"))
        var b = Args(["set", sub, c.hex]); try cmdKey(&b)
    }
}

func cmdKeys() {
    print(bold("Keys") + dim("  (names you can use for colors, remaps and macros)"))
    for r in 0..<6 {
        let names = KeyLayout.keys.filter { $0.row == r }.sorted { $0.col < $1.col }.map(\.name)
        print("  row \(r): " + names.joined(separator: " "))
    }
    print("\n" + bold("Groups"))
    for (g, ks) in KeyLayout.groups.sorted(by: { $0.key < $1.key }) where !g.hasPrefix("row") {
        print("  \(g.padding(toLength: 10, withPad: " ", startingAt: 0)) \(ks.prefix(14).joined(separator: " "))\(ks.count > 14 ? " …" : "")")
    }
    print("\nRanges also work, e.g. f1-f6, q-p, 1-5.  Lists: q,w,e,r")
    print("Extra remap targets: " + KeyLayout.extraTargets.keys.sorted().joined(separator: " "))
}

func cmdRemap(_ a: inout Args) throws {
    let sub = a.next() ?? "list"
    switch sub {
    case "list":
        let p = try store.activeProfile()
        if p.remaps.isEmpty { print("No remaps. Example: chroma remap capslock esc"); return }
        for (f, t) in p.remaps.sorted(by: { $0.key < $1.key }) { print("  \(f) → \(t)") }
    case "remove", "rm", "delete":
        let k = try a.require("key")
        let name = KeyLayout.key(k)?.name ?? k
        try store.updateActive { $0.remaps[name] = nil }
        try commit(); print("Removed remap for \(name).")
    case "clear":
        try store.updateActive { $0.remaps = [:] }
        try commit(); print("All remaps removed.")
    default:
        let to = try a.require("target key").lowercased()
        guard let fk = KeyLayout.key(sub) else { throw ChromaError.invalid("Unknown key '\(sub)'.") }
        guard KeyLayout.key(to) != nil || KeyLayout.extraTargets[to] != nil else { throw ChromaError.invalid("Unknown target '\(to)'. See `chroma keys`.") }
        let target = KeyLayout.key(to)?.name ?? to
        try store.updateActive { $0.remaps[fk.name] = target }
        try commit()
        print("Remapped \(fk.name) → \(target) (this keyboard only).")
    }
}

func parseActions(_ items: [String]) throws -> [MacroAction] {
    var out: [MacroAction] = []
    for it in items {
        guard let colon = it.firstIndex(of: ":") else { throw ChromaError.invalid("Action '\(it)' should look like type:value (text:, keys:, delay:, app:, shell:, url:).") }
        let t = String(it[..<colon]).lowercased(), v = String(it[it.index(after: colon)...])
        guard let kind = MacroAction.Kind(rawValue: t) else { throw ChromaError.invalid("Unknown action type '\(t)'.") }
        if kind == .keys { for c in v.split(separator: " ") where MacroRunner.parseCombo(String(c)) == nil { throw ChromaError.invalid("Can't understand shortcut '\(c)'.") } }
        if kind == .delay, Int(v) == nil { throw ChromaError.invalid("delay needs milliseconds, e.g. delay:200") }
        out.append(MacroAction(type: kind, value: v))
    }
    return out
}

func cmdMacro(_ a: inout Args) throws {
    let sub = a.next() ?? "list"
    switch sub {
    case "list":
        let p = try store.activeProfile()
        if p.macros.isEmpty { print("No macros. Example: chroma macro set m1 'text:Hello!' keys:enter"); return }
        let slots = Remapper.slotAssignments(p)
        for (k, m) in p.macros.sorted(by: { $0.key < $1.key }) {
            print("  \(bold(k))\(slots[k] == nil ? dim(" (inactive: too many macros)") : ""): " + m.actions.map(\.description).joined(separator: "  →  "))
        }
    case "set", "add":
        let key = try a.require("key")
        guard let k = KeyLayout.key(key) else { throw ChromaError.invalid("Unknown key '\(key)'.") }
        let actions = try parseActions(a.items); a.items = []
        guard !actions.isEmpty else { throw ChromaError.invalid("Give at least one action, e.g. text:hello keys:cmd+v delay:100 app:Safari shell:'say hi' url:https://…") }
        try store.updateActive { $0.macros[k.name] = Macro(actions: actions); $0.remaps[k.name] = nil }
        try commit(quiet: true)
        print("Macro on \(k.name): " + actions.map(\.description).joined(separator: "  →  "))
        if !serviceRunning { print("⚠️  Macros run in the background service: `chroma service install`.") }
        if k.name.hasPrefix("m") && k.usage == nil && !store.settings().driverMode {
            print(dim("Note: M1–M5 need driver mode. If the macro doesn't fire, run `chroma keytest` (see README)."))
        }
    case "remove", "rm", "delete":
        let key = try a.require("key")
        let name = KeyLayout.key(key)?.name ?? key
        try store.updateActive { $0.macros[name] = nil }
        try commit(quiet: true); print("Removed macro on \(name).")
    case "run", "test":
        let key = try a.require("key")
        let p = try store.activeProfile()
        guard let m = p.macros[KeyLayout.key(key)?.name ?? key] else { throw ChromaError.invalid("No macro on '\(key)'.") }
        print("Running in 2 seconds — focus the window you want it typed into…")
        sleep(2)
        let r = MacroRunner(); r.run(m, name: key); sleep(UInt32(1 + m.actions.count / 4))
    default:
        throw ChromaError.invalid("Usage: chroma macro list | set <key> <actions…> | remove <key> | run <key>")
    }
}

func cmdProfile(_ a: inout Args) throws {
    let sub = a.next() ?? "list"
    var s = store.settings()
    switch sub {
    case "list", "ls":
        for n in store.profileNames() { print(n == s.activeProfile ? "* \(bold(n))" : "  \(n)") }
    case "show":
        let p = try store.load(a.next() ?? s.activeProfile)
        print("\(bold(p.name))\n  effect:     \(describe(p.effect))\n  brightness: \(p.brightness)%")
        print("  key colors: \(p.keyColors.count)   remaps: \(p.remaps.count)   macros: \(p.macros.count)")
        print("  alerts:     notifications \(p.alerts.watchNotifications ? "on" : "off") — notify \(p.alerts.notification.pattern.rawValue) on \(p.alerts.notification.keys), call \(p.alerts.call.pattern.rawValue) on \(p.alerts.call.keys)")
    case "use", "switch":
        let n = try a.require("profile name")
        _ = try store.load(n)
        s.activeProfile = n; try store.saveSettings(s)
        try commit(); print("Active profile: \(n)")
    case "new", "create":
        let n = try a.require("profile name")
        if store.exists(n) { throw ChromaError.invalid("Profile '\(n)' already exists.") }
        var p = a.flag("blank") ? Profile(name: n) : try store.load(a.option("from") ?? s.activeProfile)
        p.name = n
        try store.save(p)
        s.activeProfile = n; try store.saveSettings(s)
        try commit(); print("Created and switched to '\(n)'.")
    case "delete", "rm":
        let n = try a.require("profile name")
        if n == s.activeProfile { throw ChromaError.invalid("Can't delete the active profile. Switch first.") }
        try store.delete(n); print("Deleted '\(n)'.")
    case "rename":
        let old = try a.require("old name"), new = try a.require("new name")
        var p = try store.load(old); p.name = new; try store.save(p); try store.delete(old)
        if s.activeProfile == old { s.activeProfile = new; try store.saveSettings(s) }
        print("Renamed '\(old)' → '\(new)'.")
    case "path":
        print(store.profilesDir.path)
    default:
        throw ChromaError.invalid("Usage: chroma profile list | show [name] | use <name> | new <name> [--from x|--blank] | delete <name> | rename <old> <new>")
    }
}

func cmdExport(_ a: inout Args) throws {
    var names: [String] = []
    while let p = a.option("profile") { names.append(p) }
    let all = a.flag("all")
    let file = a.next() ?? "chroma-profiles.json"
    let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
    let n = try store.export(names: names.isEmpty ? (all ? nil : nil) : names, to: url)
    print("Exported \(n) profile(s) to \(url.path)")
}

func cmdImport(_ a: inout Args) throws {
    let overwrite = a.flag("overwrite"), activate = a.flag("activate")
    let file = try a.require("file")
    let names = try store.importBundle(from: URL(fileURLWithPath: (file as NSString).expandingTildeInPath), overwrite: overwrite, activate: activate)
    print("Imported: \(names.joined(separator: ", "))")
    if activate { try commit() } else { print(dim("Switch with `chroma profile use <name>`, or re-run with --activate.")) }
}

func cmdAlert(_ a: inout Args) throws {
    let sub = a.next() ?? "show"
    func requireService() throws {
        if !serviceRunning { throw ChromaError.invalid("Alerts are drawn by the background service. Start it with `chroma service install`.") }
    }
    switch sub {
    case "notify", "notification", "call":
        try requireService()
        _ = IPC.send(["cmd": "alert", "kind": sub == "call" ? "call" : "notify"])
        print("Triggered \(sub == "call" ? "call" : "notification") alert.")
    case "clear":
        _ = IPC.send(["cmd": "clear"]); print("Cleared.")
    case "show":
        let al = try store.activeProfile().alerts
        func show(_ t: String, _ s: AlertStyle) {
            print("  \(bold(t)): pattern \(s.pattern.rawValue), keys \(s.keys), color \(swatch(s.color))\(s.secondColor.map { ", second \(swatch($0))" } ?? ""), \(s.duration)s, persist \(s.persist ? "on (\(s.persistKeys))" : "off")")
        }
        print("Watch macOS notifications: \(al.watchNotifications ? "on" : "off")")
        show("notify", al.notification); show("call  ", al.call)
        print("  call apps:     \(al.callApps.joined(separator: ", "))")
        print("  call keywords: \(al.callKeywords.joined(separator: ", "))")
        print("  ignored apps:  \(al.ignoreApps.isEmpty ? "-" : al.ignoreApps.joined(separator: ", "))")
        print("  only apps:     \(al.onlyApps.isEmpty ? "(all)" : al.onlyApps.joined(separator: ", "))")
        print("  dismiss on keypress: \(al.dismissOnKeypress ? "on" : "off")")
        if let e = NotificationWatcher.checkAccess() { print(dim("  (from this terminal: \(e))")) }
    case "watch":
        let v = try onOff(try a.require("on|off"))
        try store.updateActive { $0.alerts.watchNotifications = v }
        try commit(quiet: true); print("Watching notifications: \(v ? "on" : "off")")
    case "dismiss-on-keypress":
        let v = try onOff(try a.require("on|off"))
        try store.updateActive { $0.alerts.dismissOnKeypress = v }
        try commit(quiet: true); print("OK")
    case "set":
        let which = try a.require("notify|call"), field = try a.require("field"), value = try a.require("value")
        try store.updateActive { p in
            var s = which == "call" ? p.alerts.call : p.alerts.notification
            switch field {
            case "keys": _ = try KeyLayout.resolve(value); s.keys = value
            case "color": s.color = try color(value)
            case "second-color", "color2": s.secondColor = try color(value)
            case "pattern":
                guard let pt = AlertPattern(rawValue: value) else { throw ChromaError.invalid("Patterns: \(AlertPattern.allCases.map(\.rawValue).joined(separator: ", "))") }
                s.pattern = pt
            case "duration": guard let d = Double(value) else { throw ChromaError.invalid("Bad duration") }; s.duration = d
            case "persist": s.persist = try onOff(value)
            case "persist-keys": _ = try KeyLayout.resolve(value); s.persistKeys = value
            default: throw ChromaError.invalid("Fields: keys, color, second-color, pattern, duration, persist, persist-keys")
            }
            if which == "call" { p.alerts.call = s } else { p.alerts.notification = s }
        }
        try commit(quiet: true); print("Updated \(which) alert \(field) = \(value)")
    case "call-app", "ignore", "only", "keyword":
        let op = try a.require("add|remove"), v = try a.require("value")
        try store.updateActive { p in
            func edit(_ list: inout [String]) { if op == "add" { if !list.contains(v) { list.append(v) } } else { list.removeAll { $0 == v } } }
            switch sub {
            case "call-app": edit(&p.alerts.callApps)
            case "ignore": edit(&p.alerts.ignoreApps)
            case "only": edit(&p.alerts.onlyApps)
            default: edit(&p.alerts.callKeywords)
            }
        }
        try commit(quiet: true); print("OK")
    default:
        throw ChromaError.invalid("Usage: chroma alert show | notify | call | clear | watch on|off | set notify|call <field> <value> | call-app|ignore|only|keyword add|remove <value>")
    }
}

func installedBinaryPath() -> String {
    let p = CommandLine.arguments[0]
    let resolved = p.contains("/") ? URL(fileURLWithPath: p).resolvingSymlinksInPath().path
        : (Bundle.main.executablePath ?? p)
    return resolved
}

func cmdService(_ a: inout Args) throws {
    let sub = a.next() ?? "status"
    switch sub {
    case "run":
        let s = try Service()
        s.run()
    case "install":
        let bin = installedBinaryPath()
        if bin.contains("/.build/") { print("⚠️  Installing from the build folder. For a stable path run ./install.sh first.") }
        try LaunchAgent.install(binary: bin)
        print("Service installed and started (runs at login).")
        print("Binary: \(bin)")
        print("""

        Grant these permissions to that binary (System Settings → Privacy & Security):
          • Accessibility       → macros, remapped macro keys, typing effects (ripple/reactive/heatmap)
          • Full Disk Access    → notification & call alerts
        Use the “+” button and pick the file above (⌘⇧G lets you paste the path), then run `chroma service restart`.
        """)
    case "uninstall":
        LaunchAgent.uninstall(); print("Service removed.")
    case "restart":
        if !LaunchAgent.restart() { throw ChromaError.io("Restart failed. Is it installed? (chroma service install)") }
        print("Service restarted.")
    case "stop": LaunchAgent.stop(); print("Service stopped (starts again at next login; `chroma service start` to start now).")
    case "start": _ = LaunchAgent.start(); print("Service started.")
    case "status":
        if let s = IPC.send(["cmd": "status"]) {
            for (k, v) in s.sorted(by: { $0.key < $1.key }) where k != "ok" { print("  \(k): \(v)") }
        } else { print(LaunchAgent.isInstalled ? "Installed, not responding." : "Not installed.") }
    case "logs", "log":
        let (_, out) = (0, (try? String(contentsOf: store.logURL, encoding: .utf8)) ?? "(no log yet)")
        print(out.split(separator: "\n").suffix(40).joined(separator: "\n"))
    default: throw ChromaError.invalid("Usage: chroma service install | uninstall | start | stop | restart | status | logs")
    }
}

func cmdIdentify(_ a: inout Args) throws {
    let kb = try RazerKeyboard()
    defer { try? commit(quiet: true) }
    if let spec = a.next() {
        let keys = try KeyLayout.resolve(spec)
        var f = Frame(fill: RGB(0, 0, 30))
        for k in keys { f[k.row, k.col] = .white }
        try kb.showFrame(f)
        print("Lit \(keys.map(\.name).joined(separator: " ")) for 5 s"); sleep(5)
        return
    }
    print("Walking every key (Ctrl-C to stop). Check that the lit key matches the printed name.")
    for k in KeyLayout.keys {
        var f = Frame(fill: RGB(0, 0, 30)); f[k.row, k.col] = .white
        try kb.showFrame(f, fast: true)
        print("  \(k.name)  (row \(k.row), col \(k.col))"); fflush(stdout)
        usleep(450_000)
    }
}

func cmdKeytest(_ a: inout Args) throws {
    let driver = a.flag("driver-mode")
    let secs = Double(a.option("seconds") ?? "20") ?? 20
    let kb = try RazerKeyboard()
    let previous = (try? kb.deviceMode()) ?? 0
    if driver { try kb.setDeviceMode(0x03) }
    print("Press keys on the Razer keyboard (M1–M5, Fn combos…) for \(Int(secs)) s\(driver ? " [driver mode]" : "")…")
    defer { if driver { try? kb.setDeviceMode(previous) } }
    try KeyTest.run(seconds: secs)
}

func cmdSetting(_ a: inout Args) throws {
    var s = store.settings()
    guard let k = a.next() else {
        print("driver-mode: \(s.driverMode ? "on" : "off")   lights-off-when-display-sleeps: \(s.lightsOffWhenDisplaySleeps ? "on" : "off")"); return
    }
    let v = try onOff(try a.require("on|off"))
    switch k {
    case "driver-mode": s.driverMode = v
    case "lights-off-when-display-sleeps", "sleep-off": s.lightsOffWhenDisplaySleeps = v
    default: throw ChromaError.invalid("Settings: driver-mode, lights-off-when-display-sleeps")
    }
    try store.saveSettings(s)
    if k == "driver-mode", let kb = try? RazerKeyboard() { try kb.setDeviceMode(v ? 0x03 : 0x00) }
    try commit(quiet: true)
    print("\(k) = \(v ? "on" : "off")")
}

let help = """
\(bold("chroma")) — control your Razer BlackWidow Chroma on macOS

\(bold("Lighting"))
  chroma status                         keyboard, profile and service status
  chroma effect list                    list all effects
  chroma effect <name> [options]        e.g. effect wave --direction left
  chroma color <color>                  shortcut for a static color
  chroma off                            lights off
  chroma brightness [0-100]
  chroma key set <keys> <color>         per-key colors: key set wasd red / key set f1-f12 blue
  chroma key clear [keys|all] · key list
  chroma keys                           list key names and groups
  chroma identify [keys]                light keys to check the layout

\(bold("Keys & macros"))
  chroma remap <from> <to>              e.g. remap capslock esc (this keyboard only)
  chroma remap list · remove <key> · clear
  chroma macro set <key> <actions…>     actions: text:… keys:cmd+c delay:200 app:Safari shell:'…' url:…
  chroma macro list · remove <key> · run <key>
  chroma keytest [--driver-mode]        show raw key codes (for M1–M5 setup)

\(bold("Alerts"))
  chroma alert show                     current notification/call alert settings
  chroma alert notify | call | clear    trigger/test alerts (also usable from Shortcuts)
  chroma alert set notify keys f1-f12   fields: keys color second-color pattern duration persist persist-keys
  chroma alert call-app add <bundle-id> · keyword add "incoming call" · ignore add <bundle-id>

\(bold("Profiles"))
  chroma profile list · use <n> · new <n> [--from x|--blank] · show [n] · rename · delete
  chroma export [file] [--profile n …]  export profiles to JSON (default: all)
  chroma import <file> [--overwrite] [--activate]

\(bold("Background service"))
  chroma service install                start at login (needed for animations, macros, alerts)
  chroma service status · logs · restart · stop · uninstall
  chroma setting [driver-mode|lights-off-when-display-sleeps] [on|off]
  chroma apply                          re-send the active profile to the keyboard

Colors: names (red, cyan, purple, razer…), #ff8800, or 255,136,0
"""

// MARK: - main

var args = Args(Array(CommandLine.arguments.dropFirst()))
do {
    switch args.next() ?? "help" {
    case "status": try cmdStatus()
    case "effect", "effects": try cmdEffect(&args)
    case "color", "colour":
        var b = Args(["static", try args.require("color")]); try cmdEffect(&b)
    case "off": var b = Args(["off"]); try cmdEffect(&b)
    case "brightness", "bright": try cmdBrightness(&args)
    case "key": try cmdKey(&args)
    case "keys": cmdKeys()
    case "remap": try cmdRemap(&args)
    case "macro", "macros": try cmdMacro(&args)
    case "profile", "profiles": try cmdProfile(&args)
    case "export": try cmdExport(&args)
    case "import": try cmdImport(&args)
    case "alert", "alerts": try cmdAlert(&args)
    case "service", "daemon": try cmdService(&args)
    case "identify": try cmdIdentify(&args)
    case "keytest": try cmdKeytest(&args)
    case "setting", "settings": try cmdSetting(&args)
    case "apply": try commit(); print("Applied '\(store.settings().activeProfile)'.")
    case "help", "-h", "--help": print(help)
    case "version", "--version": print("chroma 1.0.0")
    case let other: throw ChromaError.invalid("Unknown command '\(other)'. Run `chroma help`.")
    }
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
