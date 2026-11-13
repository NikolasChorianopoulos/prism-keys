import Foundation
import SQLite3

/// Watches macOS Notification Center's database for newly delivered notifications.
/// Reading it requires "Full Disk Access" for the process (System Settings → Privacy & Security).
public final class NotificationWatcher {
    public struct Note { public let app: String; public let title: String; public let subtitle: String; public let body: String }

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

    /// Classifies a notification using the profile's alert settings. nil = ignore.
    public static func classify(_ n: Note, _ s: AlertSettings) -> Animator.AlertKind? {
        let app = n.app.lowercased()
        if s.ignoreApps.contains(where: { $0.lowercased() == app }) { return nil }
        let text = "\(n.title) \(n.subtitle) \(n.body)".lowercased()
        if s.callApps.contains(where: { $0.lowercased() == app }) { return .call }
        if s.callKeywords.contains(where: { !$0.isEmpty && text.contains($0.lowercased()) }) { return .call }
        if !s.onlyApps.isEmpty && !s.onlyApps.contains(where: { $0.lowercased() == app }) { return nil }
        return .notify
    }
}
