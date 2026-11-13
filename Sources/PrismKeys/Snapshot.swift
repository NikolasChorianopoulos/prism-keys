import AppKit
import SwiftUI

/// Developer aid: `PrismKeys --snapshot <dir>` renders the main views to PNGs and quits.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel.shared, updater = UpdaterManager.shared
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            render(MenuView(), "menu", dir, model, updater)
            for tab in ["lighting", "keys", "alerts", "profiles", "general"] {
                render(SettingsView(initialTab: tab), "settings-\(tab)", dir, model, updater)
            }
            exit(0)
        }
    }

    static func render<V: View>(_ v: V, _ name: String, _ dir: URL, _ model: AppModel, _ updater: UpdaterManager) {
        let host = NSHostingView(rootView: v.environmentObject(model).environmentObject(updater))
        let size = host.fittingSize
        let win = NSWindow(contentRect: NSRect(origin: NSPoint(x: -6000, y: -6000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = NSColor.windowBackgroundColor
        win.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        win.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        var rep: NSBitmapImageRep?
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(win.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
            rep = NSBitmapImageRep(cgImage: cg)
        } else if let r = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: r); rep = r
        }
        win.orderOut(nil)
        guard let rep else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
