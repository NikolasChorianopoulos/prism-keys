import PrismCore
import SwiftUI

struct KeysTab: View {
    @EnvironmentObject var model: AppModel
    @Local private var selection: Set<String> = []
    @Local private var remapTarget = "esc"

    private var selectedKey: String? { selection.count == 1 ? selection.first : nil }

    static let targets: [String] = KeyLayout.keys.filter { $0.usage != nil }.map(\.name)
        + KeyLayout.extraTargets.keys.filter { $0 != "rwin" }.sorted()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pick a key, then remap it or give it a macro. Changes only affect this keyboard, not your Mac's built-in one.")
                    .font(.callout).foregroundStyle(.secondary)
                KeyboardView(colorFor: { name in
                    if model.profile.macros[name] != nil { return Color.purple.opacity(0.8) }
                    if model.profile.remaps[name] != nil { return Color.teal.opacity(0.8) }
                    return nil
                }, selection: Binding(get: { selection }, set: { selection = $0.count > 1 ? [$0.first!] : $0 }),
                   badgeFor: { name in
                    if model.profile.macros[name] != nil { return "M" }
                    if let r = model.profile.remaps[name] { return "→" + VisualLayout.label(r) }
                    return nil
                })

                if let key = selectedKey {
                    GroupBox { KeyDetail(key: key, remapTarget: $remapTarget).padding(6) }
                } else {
                    GroupBox {
                        HStack {
                            Image(systemName: "hand.point.up.left")
                            Text("Select a key above to remap it or attach a macro.")
                            Spacer()
                        }.foregroundStyle(.secondary).padding(6)
                    }
                }

                MKeysBox()
                summary
            }
        }
    }

    private var summary: some View {
        GroupBox("All assignments") {
            VStack(alignment: .leading, spacing: 4) {
                if model.profile.remaps.isEmpty && model.profile.macros.isEmpty {
                    Text("None yet").foregroundStyle(.secondary)
                }
                ForEach(model.profile.remaps.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    HStack {
                        Text(VisualLayout.label(k)).bold(); Image(systemName: "arrow.right"); Text(VisualLayout.label(v))
                        Spacer()
                        Button { model.profile.remaps[k] = nil } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
                ForEach(model.profile.macros.sorted(by: { $0.key < $1.key }), id: \.key) { k, m in
                    HStack {
                        Text(VisualLayout.label(k)).bold(); Image(systemName: "bolt.fill").foregroundStyle(.purple)
                        Text(m.actions.map(describe).joined(separator: " → ")).lineLimit(1).foregroundStyle(.secondary)
                        Spacer()
                        Button { model.profile.macros[k] = nil } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

func describe(_ a: MacroAction) -> String {
    switch a.type {
    case .text: return "type “\(a.value)”"
    case .keys: return a.value
    case .delay: return "wait \(a.value) ms"
    case .app: return "open \(a.value)"
    case .shell: return "run \(a.value)"
    case .url: return a.value
    }
}

struct KeyDetail: View {
    @EnvironmentObject var model: AppModel
    let key: String
    @Binding var remapTarget: String

    private enum Mode: String { case normal, remap, macro }

    private var mode: Mode {
        if model.profile.macros[key] != nil { return .macro }
        if model.profile.remaps[key] != nil { return .remap }
        return .normal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Key: \(VisualLayout.label(key))").font(.headline)
                Spacer()
                Picker("", selection: Binding(get: { mode }, set: { setMode($0) })) {
                    Text("Default").tag(Mode.normal)
                    Text("Remap").tag(Mode.remap)
                    Text("Macro").tag(Mode.macro)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
            switch mode {
            case .normal:
                Text("This key works normally.").foregroundStyle(.secondary)
            case .remap:
                HStack {
                    Text("Acts as")
                    Picker("", selection: Binding(get: { model.profile.remaps[key] ?? "esc" }, set: { model.profile.remaps[key] = $0 })) {
                        ForEach(KeysTab.targets, id: \.self) { Text(VisualLayout.label($0) + (VisualLayout.labels[$0] != nil ? "  (\($0))" : "")).tag($0) }
                    }.labelsHidden().frame(width: 220)
                    Spacer()
                }
            case .macro:
                MacroEditor(macro: Binding(get: { model.profile.macros[key] ?? Macro(actions: []) },
                                           set: { model.profile.macros[key] = $0 }), keyName: key)
                if Remapper.isDirect(key) && !model.status.mKeysActive {
                    Label("Turn on “Enable M1–M5 keys” below so this macro can fire.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
                if !model.status.keyTap {
                    Banner(text: "Macros need Accessibility access for Prism Keys.", action: "Grant") { Permissions.requestAccessibility() }
                }
            }
        }
    }

    private func setMode(_ m: Mode) {
        switch m {
        case .normal: model.profile.remaps[key] = nil; model.profile.macros[key] = nil
        case .remap: model.profile.macros[key] = nil; model.profile.remaps[key] = remapTarget
        case .macro:
            model.profile.remaps[key] = nil
            model.profile.macros[key] = Macro(actions: [MacroAction(type: .text, value: "Hello!")])
        }
    }
}

struct MacroEditor: View {
    @Binding var macro: Macro
    let keyName: String
    @Local private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(macro.actions.indices, id: \.self) { i in
                HStack {
                    Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary).frame(width: 20)
                    Picker("", selection: $macro.actions[i].type) {
                        Text("Type text").tag(MacroAction.Kind.text)
                        Text("Shortcut").tag(MacroAction.Kind.keys)
                        Text("Wait (ms)").tag(MacroAction.Kind.delay)
                        Text("Open app").tag(MacroAction.Kind.app)
                        Text("Open URL").tag(MacroAction.Kind.url)
                        Text("Shell command").tag(MacroAction.Kind.shell)
                    }.labelsHidden().frame(width: 130)
                    TextField(placeholder(macro.actions[i].type), text: $macro.actions[i].value)
                        .textFieldStyle(.roundedBorder)
                    if macro.actions[i].type == .keys, !macro.actions[i].value.isEmpty,
                       macro.actions[i].value.split(separator: " ").contains(where: { MacroRunner.parseCombo(String($0)) == nil }) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("Unknown key in shortcut")
                    }
                    Button { if i > 0 { macro.actions.swapAt(i, i - 1) } } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(i == 0)
                    Button { macro.actions.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            HStack {
                Button { macro.actions.append(MacroAction(type: .keys, value: "")) } label: { Label("Add step", systemImage: "plus") }
                Spacer()
                Text("Shortcut examples: cmd+c · cmd+shift+4 · ctrl+left · enter · f5").font(.caption).foregroundStyle(.secondary)
                Button(testing ? "Running in 3 s…" : "Test") {
                    testing = true
                    let m = macro
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MacroRunner().run(m, name: keyName); testing = false }
                }.disabled(testing)
            }
        }
    }

    private func placeholder(_ k: MacroAction.Kind) -> String {
        switch k {
        case .text: return "Text to type"
        case .keys: return "e.g. cmd+shift+4"
        case .delay: return "milliseconds, e.g. 200"
        case .app: return "App name, e.g. Safari"
        case .url: return "https://…"
        case .shell: return "e.g. say hello"
        }
    }
}

struct MKeysBox: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Enable M1–M5 keys").font(.headline)
                        Text("Switches the keyboard to driver mode so the M-keys reach Prism Keys. Prism Keys then also handles the Fn shortcuts while it's running: F1–F3 volume, F5–F7 media, F9 record a macro, F10 gaming mode, F11/F12 brightness, Pause sleep. Quitting Prism Keys gives them back to the keyboard.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $model.settings.driverMode).toggleStyle(.switch).labelsHidden()
                }
                if model.settings.driverMode && !model.status.mKeysActive {
                    Banner(text: "Needs Input Monitoring access for Prism Keys, then reopen the app.", action: "Grant") {
                        RazerInputListener.requestPermission(); Permissions.open("Privacy_ListenEvent")
                    }
                } else if model.status.mKeysActive {
                    Label("Active. Press an M-key to run its macro.", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
                    Text("Quick recording: press Fn+F9 (the M light turns on), type your keys, press Fn+F9 again, then press the key that should play it back (Esc cancels).")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(6)
        }
    }
}
