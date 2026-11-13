import PrismCore
import SwiftUI

struct KeysTab: View {
    @EnvironmentObject var model: AppModel
    @Local private var selection: Set<String> = []
    @Local private var remapTarget = "esc"
    @Local private var showMKeyWizard = false

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

                GroupBox {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("M1–M5 macro keys").font(.headline)
                            Text(model.settings.mKeyUsages.count == 5 ? "Set up ✓  — the M-keys can run macros."
                                 : "macOS can't see the M-keys until they're set up once. This needs Input Monitoring access.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(model.settings.mKeyUsages.isEmpty ? "Set up M-keys…" : "Redo setup…") { showMKeyWizard = true }
                    }.padding(6)
                }
                summary
            }
        }
        .sheet(isPresented: $showMKeyWizard) { MKeyWizard().environmentObject(model) }
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
                if key.hasPrefix("m"), KeyLayout.key(key)?.usage == nil, model.settings.mKeyUsages[key] == nil {
                    Label("Set up the M-keys below so this macro can fire.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
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

/// Learns what M1–M5 send so they can be remapped/used for macros.
struct MKeyWizard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Local private var listener = HIDKeyListener()
    @Local private var captured: [String: UInt32] = [:]
    @Local private var step = 0
    @Local private var error: String?
    @Local private var lastSeen = ""
    private let names = ["m1", "m2", "m3", "m4", "m5"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up the M-keys").font(.title2.bold())
            if !HIDKeyListener.hasPermission {
                Text("Prism Keys needs **Input Monitoring** access to see what the M-keys send. Grant it, then reopen this window.")
                HStack {
                    Button("Request access") { HIDKeyListener.requestPermission() }
                    Button("Open System Settings") { Permissions.open("Privacy_ListenEvent") }
                }
            } else if step < names.count {
                Text("Press **\(names[step].uppercased())** on the keyboard (the column on the far left).").font(.title3)
                HStack(spacing: 10) {
                    ForEach(names.indices, id: \.self) { i in
                        Text(names[i].uppercased()).bold()
                            .frame(width: 44, height: 34)
                            .background(RoundedRectangle(cornerRadius: 6).fill(i < step ? Color.green.opacity(0.4) : i == step ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08)))
                    }
                }
                if !lastSeen.isEmpty { Text(lastSeen).font(.caption).foregroundStyle(.secondary) }
                Divider()
                Toggle("Driver mode", isOn: $model.settings.driverMode)
                Text("Nothing happens when you press M1? Turn on Driver mode and try again. In driver mode the keyboard reports the M-keys to the Mac. Check afterwards that Fn+F11/F12 brightness still works.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("All five M-keys are set up. Attach macros to them in Keys & Macros.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let e = error { Text(e).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Cancel") { listener.stop(); dismiss() }
                Spacer()
                if step >= names.count {
                    Button("Save") {
                        model.settings.mKeyUsages = captured
                        listener.stop(); dismiss()
                    }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: start)
        .onDisappear { listener.stop() }
    }

    private func start() {
        guard HIDKeyListener.hasPermission else { return }
        do {
            try listener.start { page, usage, pressed in
                guard pressed, step < names.count else { return }
                lastSeen = String(format: "Last key: page 0x%02X usage 0x%02X", page, usage)
                guard page == 0x07 else { return }
                if captured.values.contains(usage) { return }
                captured[names[step]] = usage
                step += 1
            }
        } catch { self.error = "\(error)" }
    }
}
