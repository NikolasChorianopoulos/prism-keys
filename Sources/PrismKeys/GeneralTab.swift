import Combine
import PrismCore
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updater: UpdaterManager
    @Local private var perms = (ax: false, fda: false, im: false)
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(nsImage: AppIconImage.small).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Prism Keys").font(.title2.bold())
                        Text("Version \(UpdaterManager.version)").foregroundStyle(.secondary)
                        Text(model.status.connected ? "\(model.status.model ?? "") · firmware \(model.status.firmware ?? "?")" : "Keyboard not connected")
                            .font(.callout).foregroundStyle(model.status.connected ? Color.green : .secondary)
                    }
                    Spacer()
                }

                GroupBox("Startup") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Open Prism Keys at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                        Toggle("Turn keyboard lights off when the display sleeps", isOn: $model.settings.lightsOffWhenDisplaySleeps)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }

                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 8) {
                        PermissionRow(granted: perms.ax, title: "Accessibility", detail: "Macros, typing effects (Ripple, Heatmap), stopping alerts with a key press") {
                            Permissions.requestAccessibility()
                        }
                        PermissionRow(granted: perms.fda, title: "Full Disk Access", detail: "Notification and incoming call alerts (reads macOS's notification list)") {
                            Permissions.open("Privacy_AllFiles")
                        }
                        PermissionRow(granted: perms.im, title: "Input Monitoring", detail: "Only for the one-time M1–M5 key setup") {
                            HIDKeyListener.requestPermission(); Permissions.open("Privacy_ListenEvent")
                        }
                        Text("Basic lighting needs no permissions. After granting Full Disk Access, quit and reopen Prism Keys.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(6)
                }

                GroupBox("Updates") {
                    VStack(alignment: .leading, spacing: 6) {
                        if updater.isConfigured {
                            Toggle("Check for updates automatically", isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                            Toggle("Download and install updates automatically", isOn: Binding(get: { updater.automaticallyDownloads }, set: { updater.automaticallyDownloads = $0 }))
                            HStack {
                                Button("Check Now") { updater.checkForUpdates() }
                                if let d = updater.lastCheck { Text("Last checked \(d.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                            }
                        } else {
                            Text("Updates aren't set up in this build (development build).").foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }

                GroupBox("Advanced") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Maximum brightness")
                            Slider(value: Binding(get: { Double(model.settings.maxBrightness) },
                                                  set: { model.settings.maxBrightness = Int($0) }), in: 30...100, step: 5)
                                .frame(width: 200)
                            Text("\(model.settings.maxBrightness)%").monospacedDigit()
                        }
                        Text("If the keyboard flickers on bright colors (especially white), it isn't getting enough power, often because of a USB hub. Lower this, or plug the keyboard straight into the Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Driver mode (makes the keyboard report M1–M5 to the Mac)", isOn: $model.settings.driverMode)
                        HStack {
                            Button("Open data folder") { NSWorkspace.shared.open(model.store.baseDir) }
                            Button("Open log") { NSWorkspace.shared.open(model.store.logURL) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }

                Text("Prism Keys is an independent project and isn't affiliated with or endorsed by Razer Inc. Razer, BlackWidow and Chroma are trademarks of Razer Inc.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        perms = (Permissions.accessibility, Permissions.fullDiskAccess, Permissions.inputMonitoring)
    }
}

struct PermissionRow: View {
    let granted: Bool
    let title: String
    let detail: String
    let action: () -> Void
    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange).font(.title3)
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant…", action: action) }
        }
    }
}
