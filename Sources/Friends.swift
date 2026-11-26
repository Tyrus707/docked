import Foundation
import CoreWLAN

// Play with friends: a converted game's Local Wireless reaches the friends in the player's circle, over the internet (Friends/engine-patches).
// Docked only keeps the circle's pass, friends.cfg (the meeting point's address and the circle's shared key), where every converted game looks for it.
// The player turns it on per game, in that game's settings (DM_FRIENDS); friends are added by code on the game's own Friends screen.
enum Friends {
    static var folder: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOCKED_FRIENDS"] ?? NSHomeDirectory() + "/Library/Application Support/Docked/Friends") }
    static var pass: URL { folder.appendingPathComponent("friends.cfg") }
    // where the first meeting point setup (before Docked had friends) saved its pass
    static var older: URL { folder.deletingLastPathComponent().appendingPathComponent("Friends Meeting/friends.cfg") }
    static var ready: Bool { read(pass) != nil }
    static var meetingPoint: String? { read(pass).flatMap { URL(string: $0.meet)?.host } }

    struct Pass: Equatable { let meet: String; let circle: Data }
    static func read(_ u: URL) -> Pass? {
        guard let a = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), a.isRegularFile == true, (a.fileSize ?? 0) < 4096,
              let t = try? String(contentsOf: u, encoding: .utf8) else { return nil }
        return parse(t)
    }
    static func parse(_ t: String) -> Pass? {
        var meet: String?, circle: Data?
        for l in t.split(whereSeparator: \.isNewline) {
            let s = l.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("meet=") { meet = String(s.dropFirst(5)) } else if s.hasPrefix("circle=") { circle = Data(base64Encoded: String(s.dropFirst(7))) }
        }
        guard let m = meet, let u = URL(string: m), u.scheme == "wss", let h = u.host, !h.isEmpty, let c = circle, c.count == 32 else { return nil }
        return Pass(meet: m, circle: c)
    }
    // Takes a pass the player was given (or made), readable by this player only. The one in use stays until the new one is in place.
    static func use(_ from: URL) throws {
        guard read(from) != nil else { throw RetroError("That isn't a friends pass. Ask whoever set up your circle for their friends.cfg file.") }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let d = try Data(contentsOf: from), t = folder.appendingPathComponent("friends.cfg.new")
        try? fm.removeItem(at: t)
        guard fm.createFile(atPath: t.path, contents: d, attributes: [.posixPermissions: 0o600]) else { throw RetroError("The friends pass couldn't be saved.") }
        if fm.fileExists(atPath: pass.path) { _ = try fm.replaceItemAt(pass, withItemAt: t) } else { try fm.moveItem(at: t, to: pass) }
    }
    // A pass the earlier setup made is taken as it is, once
    static func adoptOlder() { if !ready, read(older) != nil { try? use(older) } }
    // A copy to send to a friend (AirDrop, Messages, Mail), with a name that says what it is
    static func shareable() -> URL? {
        guard ready, let d = try? Data(contentsOf: pass) else { return nil }
        forgetShared()   // the pass is the circle's key: only the newest copy waits in the temporary folder
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("docked-pass-\(UUID().uuidString)"), u = dir.appendingPathComponent("Docked Friends Pass.cfg")
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil, FileManager.default.createFile(atPath: u.path, contents: d, attributes: [.posixPermissions: 0o600]) else { return nil }
        return u
    }
    static func forgetShared(in tmp: URL = FileManager.default.temporaryDirectory) {
        for n in (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? [] where n.hasPrefix("docked-pass-") && UUID(uuidString: String(n.dropFirst(12))) != nil { try? FileManager.default.removeItem(at: tmp.appendingPathComponent(n)) }
    }
    // Is Play with friends switched on in this game's own settings
    static func on(_ app: URL) -> Bool {
        guard let p = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")), let b = p["CFBundleIdentifier"] as? String, let u = UserDefaults(suiteName: b) else { return false }
        return u.string(forKey: "launcher.DM_FRIENDS") == "1"
    }
    // On Wi-Fi with no wired connection up: Mac Wi-Fi pauses now and then to look for AirDrop and Handoff devices, which lockstep games feel as slow motion
    static func wifiOnly() -> Bool {
        guard let wifi = CWWiFiClient.shared().interface(), wifi.powerOn(), wifi.ssid() != nil || wifi.wlanChannel() != nil, let name = wifi.interfaceName else { return false }
        var list: UnsafeMutablePointer<ifaddrs>?; guard getifaddrs(&list) == 0, let first = list else { return true }
        defer { freeifaddrs(list) }
        var wired = false
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee, n = String(cString: i.ifa_name), up = (i.ifa_flags & UInt32(IFF_UP | IFF_RUNNING)) == UInt32(IFF_UP | IFF_RUNNING)
            if up, n != name, n.hasPrefix("en"), let a = i.ifa_addr, a.pointee.sa_family == UInt8(AF_INET) { wired = true }
        }
        return !wired
    }

    // AirDrop, Handoff and Sidecar share the Wi-Fi radio through awdl0, which leaves the network channel for a few ms many times a second: in a lockstep game that is lag.
    // With one admin prompt, awdl0 stays down while the game runs (macOS brings it back on its own, so it is put down again every 2 s) and comes back when the game closes.
    static func pauseAirDrop(whilePID pid: Int32) {
        guard pid > 0 else { return }
        let sh = "/sbin/ifconfig awdl0 down; (while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 2; /sbin/ifconfig awdl0 down; done; /sbin/ifconfig awdl0 up) >/dev/null 2>&1 &"
        let script = "do shell script \"\(sh)\" with administrator privileges with prompt \"Docked will pause AirDrop's Wi-Fi scanning while you play with friends, so the game doesn't lag. AirDrop comes back when the game closes.\""
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    // Games converted before Play with friends have no friends link in them: their settings list has no DM_FRIENDS
    static func supported(_ app: URL) -> Bool {
        guard let d = try? Data(contentsOf: app.appendingPathComponent("Contents/Resources/dm/launcher.json")) else { return false }
        return d.range(of: Data("\"DM_FRIENDS\"".utf8)) != nil
    }
    // Turn it on in the game's own settings, which live outside the signed app. Only works once the conversion has added the switch.
    @discardableResult
    static func enable(on app: URL) -> Bool {
        guard let settings = GameSettings(app: app), let s = settings.settings.first(where: { $0.env == "DM_FRIENDS" }), s.kind == .toggle else { return false }
        guard !settings.isFixed(s) else { return settings.value(s) == (s.on ?? "1") }
        settings.set(s, s.on ?? "1")
        return on(app)
    }
    // Why an older game can't be rebuilt yet. The links Docked keeps in Inputs are no use once the originals are gone.
    static func missingOriginals(_ name: String) -> String {
        "Docked can't find \(name)'s original files. If you chose to move them to the Trash and haven't emptied it, put them back. Otherwise add the game again from where you keep your games, with its update and DLC. The links in Docked's Inputs folder only help while the original files are still there. Your save stays, and Play with friends is already switched on for this conversion."
    }
}
