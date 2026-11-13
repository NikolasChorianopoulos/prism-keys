import AppKit
import PrismCore
import SwiftUI

@main
struct PrismKeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    @StateObject private var updater = UpdaterManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
                .environmentObject(updater)
        } label: {
            MenuBarLabel(connected: model.status.connected)
        }
        .menuBarExtraStyle(.window)

        Window("Prism Keys Settings", id: "settings") {
            SettingsView()
                .environmentObject(model)
                .environmentObject(updater)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = AppModel.shared
        Snapshot.runIfRequested()
    }

    /// prismkeys://alert/notify · alert/call · alert/clear · profile/<name> · effect/<name>
    /// Handy for Shortcuts and scripts: `open prismkeys://alert/notify`
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { Task { @MainActor in AppModel.shared.handleURL(url) } }
    }
}

/// Opens the settings window from anywhere (menu, URL, etc.).
enum WindowRouter {
    @MainActor static var openSettings: (() -> Void)?
}

/// The menu bar icon. It exists from launch, so it's where we grab `openWindow`.
struct MenuBarLabel: View {
    let connected: Bool
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Image(nsImage: MenuBarIcon.image(active: connected))
            .onAppear {
                WindowRouter.openSettings = {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                if !UserDefaults.standard.bool(forKey: "didOnboard"), !CommandLine.arguments.contains("--snapshot") {
                    UserDefaults.standard.set(true, forKey: "didOnboard")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { WindowRouter.openSettings?() }
                }
            }
    }
}
