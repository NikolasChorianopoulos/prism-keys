import Foundation

/// Persists profiles under ~/Library/Application Support/RazerChroma
public final class Store {
    public static let shared = Store()

    public let baseDir: URL
    public var profilesDir: URL { baseDir.appendingPathComponent("profiles") }
    public var settingsURL: URL { baseDir.appendingPathComponent("settings.json") }
    public var socketPath: String { baseDir.appendingPathComponent("service.sock").path }
    public var logURL: URL { baseDir.appendingPathComponent("service.log") }

    public struct Settings: Codable {
        public var activeProfile: String = "default"
        /// Puts the keyboard in "driver mode" so the M1–M5 keys report to the Mac.
        public var driverMode: Bool = false
        /// Turn the keyboard lights off while the Mac's display sleeps.
        public var lightsOffWhenDisplaySleeps: Bool = true
        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            activeProfile = try c.decodeIfPresent(String.self, forKey: .activeProfile) ?? "default"
            driverMode = try c.decodeIfPresent(Bool.self, forKey: .driverMode) ?? false
            lightsOffWhenDisplaySleeps = try c.decodeIfPresent(Bool.self, forKey: .lightsOffWhenDisplaySleeps) ?? true
        }
    }

    public struct ExportBundle: Codable {
        public var format = "razer-chroma-cli"
        public var version = 1
        public var exportedAt = ISO8601DateFormatter().string(from: Date())
        public var activeProfile: String?
        public var profiles: [Profile]
    }

    private init() {
        if let custom = ProcessInfo.processInfo.environment["CHROMA_HOME"] {
            baseDir = URL(fileURLWithPath: custom)
        } else {
            baseDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/RazerChroma")
        }
        try? FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e
    }()

    // MARK: settings

    public func settings() -> Settings {
        guard let d = try? Data(contentsOf: settingsURL), let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
        return s
    }

    public func saveSettings(_ s: Settings) throws {
        try encoder.encode(s).write(to: settingsURL, options: .atomic)
    }

    // MARK: profiles

    static func fileName(_ name: String) -> String {
        let safe = name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return String(safe) + ".json"
    }

    public func profileNames() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Profile.self, from: Data(contentsOf: $0)).name }
            .sorted()
    }

    public func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: profilesDir.appendingPathComponent(Store.fileName(name)).path)
    }

    public func load(_ name: String) throws -> Profile {
        let url = profilesDir.appendingPathComponent(Store.fileName(name))
        guard let d = try? Data(contentsOf: url) else {
            if name == "default" { let p = Profile(name: "default"); try save(p); return p }
            throw ChromaError.invalid("Profile '\(name)' not found. Run `chroma profile list`.")
        }
        do { return try JSONDecoder().decode(Profile.self, from: d) }
        catch { throw ChromaError.io("Profile '\(name)' is corrupt: \(error)") }
    }

    public func save(_ p: Profile) throws {
        try encoder.encode(p).write(to: profilesDir.appendingPathComponent(Store.fileName(p.name)), options: .atomic)
    }

    public func delete(_ name: String) throws {
        try FileManager.default.removeItem(at: profilesDir.appendingPathComponent(Store.fileName(name)))
    }

    public func activeProfile() throws -> Profile { try load(settings().activeProfile) }

    /// Loads, mutates and saves the active profile.
    @discardableResult
    public func updateActive(_ f: (inout Profile) throws -> Void) throws -> Profile {
        var p = try activeProfile()
        try f(&p)
        try save(p)
        return p
    }

    // MARK: import / export

    public func export(names: [String]?, to url: URL) throws -> Int {
        let list = try (names ?? profileNames()).map { try load($0) }
        let bundle = ExportBundle(activeProfile: settings().activeProfile, profiles: list)
        try encoder.encode(bundle).write(to: url, options: .atomic)
        return list.count
    }

    /// Returns (imported names, renamed pairs).
    public func importBundle(from url: URL, overwrite: Bool, activate: Bool) throws -> [String] {
        let data = try Data(contentsOf: url)
        var profiles: [Profile]
        var active: String?
        if let b = try? JSONDecoder().decode(ExportBundle.self, from: data) {
            profiles = b.profiles; active = b.activeProfile
        } else if let p = try? JSONDecoder().decode(Profile.self, from: data) {
            profiles = [p]; active = p.name
        } else {
            throw ChromaError.invalid("\(url.path) is not a chroma export file.")
        }
        var names: [String] = []
        var renamed: [String: String] = [:]
        for var p in profiles {
            if exists(p.name) && !overwrite {
                var i = 2
                while exists("\(p.name)-\(i)") { i += 1 }
                renamed[p.name] = "\(p.name)-\(i)"
                p.name = "\(p.name)-\(i)"
            }
            try save(p); names.append(p.name)
        }
        if activate, let a = active {
            var s = settings(); s.activeProfile = renamed[a] ?? a; try saveSettings(s)
        }
        return names
    }
}
