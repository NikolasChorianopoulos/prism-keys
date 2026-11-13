import Foundation
import Testing
@testable import PrismCore

/// Export → import round trips for profiles, using throwaway data folders.
@Suite struct ProfileTransferTests {
    func tempStore() -> Store {
        Store(baseDir: FileManager.default.temporaryDirectory.appendingPathComponent("prismkeys-test-\(UUID().uuidString)"))
    }

    /// A profile with every kind of setting changed from the defaults.
    func richProfile(_ name: String) -> Profile {
        var p = Profile(name: name)
        p.brightness = 42
        p.effect = Effect(type: .ripple, color: RGB(1, 2, 3), colors: [RGB(10, 20, 30), RGB(40, 50, 60)],
                          background: RGB(0, 0, 40), speed: 7, direction: "left")
        p.keyColors = ["w": RGB(255, 0, 0), "logo": RGB(0, 255, 0)]
        p.remaps = ["capslock": "esc"]
        p.macros = ["m1": Macro(actions: [MacroAction(type: .text, value: "Hello, “quotes” & ünïcödé ✓"),
                                          MacroAction(type: .delay, value: "200"),
                                          MacroAction(type: .keys, value: "cmd+shift+4")])]
        p.alerts.notification.color = RGB(9, 8, 7)
        p.alerts.notification.reminderColor = RGB(1, 1, 1)
        p.alerts.call.persist = false
        p.alerts.dimBackground = 30
        p.alerts.ignoreApps = ["com.apple.Music"]
        return p
    }

    @Test func exportAllThenImportIntoEmptyStoreKeepsEverything() throws {
        let a = tempStore(), b = tempStore()
        let work = richProfile("Work"), gaming = richProfile("Gaming")
        try a.save(work); try a.save(gaming)
        var s = a.settings(); s.activeProfile = "Gaming"; try a.saveSettings(s)

        let file = a.baseDir.appendingPathComponent("export.json")
        let count = try a.export(names: nil, to: file)
        #expect(count == 2)

        let imported = try b.importBundle(from: file, overwrite: false, activate: true)
        #expect(Set(imported) == ["Work", "Gaming"])
        #expect(try b.load("Work") == work)
        #expect(try b.load("Gaming") == gaming)
        #expect(b.settings().activeProfile == "Gaming")
    }

    @Test func exportSelectedOnlyContainsThatProfile() throws {
        let a = tempStore()
        try a.save(richProfile("One")); try a.save(richProfile("Two"))
        let file = a.baseDir.appendingPathComponent("one.json")
        #expect(try a.export(names: ["One"], to: file) == 1)
        let b = tempStore()
        #expect(try b.importBundle(from: file, overwrite: false, activate: false) == ["One"])
        #expect(b.profileNames() == ["One"])
    }

    @Test func importingAnExistingNameKeepsBothUnlessOverwriting() throws {
        let a = tempStore()
        var original = Profile(name: "Work"); original.brightness = 10
        try a.save(original)
        let file = a.baseDir.appendingPathComponent("work.json")
        let other = tempStore()
        try other.save(richProfile("Work"))
        _ = try other.export(names: ["Work"], to: file)

        #expect(try a.importBundle(from: file, overwrite: false, activate: false) == ["Work-2"])
        #expect(try a.load("Work").brightness == 10)          // original untouched
        #expect(try a.load("Work-2").brightness == 42)
        #expect(try a.importBundle(from: file, overwrite: false, activate: false) == ["Work-3"])

        #expect(try a.importBundle(from: file, overwrite: true, activate: false) == ["Work"])
        #expect(try a.load("Work").brightness == 42)
    }

    @Test func importingRenamedActiveProfileActivatesTheCopy() throws {
        let a = tempStore()
        try a.save(Profile(name: "Work"))
        let src = tempStore()
        try src.save(richProfile("Work"))
        var s = src.settings(); s.activeProfile = "Work"; try src.saveSettings(s)
        let file = src.baseDir.appendingPathComponent("x.json")
        _ = try src.export(names: nil, to: file)
        _ = try a.importBundle(from: file, overwrite: false, activate: true)
        #expect(a.settings().activeProfile == "Work-2")
    }

    @Test func aSingleProfileFileCanBeImported() throws {
        let a = tempStore()
        let p = richProfile("Solo")
        try a.save(p)
        let profileFile = a.profilesDir.appendingPathComponent("Solo.json")
        let b = tempStore()
        #expect(try b.importBundle(from: profileFile, overwrite: false, activate: false) == ["Solo"])
        #expect(try b.load("Solo") == p)
    }

    @Test func olderOrPartialFilesFillInDefaults() throws {
        let a = tempStore()
        let file = a.baseDir.appendingPathComponent("old.json")
        try ##"{"name":"Old","effect":{"type":"static","color":"#ff8800"}}"##.write(to: file, atomically: true, encoding: .utf8)
        #expect(try a.importBundle(from: file, overwrite: false, activate: false) == ["Old"])
        let p = try a.load("Old")
        #expect(p.effect.color == RGB(255, 136, 0))
        #expect(p.brightness == 100)
        #expect(p.alerts == AlertSettings())
    }

    @Test func nonProfileFilesAreRejected() throws {
        let a = tempStore()
        let file = a.baseDir.appendingPathComponent("junk.json")
        try #"{"hello":"world"}"#.write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: ChromaError.self) { try a.importBundle(from: file, overwrite: false, activate: false) }
        #expect(a.profileNames().isEmpty)
    }
}
/// Which notifications count as calls. Uses the default alert settings.
@Suite struct AlertClassificationTests {
    let s = AlertSettings()
    func note(_ app: String, _ title: String = "Someone", _ body: String = "", buttons: String = "") -> NotificationWatcher.Note {
        NotificationWatcher.Note(app: app, title: title, subtitle: "", body: body, buttons: buttons)
    }

    @Test func faceTimeCallBannerIsACall() {
        // What a real incoming iPhone/FaceTime call banner reported on macOS 27.
        #expect(NotificationWatcher.classify(note("FaceTime Notification"), s) == .call)
        #expect(NotificationWatcher.classify(note("FaceTime"), s) == .call)
        #expect(NotificationWatcher.classify(note("com.apple.FaceTime"), s) == .call)
    }

    @Test func callButtonsOrWordsMakeACall() {
        #expect(NotificationWatcher.classify(note("WhatsApp", buttons: "Decline Accept"), s) == .call)
        #expect(NotificationWatcher.classify(note("Teams", "Alex", "Incoming call"), s) == .call)
    }

    @Test func similarlyNamedAppsAreNotCalls() {
        #expect(NotificationWatcher.classify(note("iPhone Mirroring"), s) == .notify)
        #expect(NotificationWatcher.classify(note("Messages", "Alex", "see you at 5"), s) == .notify)
    }

    @Test func ignoredAppsAreIgnored() {
        var t = s; t.ignoreApps = ["com.apple.Music"]
        #expect(NotificationWatcher.classify(note("Music Notification"), t) == nil || NotificationWatcher.classify(note("Music"), t) == nil)
    }
}
