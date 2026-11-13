import AppKit
import ApplicationServices

/// Reads notification banners from the Notification Center UI via the Accessibility API.
public enum AXTree {
    static func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    static func str(_ e: AXUIElement, _ name: String) -> String? { attr(e, name) as? String }
    static func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

    static func notificationCenterApp() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    /// Structure only: roles/subroles/identifiers and text *lengths* (never the text itself).
    public static func dumpStructure() {
        guard let app = notificationCenterApp() else { log("diag-ax: Notification Center process not found"); return }
        var lines: [String] = []
        func walk(_ e: AXUIElement, _ depth: Int) {
            guard depth < 14, lines.count < 150 else { return }
            let role = str(e, kAXRoleAttribute) ?? "?"
            let sub = str(e, kAXSubroleAttribute) ?? ""
            let ident = str(e, kAXIdentifierAttribute) ?? ""
            let desc = str(e, kAXDescriptionAttribute)?.count ?? 0
            let title = str(e, kAXTitleAttribute)?.count ?? 0
            let value = (attr(e, kAXValueAttribute) as? String)?.count ?? 0
            let actions: [String] = {
                var names: CFArray?
                AXUIElementCopyActionNames(e, &names)
                return ((names as? [String]) ?? []).filter { !$0.hasPrefix("AXScroll") }
            }()
            lines.append(String(repeating: "  ", count: depth) + "\(role) \(sub) id=\(ident) desc#\(desc) title#\(title) value#\(value) actions=\(actions.count)")
            for c in children(e) { walk(c, depth + 1) }
        }
        let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        lines.append("windows: \(windows.count)")
        for w in windows { walk(w, 0) }
        log("diag-ax: Notification Center tree (\(lines.count) nodes)\n" + lines.joined(separator: "\n"))
    }
}

/// Watches the Notification Center UI for new banners/alerts (needs Accessibility only).
public final class AXNotificationWatcher {
    public var onNotification: ((NotificationWatcher.Note) -> Void)?
    public var onBannerGone: ((String) -> Void)?
    private let queue = DispatchQueue(label: "prismkeys.axnotifications")
    private var timer: DispatchSourceTimer?
    private var seen = Set<String>()
    private var primed = false

    public init() {}

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 0.2)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    struct Banner { let id: String; let note: NotificationWatcher.Note }

    private func poll() {
        guard AXIsProcessTrusted(), let app = AXTree.notificationCenterApp() else { return }
        let windows = (AXTree.attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        var found: [Banner] = []
        func walk(_ e: AXUIElement, _ depth: Int) {
            guard depth < 10, found.count < 50 else { return }
            let sub = AXTree.str(e, kAXSubroleAttribute) ?? ""
            if sub.hasPrefix("AXNotificationCenter") {
                if let b = Self.banner(e) { found.append(b) }
                return
            }
            for c in AXTree.children(e) { walk(c, depth + 1) }
        }
        for w in windows { walk(w, 0) }

        let ids = Set(found.map(\.id))
        let fresh = found.filter { !seen.contains($0.id) }
        for gone in seen.subtracting(ids) { onBannerGone?(gone) }
        seen = ids
        guard primed else { primed = true; return }       // ignore what was already on screen at launch
        guard !fresh.isEmpty, fresh.count <= 3 else { return } // many at once = the Notification Center panel was opened
        for b in fresh { onNotification?(b.note) }
    }

    static func banner(_ e: AXUIElement) -> Banner? {
        var title = "", subtitle = "", body = ""
        var buttons: [String] = []
        func collect(_ x: AXUIElement, _ depth: Int) {
            guard depth < 6 else { return }
            let ident = AXTree.str(x, kAXIdentifierAttribute) ?? ""
            let value = (AXTree.attr(x, kAXValueAttribute) as? String) ?? ""
            switch ident {
            case "title": title = value
            case "subtitle": subtitle = value
            case "body": body = value
            default: break
            }
            if AXTree.str(x, kAXRoleAttribute) == kAXButtonRole as String {
                buttons.append(AXTree.str(x, kAXTitleAttribute) ?? AXTree.str(x, kAXDescriptionAttribute) ?? "")
            }
            for c in AXTree.children(x) { collect(c, depth + 1) }
        }
        collect(e, 0)
        var actionNames: CFArray?
        AXUIElementCopyActionNames(e, &actionNames)
        let actions = ((actionNames as? [String]) ?? []).compactMap { a -> String? in
            // custom actions look like "Name:Accept\nTarget:…"
            guard a.hasPrefix("Name:") else { return nil }
            return String(a.dropFirst(5).prefix { $0 != "\n" })
        }
        let desc = AXTree.str(e, kAXDescriptionAttribute) ?? ""
        // The description reads "App name, title, body"
        var appName = desc
        if !title.isEmpty, let r = desc.range(of: ", \(title)") { appName = String(desc[..<r.lowerBound]) }
        else if let comma = desc.firstIndex(of: ",") { appName = String(desc[..<comma]) }
        // macOS reuses a banner for the next notification from the same app, so the
        // content is part of the identity.
        let id = (AXTree.str(e, kAXIdentifierAttribute) ?? "") + "|\(desc.hashValue)"
        let extra = (buttons + actions).joined(separator: " ")
        var note = NotificationWatcher.Note(app: appName, title: title, subtitle: subtitle, body: body, buttons: extra)
        note.bannerID = id
        return Banner(id: id, note: note)
    }
}
