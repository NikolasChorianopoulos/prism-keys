import AppKit
import PrismCore
import SwiftUI

@main
struct PrismKeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // The menu bar icon, dropdown and Settings window are managed by StatusBarController and
        // SettingsWindowController. SwiftUI still needs one scene: this one is never shown.
        MenuBarExtra("Prism Keys", isInserted: .constant(false)) { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { SettingsWindowController.shared.show() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        KeyboardPalette.install()
        MainActor.assumeIsolated {
            _ = AppModel.shared
            WindowRouter.openSettings = { SettingsWindowController.shared.show() }
            let snapshot = CommandLine.arguments.contains("--snapshot")
            if !snapshot {
                StatusBarController.shared.install()
                if !UserDefaults.standard.bool(forKey: "didOnboard") {
                    UserDefaults.standard.set(true, forKey: "didOnboard")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { SettingsWindowController.shared.show() }
                }
            }
            Snapshot.runIfRequested()
        }
    }

    /// Reopening the app (e.g. double-clicking it in Applications) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { SettingsWindowController.shared.show() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.flushSave()
            AppModel.shared.engine.shutdown()
        }
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
