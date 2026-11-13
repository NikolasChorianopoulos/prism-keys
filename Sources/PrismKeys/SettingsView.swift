import PrismCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Local private var tab: String
    init(initialTab: String = "lighting") { _tab = Local(wrappedValue: initialTab) }

    var body: some View {
        TabView(selection: $tab) {
            LightingTab().tabItem { Label("Lighting", systemImage: "paintbrush") }.tag("lighting")
            KeysTab().tabItem { Label("Keys & Macros", systemImage: "command.square") }.tag("keys")
            AlertsTab().tabItem { Label("Alerts", systemImage: "bell.badge") }.tag("alerts")
            ProfilesTab().tabItem { Label("Profiles", systemImage: "person.2.crop.square.stack") }.tag("profiles")
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
        }
        .padding(20)
        .frame(width: 760, height: 600)
        .alert("Prism Keys", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

// MARK: - Lighting

struct LightingTab: View {
    @EnvironmentObject var model: AppModel
    @Local private var selection: Set<String> = []
    @Local private var paint = RGB(255, 0, 0)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AlertClashWarning()
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker("Effect", selection: Binding(get: { model.profile.effect.type }, set: { model.selectEffect($0) })) {
                                ForEach(EffectType.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                            }
                            .frame(width: 240)
                            Spacer()
                            Image(systemName: "sun.max").foregroundStyle(.secondary)
                            Slider(value: Binding(get: { Double(model.profile.brightness) }, set: { model.profile.brightness = Int($0) }), in: 0...100)
                                .frame(width: 160)
                            Text("\(model.profile.brightness)%").monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                        Text(model.profile.effect.type.summary).font(.callout).foregroundStyle(.secondary)
                        EffectOptions()
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Per-key colors").font(.headline)
                            Text("Click a key, ⌘/⇧-click for more").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(selection.count) selected").font(.caption).foregroundStyle(.secondary)
                        }
                        KeyboardView(colorFor: previewColor, selection: $selection)
                        HStack(spacing: 6) {
                            Text("Select:").font(.caption).foregroundStyle(.secondary)
                            ForEach(["wasd", "arrows", "fkeys", "numbers", "letters", "numpad", "macro", "all"], id: \.self) { g in
                                Button(g == "fkeys" ? "F-keys" : g == "wasd" ? "WASD" : g.capitalized) {
                                    selection = Set(KeyLayout.groups[g] ?? [])
                                }
                                .controlSize(.small)
                            }
                            Button("None") { selection = [] }.controlSize(.small)
                        }
                        HStack {
                            ColorPicker("Color", selection: $paint.color, supportsOpacity: false).fixedSize()
                            Button("Paint selected") {
                                for k in selection { model.profile.keyColors[k] = paint }
                            }.disabled(selection.isEmpty)
                            Button("Turn off selected") {
                                for k in selection { model.profile.keyColors[k] = .black }
                            }.disabled(selection.isEmpty)
                            Button("Reset selected") {
                                for k in selection { model.profile.keyColors[k] = nil }
                            }.disabled(selection.isEmpty)
                            Spacer()
                            Button("Blink selected") { model.engine.identify(selection.compactMap { KeyLayout.key($0) }) }
                                .disabled(selection.isEmpty)
                                .help("Flash these keys on the real keyboard to check the layout")
                            Button("Reset all", role: .destructive) { model.profile.keyColors = [:] }
                                .disabled(model.profile.keyColors.isEmpty)
                        }
                        Text("Custom key colors are drawn on top of the effect. With Static or Off they run on the keyboard itself; with other effects Prism Keys animates them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(6)
                }
            }
        }
    }

    private func previewColor(_ name: String) -> Color? {
        if let c = model.profile.keyColors[name] { return c.color }
        let e = model.profile.effect
        switch e.type {
        case .static: return (e.color ?? .white).color
        case .off: return nil
        case .wave, .spectrum, .rainbow:
            if let k = KeyLayout.key(name) { return RGB.hsv(Double(k.col + k.row) / 26, 0.85, 0.9).color }
            return nil
        case .gradient:
            let cols = (e.colors?.count ?? 0) >= 2 ? e.colors! : [RGB(255, 0, 120), RGB(0, 120, 255)]
            guard let k = KeyLayout.key(name) else { return nil }
            let x = Double(k.col) / 21 * Double(cols.count - 1)
            let i = min(Int(x), cols.count - 2)
            return cols[i].mix(cols[i + 1], x - Double(i)).color
        default:
            return (e.background ?? e.color ?? e.colors?.first)?.scaled(e.background == nil ? 0.35 : 1).color
        }
    }
}

struct EffectOptions: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let t = model.profile.effect.type
        VStack(alignment: .leading, spacing: 8) {
            switch t {
            case .static, .reactive, .ripple:
                ColorPicker("Color", selection: optionalColor(\.color, default: RGB(0, 255, 0)), supportsOpacity: false).fixedSize()
            case .breathing, .starlight, .gradient:
                ColorList(colors: Binding(get: { model.profile.effect.colors ?? [] }, set: { model.profile.effect.colors = $0 }),
                          max: t == .breathing ? 2 : 6,
                          emptyHint: t == .gradient ? "Needs at least 2 colors" : "No colors = random colors")
            default: EmptyView()
            }
            if t == .reactive || t == .ripple || t == .starlight {
                HStack {
                    Toggle("Background", isOn: Binding(get: { model.profile.effect.background != nil },
                                                       set: { model.profile.effect.background = $0 ? RGB(0, 0, 40) : nil }))
                    if model.profile.effect.background != nil {
                        ColorPicker("", selection: optionalColor(\.background, default: RGB(0, 0, 40)), supportsOpacity: false).labelsHidden()
                    }
                }
                .fixedSize()
                if t == .reactive && model.profile.effect.background != nil {
                    Text("A background color makes Reactive run in Prism Keys instead of on the keyboard.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if t.hasSpeed {
                HStack {
                    Text(t == .reactive ? "Fade time" : "Speed")
                    Slider(value: Binding(get: { Double(model.profile.effect.speed ?? (t == .reactive ? 2 : 5)) },
                                          set: { model.profile.effect.speed = Int($0.rounded()) }),
                           in: 1...(t == .reactive ? 4 : 10), step: 1).frame(width: 220)
                }
            }
            if t == .wave {
                Picker("Direction", selection: Binding(get: { model.profile.effect.direction ?? "right" }, set: { model.profile.effect.direction = $0 })) {
                    Text("← Left").tag("left"); Text("Right →").tag("right")
                }.pickerStyle(.segmented).frame(width: 220)
            }
        }
    }

    private func optionalColor(_ kp: WritableKeyPath<Effect, RGB?>, default d: RGB) -> Binding<Color> {
        Binding(get: { (model.profile.effect[keyPath: kp] ?? d).color },
                set: { model.profile.effect[keyPath: kp] = RGB($0) })
    }
}

struct ColorList: View {
    @Binding var colors: [RGB]
    let max: Int
    let emptyHint: String

    var body: some View {
        HStack(spacing: 8) {
            Text("Colors")
            ForEach(colors.indices, id: \.self) { i in
                HStack(spacing: 2) {
                    ColorPicker("", selection: Binding(get: { colors[i].color }, set: { colors[i] = RGB($0) }), supportsOpacity: false).labelsHidden()
                    Button { colors.remove(at: i) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            if colors.count < max {
                Button { colors.append(RGB.hsv(Double(colors.count) * 0.3, 1, 1)) } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.plain)
            }
            if colors.isEmpty { Text(emptyHint).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
