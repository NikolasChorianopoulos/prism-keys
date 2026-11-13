import AppKit
import Combine
import PrismCore
import SwiftUI

/// The menu bar icon and its dropdown panel. We manage these ourselves (instead of SwiftUI's
/// MenuBarExtra) so the dropdown gets proper rounded corners and a matching shadow.
@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: MenuPanel?
    private var hosting: NSHostingView<AnyView>?
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var fitSubscription: AnyCancellable?

    func install() {
        guard let button = item.button else { return }
        button.image = MenuBarIcon.image(active: false)
        button.toolTip = "Prism Keys"
        button.target = self
        button.action = #selector(toggle)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])

        AppModel.shared.$status
            .map(\.connected).removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in self?.item.button?.image = MenuBarIcon.image(active: connected) }
            .store(in: &bag)
    }

    var isOpen: Bool { panel?.isVisible == true }

    @objc func toggle() { isOpen ? close() : open() }

    func open() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        fitAndPosition()
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        item.button?.highlight(true)
        installMonitors()
        // The contents can change size (e.g. a warning banner): keep the panel fitted.
        fitSubscription = AppModel.shared.objectWillChange
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.fitAndPosition() }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        fitSubscription = nil
        item.button?.highlight(false)
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    private func makePanel() -> MenuPanel {
        let root = MenuView()
            .environmentObject(AppModel.shared)
            .environmentObject(UpdaterManager.shared)
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        self.hosting = hosting

        let panel = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 500),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false

        // System menu material with real rounded corners.
        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        background.addSubview(hosting)
        panel.contentView = background
        return panel
    }

    /// Sizes the panel to its contents and places it under the menu bar icon.
    private func fitAndPosition() {
        guard let panel, let hosting, let button = item.button, let buttonWindow = button.window else { return }
        let size = hosting.fittingSize
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
        let y = buttonFrame.minY - size.height - 5
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.invalidateShadow()
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        // Clicks in other apps close the menu.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.close() }
        }) { monitors.append(m) }
        // Clicks in our own other windows (except the color panel and popup menus) close it too; Esc closes it.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53, panel.isKeyWindow { self.close(); return nil }
                return event
            }
            let w = event.window
            if w === panel || w === self.item.button?.window || w is NSColorPanel
                || String(describing: type(of: w as Any)).contains("Menu") { return event }
            self.close()
            return event
        }) { monitors.append(m) }
    }
}

/// A borderless panel that can still take keyboard focus (for ⌘, ⌘Q and the profile picker).
final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The Settings window.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        StatusBarController.shared.close()
        if window == nil {
            let root = SettingsView()
                .environmentObject(AppModel.shared)
                .environmentObject(UpdaterManager.shared)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Prism Keys Settings"
            let hosting = NSHostingView(rootView: root)
            w.contentView = hosting
            w.setContentSize(hosting.fittingSize)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
