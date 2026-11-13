import PrismCore
import SwiftUI

struct AlertsTab: View {
    @EnvironmentObject var model: AppModel
    @Local private var fda = Permissions.fullDiskAccess

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Toggle("Light up the keyboard for notifications and incoming calls", isOn: $model.profile.alerts.watchNotifications)
                        .toggleStyle(.switch)
                    Spacer()
                }
                if !model.status.keyTap {
                    Banner(text: "Prism Keys sees notification banners through Accessibility access. Grant it to use alerts.",
                           action: "Grant") { Permissions.requestAccessibility() }
                } else {
                    Text("Alerts react to the notification banners macOS shows. Notifications that Focus or Do Not Disturb silences won't light the keyboard either."
                         + (fda ? "" : " Optional: Full Disk Access lets Prism Keys catch some notifications from macOS's notification list as well."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                AlertStyleEditor(title: "Notifications", symbol: "bell.fill",
                                 style: $model.profile.alerts.notification) { model.engine.trigger(.notify) }
                AlertStyleEditor(title: "Incoming calls", symbol: "phone.fill",
                                 style: $model.profile.alerts.call) { model.engine.trigger(.call) }
                GroupBox("Rules") {
                    VStack(alignment: .leading, spacing: 8) {
                        ListField(label: "Apps whose notifications are calls", hint: "bundle IDs, e.g. com.apple.facetime",
                                  values: $model.profile.alerts.callApps)
                        ListField(label: "Words that mean a call", hint: "e.g. incoming call, is calling",
                                  values: $model.profile.alerts.callKeywords)
                        ListField(label: "Ignore these apps", hint: "bundle IDs, e.g. com.apple.Music",
                                  values: $model.profile.alerts.ignoreApps)
                        ListField(label: "Only alert for these apps", hint: "empty = all apps",
                                  values: $model.profile.alerts.onlyApps)
                        Toggle("Stop the alert when I press any key", isOn: $model.profile.alerts.dismissOnKeypress)
                        Text("Tip: trigger alerts from Shortcuts or scripts with  open prismkeys://alert/notify  ·  /call  ·  /clear")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    .padding(6)
                }
            }
        }
        .onAppear { fda = Permissions.fullDiskAccess }
    }
}

struct AlertStyleEditor: View {
    let title: String
    let symbol: String
    @Binding var style: AlertStyle
    let test: () -> Void
    @Local private var keysText = ""
    @Local private var keysError = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(title, systemImage: symbol).font(.headline)
                    Spacer()
                    Button("Test", action: test)
                }
                HStack {
                    Picker("Pattern", selection: $style.pattern) {
                        Text("Sweep").tag(AlertPattern.sweep)
                        Text("Flash").tag(AlertPattern.flash)
                        Text("Pulse").tag(AlertPattern.pulse)
                        Text("Strobe").tag(AlertPattern.strobe)
                        Text("Solid").tag(AlertPattern.solid)
                    }.frame(width: 180)
                    ColorPicker("Color", selection: $style.color.color, supportsOpacity: false).fixedSize()
                    if style.pattern == .pulse || style.pattern == .strobe {
                        ColorPicker("Second", selection: Binding(get: { (style.secondColor ?? .black).color },
                                                                 set: { style.secondColor = RGB($0) }), supportsOpacity: false).fixedSize()
                    }
                    Spacer()
                    Stepper("\(Int(style.duration)) s", value: $style.duration, in: 1...120, step: 1).fixedSize()
                }
                HStack {
                    Text("Keys")
                    TextField("e.g. f1-f12, logo, all", text: $keysText, onCommit: commitKeys)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                        .foregroundStyle(keysError ? .red : .primary)
                    Text("names, groups (all, fkeys, numbers, macro…) or ranges").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Toggle("Afterwards, keep a reminder glowing on", isOn: $style.persist)
                    TextField("logo", text: $style.persistKeys).textFieldStyle(.roundedBorder).frame(width: 120).disabled(!style.persist)
                    Text("until you press a key").foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
        .onAppear { keysText = style.keys }
    }

    private func commitKeys() {
        if (try? KeyLayout.resolve(keysText)) != nil { style.keys = keysText; keysError = false } else { keysError = true }
    }
}

struct ListField: View {
    let label: String
    let hint: String
    @Binding var values: [String]
    @Local private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.callout)
            TextField(hint, text: $text, onCommit: { values = parse(text) })
                .textFieldStyle(.roundedBorder)
                .onAppear { text = values.joined(separator: ", ") }
                .onChange(of: text) { _, new in values = parse(new) }
        }
    }

    private func parse(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
