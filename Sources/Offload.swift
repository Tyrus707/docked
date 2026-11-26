import Foundation

// Offloading: a game's files go to a folder the player chooses, such as iCloud Drive, Dropbox, Google Drive or an external drive, and come back when wanted.
// Its tile, cover, play time and saves stay on this Mac. Docked uses no servers of its own: the cloud is the player's own folder.

// What to call the place a game was offloaded to
func offloadName(_ path: String) -> String {
    if let d = drive(of: path) { return d.name }
    if path.contains("/Library/Mobile Documents/") { return "iCloud Drive" }
    if let r = path.range(of: "/Library/CloudStorage/") {
        let what = path[r.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        for (k, n) in [("Dropbox", "Dropbox"), ("GoogleDrive", "Google Drive"), ("OneDrive", "OneDrive"), ("Box", "Box"), ("iCloud", "iCloud Drive")] where what.hasPrefix(k) { return n }
        return what.split(separator: "-").first.map(String.init) ?? "the cloud"
    }
    return "your offload folder"
}

enum OffloadError: LocalizedError, Equatable {
    case gone(String), stalled(String), room(Int64, Int64), split(String, String)
    var errorDescription: String? {
        switch self {
        case .gone(let w): return "It isn't in \(w) any more."
        case .stalled(let w): return "\(w) stopped sending it. Check your internet connection and try again."
        case let .split(folder, why): return "\(why) Some of its files couldn't come back and are still in \(folder). Move them back beside the game to play it."
        case let .room(need, free): return "It needs \(ByteCountFormatter.string(fromByteCount: need, countStyle: .file)) free on this Mac, and there is \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))."
        }
    }
}

enum Offload {
    // Into its console's folder there. A game that comes as several files goes in a folder of its own, so it comes back whole.
    // Returns what was offloaded: the game, or its folder.
    static func send(_ game: URL, console: String, set: Bool, to root: URL) throws -> URL {
        let fm = FileManager.default, dir = Organize.folder(console, in: root)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let parts = set ? Organize.companions(game) : []
        if parts.isEmpty { let to = Organize.free(dir.appendingPathComponent(game.lastPathComponent)); try Organize.transfer(game, to: to, move: true); return to }
        let here = game.deletingLastPathComponent().standardizedFileURL, all = [game.standardizedFileURL] + parts
        let folder = Organize.free(dir.appendingPathComponent(game.deletingPathExtension().lastPathComponent, isDirectory: true))
        if !sameVolume(here, dir) { try Organize.ensureSpace(all.reduce(0) { $0 + folderSize($1) }, at: dir) }
        var done: [(URL, URL)] = []
        do {
            for f in all { let t = folder.appendingPathComponent(String(f.path.dropFirst(here.path.count + 1))); try Organize.transfer(f, to: t, move: true); done.append((f, t)) }
        } catch {
            var stuck = false   // what had gone comes back; if some of it can't, the player is told where it is
            for (a, b) in done.reversed() { do { try Organize.transfer(b, to: a, move: true) } catch { stuck = true } }
            if stuck { throw OffloadError.split(folder.path, error.localizedDescription) }
            try? fm.removeItem(at: folder); throw error
        }
        return folder
    }

    // Back to its place on this Mac
    static func bring(_ away: URL, home: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: home.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: home.path) { throw PlaceError.taken(home.lastPathComponent) }
        var d: ObjCBool = false; _ = fm.fileExists(atPath: away.path, isDirectory: &d)
        guard d.boolValue, away.pathExtension.isEmpty, !home.pathExtension.isEmpty else { try Organize.transfer(away, to: home, move: true); return }
        // a folder of files that belong together: each goes back beside the game file
        let dir = home.deletingLastPathComponent(), items = try fm.contentsOfDirectory(at: away, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        for i in items where fm.fileExists(atPath: dir.appendingPathComponent(i.lastPathComponent).path) { throw PlaceError.taken(i.lastPathComponent) }
        if !sameVolume(away, dir) { try Organize.ensureSpace(items.reduce(0) { $0 + folderSize($1) }, at: dir) }
        for i in items { try Organize.transfer(i, to: dir.appendingPathComponent(i.lastPathComponent), move: true) }
        try? fm.removeItem(at: away)
    }

    // Free space on the disk a path is on, from the nearest folder that exists
    static func free(at u: URL) -> Int64 {
        var d = u; while !FileManager.default.fileExists(atPath: d.path), d.pathComponents.count > 1 { d.deleteLastPathComponent() }
        let v = try? d.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? Int64(v?.volumeAvailableCapacity ?? 0)
    }
}

// Files kept in the cloud, which may be on this Mac or only in the cloud until asked for
enum Cloud {
    private static let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .fileSizeKey, .totalFileAllocatedSizeKey, .isRegularFileKey]

    // An older macOS shows a file that is only in iCloud as a hidden ".name.icloud" beside where it would be
    static func placeholder(_ u: URL) -> URL { u.deletingLastPathComponent().appendingPathComponent("." + u.lastPathComponent + ".icloud") }
    static func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) || FileManager.default.fileExists(atPath: placeholder(u).path) }

    // What under u is still only in the cloud, and how many bytes of it are not here yet
    static func waiting(_ u: URL) -> (files: [URL], left: Int64) {
        let fm = FileManager.default
        var files: [URL] = [], left: Int64 = 0
        func look(_ f: URL) {
            let n = f.lastPathComponent
            if n.hasPrefix("."), n.hasSuffix(".icloud") { files.append(f.deletingLastPathComponent().appendingPathComponent(String(n.dropFirst().dropLast(7)))); return }
            guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true, v.isUbiquitousItem == true, let s = v.ubiquitousItemDownloadingStatus, s != .current else { return }
            files.append(f); left += max(0, Int64(v.fileSize ?? 0) - Int64(v.totalFileAllocatedSize ?? 0))
        }
        if !fm.fileExists(atPath: u.path) { if fm.fileExists(atPath: placeholder(u).path) { look(placeholder(u)) }; return (files, left) }
        look(u)
        if let e = fm.enumerator(at: u, includingPropertiesForKeys: Array(keys)) { for case let f as URL in e { look(f) } }
        return (files, left)
    }

    // Brings everything under u onto this Mac, telling how far along it is (0 to 1). Gives up when nothing arrives for three minutes.
    static func fetch(_ u: URL, from name: String, progress: (Double) -> Void) throws {
        var w = waiting(u)
        guard !w.files.isEmpty else { return }
        let fm = FileManager.default, total = max(w.left, 1)
        for f in w.files { try? fm.startDownloadingUbiquitousItem(at: f) }
        try? fm.startDownloadingUbiquitousItem(at: u)
        var last = (w.files.count, w.left), still = Date()
        progress(0)
        while true {
            Thread.sleep(forTimeInterval: 1)
            w = waiting(u)
            if w.files.isEmpty { progress(1); return }
            progress(min(0.99, Double(total - w.left) / Double(total)))
            if (w.files.count, w.left) != last { last = (w.files.count, w.left); still = Date() }
            else if Date().timeIntervalSince(still) > 180 { throw OffloadError.stalled(name) }
        }
    }

    // Asks the cloud folder to keep it only in the cloud, which frees the room here. This works once it has been uploaded, so it is tried again later.
    @discardableResult static func evict(_ u: URL) -> Bool {
        guard (try? u.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true else { return false }
        return (try? FileManager.default.evictUbiquitousItem(at: u)) != nil
    }
}
