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
                        PermissionRow(granted: perms.ax, title: "Accessibility", detail: "Macros, notification & call alerts, typing effects (Ripple, Heatmap)") {
                            Permissions.requestAccessibility()
                        }
                        PermissionRow(granted: perms.fda, title: "Full Disk Access", detail: "Optional: a second way to catch notifications (reads macOS's notification list)") {
                            Permissions.open("Privacy_AllFiles")
                        }
                        PermissionRow(granted: perms.im, title: "Input Monitoring", detail: "M1–M5 macro keys (and the Fn shortcuts while they're enabled)") {
                            RazerInputListener.requestPermission(); Permissions.open("Privacy_ListenEvent")
                        }
                        Text("Basic lighting needs no permissions. When macOS offers to “Quit & Reopen” after you grant something, you can pick Later: Prism Keys notices new permissions on its own (Input Monitoring is the exception and needs a reopen).")
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
                        Toggle("Share Caps Lock between the Razer and the Mac's keyboard", isOn: $model.settings.shareCapsLock)
                        Toggle("Windows-style Home, End, Page Up and Page Down on the Razer (move the cursor)", isOn: $model.settings.windowsNavigation)
                        Toggle("Num Lock key switches the numpad between numbers and arrows/navigation (like Windows)", isOn: $model.settings.numLockEmulation)
                        Text("When off, the key works as the Mac's “Clear” key (e.g. in Calculator).")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("If the keyboard flickers on bright colors (especially white), it isn't getting enough power, often because of a USB hub. Lower this, or plug the keyboard straight into the Mac.")
                            .font(.caption).foregroundStyle(.secondary)
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
