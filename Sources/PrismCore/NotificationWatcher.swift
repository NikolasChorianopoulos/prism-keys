import AppKit
import Foundation
import SQLite3

/// Watches macOS Notification Center's database for newly delivered notifications.
/// Reading it requires "Full Disk Access" for the process (System Settings → Privacy & Security).
public final class NotificationWatcher {
    public struct Note {
        /// Bundle id (database watcher) or app display name (banner watcher)
        public let app: String
        public let title: String
        public let subtitle: String
        public let body: String
        /// Button / action titles on the banner (e.g. "Accept Decline" for calls)
        public var buttons: String = ""
        /// Set for on-screen banners, so we can tell when they go away.
        public var bannerID: String?
    }

    public var onNotification: ((Note) -> Void)?
    private var lastID: Int64 = -1
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "prismkeys.notifications")
    public private(set) var status = "not started"
    private var warned = false

    public init() {}

    public static func databasePath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = ["\(home)/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        if let dir = darwinUserDir() { candidates.append("\(dir)/com.apple.notificationcenter/db2/db") }
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates.first
    }

    static func darwinUserDir() -> String? {
        let (s, out) = Remapper.run("/usr/bin/getconf", ["DARWIN_USER_DIR"])
        return s == 0 ? out.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    /// Returns nil if readable, else an explanation.
    public static func checkAccess() -> String? {
        guard let path = databasePath() else { return "Notification database not found." }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK { return "Can't open notification database (grant Full Disk Access)." }
        if sqlite3_exec(db, "SELECT count(*) FROM record", nil, nil, nil) != SQLITE_OK {
            return "Can't read notification database (grant Full Disk Access): \(String(cString: sqlite3_errmsg(db)))"
        }
        return nil
    }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1.0)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    private func poll() {
        guard let path = NotificationWatcher.databasePath() else { status = "database not found"; return }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            setError("can't open database — grant Full Disk Access to Prism Keys"); return
        }
        sqlite3_busy_timeout(db, 200)
        if lastID < 0 {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id),0) FROM record", -1, &st, nil) == SQLITE_OK else {
                setError("can't read database — grant Full Disk Access to Prism Keys"); return
            }
            if sqlite3_step(st) == SQLITE_ROW { lastID = sqlite3_column_int64(st, 0) }
            sqlite3_finalize(st)
            status = "watching"; warned = false
            log("notifications: watching (last id \(lastID))")
            return
        }
        var st: OpaquePointer?
        let sql = "SELECT r.rec_id, IFNULL(a.identifier,''), r.data FROM record r LEFT JOIN app a ON a.app_id = r.app_id WHERE r.rec_id > ? ORDER BY r.rec_id"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { setError("query failed: \(String(cString: sqlite3_errmsg(db)))"); return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, lastID)
        while sqlite3_step(st) == SQLITE_ROW {
            lastID = max(lastID, sqlite3_column_int64(st, 0))
            var app = String(cString: sqlite3_column_text(st, 1))
            var title = "", subtitle = "", body = ""
            if let blob = sqlite3_column_blob(st, 2) {
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(st, 2)))
                if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    if app.isEmpty, let a = plist["app"] as? String { app = a }
                    if let req = plist["req"] as? [String: Any] {
                        title = req["titl"] as? String ?? ""
                        subtitle = req["subt"] as? String ?? ""
                        body = req["body"] as? String ?? ""
                    }
                }
            }
            onNotification?(Note(app: app, title: title, subtitle: subtitle, body: body))
        }
        status = "watching"
    }

    private func setError(_ s: String) {
        status = s
        if !warned { log("notifications: \(s)"); warned = true }
    }

    /// Logs the layout of the notification database (no notification content).
    public static func diagnose() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let group = "\(home)/Library/Group Containers/group.com.apple.usernoted"
        if let e = FileManager.default.enumerator(atPath: group) {
            var files: [String] = []
            while let f = e.nextObject() as? String { if files.count < 40 { files.append(f) } }
            log("diag: \(group) contains \(files)")
        } else { log("diag: can't list \(group)") }
        if let d = darwinUserDir() {
            let alt = "\(d)/com.apple.notificationcenter"
            log("diag: \(alt) exists=\(FileManager.default.fileExists(atPath: alt)) contents=\((try? FileManager.default.contentsOfDirectory(atPath: alt)) ?? [])")
        }
        guard let path = databasePath() else { log("diag: no db path"); return }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { log("diag: can't open \(path)"); return }
        var st: OpaquePointer?
        var tables: [String] = []
        if sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table'", -1, &st, nil) == SQLITE_OK {
            while sqlite3_step(st) == SQLITE_ROW { tables.append(String(cString: sqlite3_column_text(st, 0))) }
        }
        sqlite3_finalize(st)
        var counts: [String] = []
        for t in tables {
            if sqlite3_prepare_v2(db, "SELECT count(*) FROM \"\(t)\"", -1, &st, nil) == SQLITE_OK, sqlite3_step(st) == SQLITE_ROW {
                counts.append("\(t)=\(sqlite3_column_int64(st, 0))")
            }
            sqlite3_finalize(st)
        }
        log("diag: db \(path) tables: \(counts.joined(separator: ", "))")
        func shape(_ o: Any, _ depth: Int = 0) -> String {
            if depth > 3 { return "…" }
            if let a = o as? [Any] { return "array[\(a.count)] of \(a.first.map { shape($0, depth + 1) } ?? "-")" }
            if let d = o as? [String: Any] {
                return "dict{" + d.keys.sorted().map { "\($0): \(shape(d[$0]!, depth + 1))" }.joined(separator: ", ") + "}"
            }
            if o is Data { return "data(\((o as! Data).count))" }
            if o is String { return "string" }
            if o is NSNumber { return "number" }
            if o is Date { return "date" }
            return "\(type(of: o))"
        }
        var sizes: [Int] = []
        if sqlite3_prepare_v2(db, "SELECT app_id, length(list), typeof(list) FROM delivered", -1, &st, nil) == SQLITE_OK {
            while sqlite3_step(st) == SQLITE_ROW { sizes.append(Int(sqlite3_column_int64(st, 1))) }
            log("diag: delivered blob sizes \(sizes) type=\(sizes.isEmpty ? "-" : "")")
        } else { log("diag: size query failed: \(String(cString: sqlite3_errmsg(db)))") }
        sqlite3_finalize(st)
        if sqlite3_prepare_v2(db, "SELECT d.app_id, a.identifier, d.list FROM delivered d LEFT JOIN app a ON a.app_id = d.app_id WHERE length(d.list) > 0 ORDER BY length(d.list) DESC LIMIT 2", -1, &st, nil) != SQLITE_OK {
            log("diag: blob query failed: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            while sqlite3_step(st) == SQLITE_ROW {
                let n = Int(sqlite3_column_bytes(st, 2))
                guard let b = sqlite3_column_blob(st, 2) else { log("diag: nil blob"); continue }
                let data = Data(bytes: b, count: n)
                let head = data.prefix(8).map { String(format: "%02x", $0) }.joined()
                var fmt = PropertyListSerialization.PropertyListFormat.binary
                if let o = try? PropertyListSerialization.propertyList(from: data, format: &fmt) {
                    log("diag: delivered row bytes=\(n) plist: \(shape(o))")
                } else {
                    log("diag: delivered row bytes=\(n) not a plist, head=\(head)")
                }
            }
        }
        sqlite3_finalize(st)
        for t in ["delivered", "displayed", "requests", "app"] {
            var cols: [String] = []
            if sqlite3_prepare_v2(db, "PRAGMA table_info(\"\(t)\")", -1, &st, nil) == SQLITE_OK {
                while sqlite3_step(st) == SQLITE_ROW {
                    cols.append("\(String(cString: sqlite3_column_text(st, 1))):\(String(cString: sqlite3_column_text(st, 2)))")
                }
            }
            sqlite3_finalize(st)
            log("diag: \(t)(\(cols.joined(separator: ", ")))")
        }
    }

    /// Classifies a notification using the profile's alert settings. nil = ignore.
    public static func classify(_ n: Note, _ s: AlertSettings) -> Animator.AlertKind? {
        func matches(_ list: [String]) -> Bool { list.contains { appMatches($0, n.app) } }
        if matches(s.ignoreApps) { return nil }
        if n.app.lowercased().hasPrefix("prism keys") { return nil }
        let text = "\(n.title) \(n.subtitle) \(n.body)".lowercased()
        let buttons = n.buttons.lowercased()
        if matches(s.callApps) { return .call }
        if ["accept", "answer", "decline", "αποδοχή", "απόρριψη"].contains(where: { buttons.contains($0) }) { return .call }
        if s.callKeywords.contains(where: { !$0.isEmpty && text.contains($0.lowercased()) }) { return .call }
        if !s.onlyApps.isEmpty && !matches(s.onlyApps) { return nil }
        return .notify
    }

    /// True if `entry` (a bundle id or app name from the settings) refers to `app`
    /// (a bundle id from the database, or a display name from a banner).
    /// Banners can add words after the app's name (an incoming FaceTime/iPhone call shows as
    /// "FaceTime Notification"), so a name that *starts with* the app's name also matches.
    static func appMatches(_ entry: String, _ app: String) -> Bool {
        let e = entry.lowercased(), a = app.lowercased()
        if e == a { return true }
        for name in [e, displayName(forBundleID: entry)?.lowercased()].compactMap({ $0 }) where !name.contains(".") || name == e {
            if a == name || a.hasPrefix(name + " ") { return true }
        }
        return false
    }

    private static var nameCache: [String: String?] = [:]
    private static let cacheLock = NSLock()
    static func displayName(forBundleID id: String) -> String? {
        guard id.contains(".") else { return nil }
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = nameCache[id] { return cached }
        var name: String?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        nameCache[id] = name
        return name
    }
}
