import Foundation

// A converted game's own data on this Mac, where the engine keeps it whatever drive the game is on (nxnative docs/settings.md):
//   ~/Library/Application Support/nxnative/<title ID>/save, save_device, save_userN, save.users   the save
//   …/save-backups     copies the engine takes at each start (and of a save cloud saves replaced); Docked's own copies go here too
//   …/cheats           Atmosphère cheat files, <build ID>.txt
//   ~/Library/Logs/nxnative/<title ID>.log   the game's log
// Saves stay on the Mac's own APFS disk, so a game kept on an exFAT drive still saves (the engine clones save folders, which needs APFS).
struct GameData {
    let id: String
    static var support: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOCKED_NXDATA"] ?? NSHomeDirectory() + "/Library/Application Support/nxnative") }
    static var logs: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOCKED_NXLOGS"] ?? NSHomeDirectory() + "/Library/Logs/nxnative") }
    init(_ titleID: String) { id = titleID.uppercased() }

    var root: URL { Self.support.appendingPathComponent(id) }
    var save: URL { root.appendingPathComponent("save") }
    var backups: URL { root.appendingPathComponent("save-backups") }
    var cheats: URL { root.appendingPathComponent("cheats") }
    var log: URL { Self.logs.appendingPathComponent(id + ".log") }

    // The parts of a save: the player's, the device's, other local players' and their list
    static func isSavePart(_ n: String) -> Bool { n == "save" || n == "save_device" || n == "save.users" || n.hasPrefix("save_user") }
    var hasSave: Bool { FileManager.default.fileExists(atPath: save.path) }

    struct Backup: Equatable {
        let url: URL; let date: Date; let bytes: Int64
        var name: String { url.lastPathComponent }
        // Docked's dated folders say why they were made; plain language in the restore menu.
        var reason: String {
            let n = name.lowercased()
            if n.contains("before convert") { return "before conversion" }
            if n.contains("before engine") { return "before engine update" }
            if n.contains("before update") { return "before update" }
            if n.contains("before offload") { return "before offload" }
            if n.contains("before trash") { return "before trash" }
            if n.contains("before restore") { return "before restore" }
            return n.contains("docked") ? "manual backup" : "backup"
        }
    }

    // Newest first. A backup is any folder in save-backups holding a save.
    func list() -> [Backup] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])) ?? []
        return dirs.compactMap { u -> Backup? in
            guard fm.fileExists(atPath: u.appendingPathComponent("save").path) else { return nil }
            let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Backup(url: u, date: d, bytes: Self.size(u))
        }.sorted { $0.date > $1.date }
    }

    static func size(_ u: URL) -> Int64 {
        var n: Int64 = 0
        let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        while let f = e?.nextObject() as? URL { if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { n += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) } }
        return n
    }

    static func stamp(_ d: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH.mm.ss"; return f.string(from: d) }

    // Copies the save into save-backups/"<date> Docked". Nil when there is no save yet.
    // One copy per save: when the newest copy already holds this save, that copy is the answer and nothing new is made.
    // Then only the newest `keep` copies stay (nil keeps them all, for a caller that prunes once it is done).
    @discardableResult func backUp(now: Date = Date(), label: String = "Docked", keep: Int? = kept) throws -> URL? {
        let fm = FileManager.default
        guard hasSave else { return nil }
        if let newest = list().first, matches(newest.url) { return newest.url }
        defer { if let keep { prune(keep: keep) } }
        var to = backups.appendingPathComponent("\(Self.stamp(now)) \(label)"), i = 2
        while fm.fileExists(atPath: to.path) { to = backups.appendingPathComponent("\(Self.stamp(now)) \(label) \(i)"); i += 1 }
        try fm.createDirectory(at: to, withIntermediateDirectories: true)
        do { for n in try fm.contentsOfDirectory(atPath: root.path) where Self.isSavePart(n) { try fm.copyItem(at: root.appendingPathComponent(n), to: to.appendingPathComponent(n)) } }
        catch { try? fm.removeItem(at: to); throw error }
        return to
    }

    // Copies Docked made by itself ("<date> Docked before ...") beyond the newest few go. Copies the player made, or brought in, stay.
    // A game keeps at most this many copies, newest first, so its save-backups folder stays small and tidy.
    static let kept = 3
    func prune(keep: Int = kept) { for b in list().dropFirst(max(keep, 1)) { try? FileManager.default.removeItem(at: b.url) } }
    // True when a copy holds exactly the save there is now: the same parts, byte for byte.
    func matches(_ copy: URL) -> Bool {
        let fm = FileManager.default
        let now = Set(((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter(Self.isSavePart)), then = Set(((try? fm.contentsOfDirectory(atPath: copy.path)) ?? []).filter(Self.isSavePart))
        return !now.isEmpty && now == then && now.allSatisfy { fm.contentsEqual(atPath: root.appendingPathComponent($0).path, andPath: copy.appendingPathComponent($0).path) }
    }

    // A dated copy in a folder the player chose, such as iCloud Drive or another drive. Never copies keys or game files.
    // The chosen folder is never replaced: the save goes in a new folder inside it, with a name saying what and when.
    @discardableResult func export(into folder: URL, named name: String? = nil) throws -> URL? {
        let fm = FileManager.default
        guard hasSave else { return nil }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = name ?? "Docked save"
        var to = folder.appendingPathComponent("\(Self.stamp(Date())) \(base)"), i = 2
        while fm.fileExists(atPath: to.path) { to = folder.appendingPathComponent("\(Self.stamp(Date())) \(base) \(i)"); i += 1 }
        try fm.createDirectory(at: to, withIntermediateDirectories: false)
        do { for n in try fm.contentsOfDirectory(atPath: root.path) where Self.isSavePart(n) { try fm.copyItem(at: root.appendingPathComponent(n), to: to.appendingPathComponent(n)) } }
        catch { try? fm.removeItem(at: to); throw error }
        return to
    }

    // A folder to bring in: a backup (holds save/) or a save folder itself. Nil when it holds no files.
    static func saveIn(_ u: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: u.appendingPathComponent("save").path) { return u }
        let items = (try? fm.contentsOfDirectory(atPath: u.path))?.filter { !$0.hasPrefix(".") } ?? []
        return items.isEmpty ? nil : u
    }

    // Puts the save from `from` in place. The current save is copied to save-backups first, so nothing is lost.
    func restore(_ from: URL, now: Date = Date()) throws {
        let fm = FileManager.default
        guard let src = Self.saveIn(from) else { throw CocoaError(.fileReadNoSuchFile) }
        try backUp(now: now, label: "before restore", keep: nil)   // the copy being brought in may be among those a prune would take
        defer { prune() }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let backup = fm.fileExists(atPath: src.appendingPathComponent("save").path)
        var parts: [(URL, String)] = [(src, "save")]
        if backup { parts = try fm.contentsOfDirectory(atPath: src.path).filter(Self.isSavePart).map { (src.appendingPathComponent($0), $0) } }
        // Each part goes in beside the old one, then takes its place, so a copy cut short leaves the old save as it was.
        for (u, n) in parts {
            let dest = root.appendingPathComponent(n), temp = root.appendingPathComponent(".\(n).incoming-\(UUID().uuidString)")
            try fm.copyItem(at: u, to: temp)
            if fm.fileExists(atPath: dest.path) { _ = try fm.replaceItemAt(dest, withItemAt: temp) } else { try fm.moveItem(at: temp, to: dest) }
        }
    }

    // Cheats: adds a cheat file (named by the game's build ID, as cheat sites name them) to the folder the engine reads.
    @discardableResult func addCheat(_ file: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: cheats, withIntermediateDirectories: true)
        let to = cheats.appendingPathComponent(file.lastPathComponent)
        if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
        try fm.copyItem(at: file, to: to); return to
    }
    var cheatFiles: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: cheats.path)) ?? []).filter { $0.lowercased().hasSuffix(".txt") }.sorted() }
    static func isCheatFile(_ u: URL) -> Bool { u.pathExtension.lowercased() == "txt" && u.deletingPathExtension().lastPathComponent.count == 16 && u.deletingPathExtension().lastPathComponent.allSatisfy(\.isHexDigit) }
}

// The cloud saves folder: one key in each game app's own preferences, which its launcher reads at every start (docs/frontends.md).
// One folder serves every game: each keeps its own <title ID>/save.dmsync in it.
enum CloudSaves {
    static let key = "cloudSaves.folder"
    static func folder(of app: URL) -> String? { gamePrefs(app)?.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 } }
    // Docked's folder for every game, or "" for off. Off only clears a game whose folder was Docked's, so a folder chosen in a game's own window stays.
    static func apply(_ folder: String, was: String, to app: URL) {
        guard let d = gamePrefs(app) else { return }
        if !folder.isEmpty { d.set(folder, forKey: key) } else if !was.isEmpty, d.string(forKey: key) == was { d.removeObject(forKey: key) }
    }
}

// A game that crashed leaves a crash report named after its program, from the time it ran.
func crashReport(for app: URL, since: Date, in dir: URL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/DiagnosticReports")) -> URL? {
    let fm = FileManager.default
    let names = ((try? fm.contentsOfDirectory(atPath: app.appendingPathComponent("Contents/MacOS").path)) ?? []).filter { !$0.hasPrefix(".") }
    guard !names.isEmpty else { return nil }
    let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    return files.filter { f in
        let n = f.lastPathComponent
        return (n.hasSuffix(".ips") || n.hasSuffix(".crash")) && names.contains { n.hasPrefix($0 + "-") || n.hasPrefix($0 + "_") }
            && ((try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= since
    }.max { a, b in a.lastPathComponent < b.lastPathComponent }
}
