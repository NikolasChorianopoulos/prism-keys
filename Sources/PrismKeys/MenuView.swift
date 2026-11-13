import PrismCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updater: UpdaterManager
    @Environment(\.openWindow) private var openWindow

    private let quickColors: [RGB] = [RGB(255, 0, 0), RGB(255, 80, 0), RGB(255, 200, 0), RGB(0, 255, 0),
                                      RGB(0, 255, 255), RGB(0, 80, 255), RGB(140, 0, 255), RGB(255, 40, 140), .white]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let r = model.status.recording { RecordingBanner(state: r) }
            if let banner = permissionBanner { banner }
            Divider()
            profileRow
            brightnessRow
            effectGrid
            effectOptions
            Divider()
            toggles
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconImage.small)
                .resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Prism Keys").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(model.status.connected ? Color.green : Color.secondary).frame(width: 7, height: 7)
                    Text(model.status.connected ? "\(shortName(model.status.model)) · \(model.status.firmware ?? "")" : "Keyboard not connected")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { model.lightsOn }, set: { model.setLights($0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .help("Lights on/off")
        }
    }

    private var profileRow: some View {
        HStack {
            Label("Profile", systemImage: "person.crop.square").foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: Binding(get: { model.settings.activeProfile }, set: { model.switchProfile($0) })) {
                ForEach(model.profileNames, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(maxWidth: 170)
        }
    }

    private var brightnessRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.min").foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(model.profile.brightness) }, set: { model.profile.brightness = Int($0) }), in: 0...100)
            Image(systemName: "sun.max").foregroundStyle(.secondary)
            Text("\(model.profile.brightness)%").monospacedDigit().frame(width: 38, alignment: .trailing).font(.callout)
        }
    }

    private var effectGrid: some View {
        let types = EffectType.allCases.filter { $0 != .off }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(types, id: \.self) { t in
                let selected = model.profile.effect.type == t
                Button { model.selectEffect(t) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.symbol).font(.system(size: 15)).frame(height: 18)
                        Text(t.title).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .help(t.summary)
            }
        }
    }

    @ViewBuilder private var effectOptions: some View {
        let t = model.profile.effect.type
        VStack(alignment: .leading, spacing: 8) {
            if model.primaryColor != nil || t == .breathing || t == .starlight {
                HStack(spacing: 5) {
                    ForEach(quickColors, id: \.self) { c in
                        Button { model.primaryColor = c } label: {
                            Circle().fill(c.color).frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.primary.opacity(model.primaryColor == c ? 0.9 : 0.15), lineWidth: model.primaryColor == c ? 2 : 1))
                        }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 2)
                    ColorPicker("", selection: Binding(get: { (model.primaryColor ?? .white).color },
                                                       set: { model.primaryColor = RGB($0) }), supportsOpacity: false)
                        .labelsHidden()
                }
            }
            if t.hasSpeed {
                let maxSpeed = t == .reactive ? 4.0 : 10.0
                HStack {
                    Text(t == .reactive ? "Fade" : "Speed").font(.callout).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                    Slider(value: Binding(get: { Double(model.profile.effect.speed ?? (t == .reactive ? 2 : 5)) },
                                          set: { model.profile.effect.speed = Int($0.rounded()) }), in: 1...maxSpeed, step: 1)
                }
            }
            if t == .wave {
                Picker("Direction", selection: Binding(get: { model.profile.effect.direction ?? "right" },
                                                       set: { model.profile.effect.direction = $0 })) {
                    Image(systemName: "arrow.left").tag("left")
                    Image(systemName: "arrow.right").tag("right")
                }.pickerStyle(.segmented)
            }
            if !t.isHardware || !model.profile.keyColors.isEmpty {
                Label(model.profile.keyColors.isEmpty ? "Animated by Prism Keys while it's running" : "\(model.profile.keyColors.count) custom key colors on top",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var toggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Notification & call alerts", systemImage: "bell.badge")
                Spacer()
                Toggle("", isOn: $model.profile.alerts.watchNotifications).labelsHidden()
            }
            HStack {
                Label("M1–M5 macro keys", systemImage: "command.square")
                Spacer()
                Toggle("", isOn: $model.settings.driverMode).labelsHidden()
            }
            if model.status.mKeysActive {
                HStack {
                    Label("Gaming mode (Win/⌘ key off)", systemImage: "gamecontroller")
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.status.gameMode }, set: { model.engine.setGameMode($0) })).labelsHidden()
                }
            }
            HStack {
                Label("Turn off when display sleeps", systemImage: "moon.zzz")
                Spacer()
                Toggle("", isOn: $model.settings.lightsOffWhenDisplaySleeps).labelsHidden()
            }
            HStack(spacing: 8) {
                Button { model.engine.trigger(.notify) } label: { Label("Test notification", systemImage: "bell") }
                Button { model.engine.trigger(.call) } label: { Label("Test call", systemImage: "phone") }
            }
            .controlSize(.small)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            MenuRow(title: "Settings…", symbol: "gearshape", shortcut: "⌘,") { openSettings() }
            if updater.isConfigured {
                MenuRow(title: "Check for Updates…", symbol: "arrow.down.circle") { updater.checkForUpdates() }
            }
            MenuRow(title: "Quit Prism Keys", symbol: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
        }
        .background {
            Button("") { openSettings() }.keyboardShortcut(",", modifiers: .command).hidden()
            Button("") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command).hidden()
        }
    }

    private var permissionBanner: AnyView? {
        let t = model.profile.effect.type
        let needsTap = t.usesTyping || !model.profile.macros.isEmpty || (t == .reactive && !model.profile.keyColors.isEmpty)
        if needsTap && !model.status.keyTap {
            return AnyView(Banner(text: "Macros & typing effects need Accessibility access.", action: "Grant") { Permissions.requestAccessibility() })
        }
        if model.profile.alerts.watchNotifications && !model.status.keyTap {
            return AnyView(Banner(text: "Notification alerts need Accessibility access.", action: "Grant") { Permissions.requestAccessibility() })
        }
        return nil
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func shortName(_ s: String?) -> String { (s ?? "").replacingOccurrences(of: "Razer ", with: "") }
}

struct MenuRow: View {
    let title: String
    let symbol: String
    var shortcut: String? = nil
    let action: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                Spacer()
                if let s = shortcut { Text(s).foregroundStyle(.secondary).font(.callout) }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.accentColor.opacity(0.85) : .clear))
            .foregroundStyle(hover ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct Banner: View {
    let text: String
    let action: String
    let perform: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action, action: perform).controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

struct RecordingBanner: View {
    let state: String
    @Local private var pulse = false
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 9, height: 9).opacity(pulse ? 0.3 : 1)
                .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { pulse = true } }
            VStack(alignment: .leading, spacing: 1) {
                Text(state == "recording" ? "Recording macro…" : "Press the key that should play it").font(.callout.bold())
                Text(state == "recording" ? "Type what you want recorded, then press Fn+F9." : "Any key or M1–M5. Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
    }
}
