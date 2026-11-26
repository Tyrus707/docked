import Foundation

// The library on disk. Docked files games into one library folder, a folder for each console, each game named after itself.
// It only ever tidies what is inside its own folders: games kept anywhere else, such as another emulator's, are remembered where they are.

enum AddMode: String, CaseIterable {
    case copy, move, leave
    var label: String { switch self { case .copy: return "Copy into the library"; case .move: return "Move into the library"; case .leave: return "Leave where they are" } }
    var detail: String {
        switch self {
        case .copy: return "The originals stay, so other emulators keep working. On the same disk a copy takes no extra space."
        case .move: return "They move into the library folder. Other apps that used them won't find them there."
        case .leave: return "Docked remembers where they are and never moves them."
        }
    }
}

enum Naming: String, CaseIterable {
    case game, original
    var label: String { self == .game ? "Game name" : "Original file name" }
}

enum Organize {
    // "Game Boy Advance", "Switch 2": the console's own name
    static func folder(_ consoleID: String, in lib: URL) -> URL { lib.appendingPathComponent(safe(consoleName(consoleID)), isDirectory: true) }

    // A name Finder takes: no slashes or colons, no leading dot, not too long
    static func safe(_ s: String) -> String {
        var n = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -").trimmingCharacters(in: .whitespacesAndNewlines)
        while n.hasPrefix(".") { n.removeFirst() }
        n = String(n.prefix(120)).trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Game" : n
    }

    static func text(_ u: URL) -> String? {
        guard let d = try? Data(contentsOf: u), d.count < 1_000_000 else { return nil }
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1)
    }
    // Words on a line, where "quoted words" count as one
    static func words(_ l: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        for ch in l {
            if ch == "\"" { quoted.toggle(); continue }
            if ch == " " || ch == "\t", !quoted { if !cur.isEmpty { out.append(cur); cur = "" }; continue }
            cur.append(ch)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    // Files that belong with a game file and must stay beside it under their own names: a cue's or gdi's tracks, an m3u's discs, a ccd's image.
    // Only files in the same folder or below it count.
    static func companions(_ u: URL) -> [URL] {
        let fm = FileManager.default, e = u.pathExtension.lowercased(), dir = u.deletingLastPathComponent().standardizedFileURL
        var names: [String] = []
        if e == "ccd" { let b = u.deletingPathExtension().lastPathComponent; names = ["img", "sub"].map { b + "." + $0 } }
        else if ["cue", "gdi", "m3u"].contains(e), let t = text(u) {
            for raw in t.split(whereSeparator: \.isNewline) {
                let l = raw.trimmingCharacters(in: .whitespaces), w = words(l)
                switch e {
                case "cue": if w.count >= 2, w[0].uppercased() == "FILE" { names.append(w[1]) }
                case "gdi": if w.count >= 5 { names.append(w[4]) }
                default: if !l.isEmpty, !l.hasPrefix("#") { names.append(l) }
                }
            }
        }
        var out: [URL] = []
        for n in names {
            let f = dir.appendingPathComponent(n).standardizedFileURL
            guard f.path.hasPrefix(dir.path + "/"), fm.fileExists(atPath: f.path), f != u.standardizedFileURL, !out.contains(f) else { continue }
            out.append(f)
            if e == "m3u" { for c in companions(f) where !out.contains(c) { out.append(c) } }
        }
        return out
    }

    // Where a game file belongs. One with companions gets a folder of its own, where every file keeps its name, since they name each other.
    static func place(_ rom: URL, console: String, name: String, naming: Naming, organized: Bool = true, in lib: URL) -> URL {
        let dir = organized ? folder(console, in: lib) : lib
        let base = organized && naming == .game ? safe(name) : rom.deletingPathExtension().lastPathComponent
        if !companions(rom).isEmpty { return dir.appendingPathComponent(base, isDirectory: true).appendingPathComponent(rom.lastPathComponent) }
        return dir.appendingPathComponent(base + (rom.pathExtension.isEmpty ? "" : "." + rom.pathExtension))
    }

    // The name itself, or "Name 2", "Name 3" when it is taken. Nothing is ever replaced.
    static func free(_ u: URL) -> URL {
        let fm = FileManager.default; guard fm.fileExists(atPath: u.path) else { return u }
        let ext = u.pathExtension, base = u.deletingPathExtension().lastPathComponent, dir = u.deletingLastPathComponent()
        var i = 2
        while true { let c = dir.appendingPathComponent("\(base) \(i)" + (ext.isEmpty ? "" : "." + ext)); if !fm.fileExists(atPath: c.path) { return c }; i += 1 }
    }
    // Already in its place: the same path, or the same name with a number after it
    static func isPlaced(_ at: URL, _ want: URL) -> Bool {
        let a = at.standardizedFileURL, w = want.standardizedFileURL
        if a.path == w.path { return true }
        guard a.deletingLastPathComponent().path == w.deletingLastPathComponent().path, a.pathExtension == w.pathExtension else { return false }
        let ab = a.deletingPathExtension().lastPathComponent, wb = w.deletingPathExtension().lastPathComponent
        guard ab.hasPrefix(wb + " ") else { return false }
        let tail = ab.dropFirst(wb.count + 1); return !tail.isEmpty && tail.allSatisfy(\.isNumber)
    }

    static func ensureSpace(_ bytes: Int64, at dir: URL) throws {
        if freeSpace(at: dir) < bytes + 200_000_000 { throw PlaceError.noSpace }
    }

    // One file or app: moved when asked and on the same disk; otherwise copied whole under a hidden name, then named.
    // A copy on the same APFS disk is a clone, so it takes no space until one of them changes.
    static func transfer(_ a: URL, to b: URL, move: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: b.deletingLastPathComponent(), withIntermediateDirectories: true)
        if move, sameVolume(a, b.deletingLastPathComponent()) { try fm.moveItem(at: a, to: b); return }
        if !sameVolume(a, b.deletingLastPathComponent()) { try ensureSpace(folderSize(a), at: b.deletingLastPathComponent()) }
        let part = b.deletingLastPathComponent().appendingPathComponent("." + b.lastPathComponent + ".partial")
        try? fm.removeItem(at: part)
        do { try fm.copyItem(at: a, to: part); try fm.moveItem(at: part, to: b) } catch { try? fm.removeItem(at: part); throw error }
        if move { LeftBehind.remove(a) }
    }

    // Puts a game file, and everything that belongs with it, into the library. Returns where the game file is now.
    static func file(_ rom: URL, console: String, name: String, mode: AddMode, naming: Naming, organized: Bool = true, in lib: URL) throws -> URL {
        guard mode != .leave else { return rom }
        let fm = FileManager.default, parts = companions(rom), want = place(rom, console: console, name: name, naming: naming, organized: organized, in: lib)
        if isPlaced(rom, want) { return rom }
        if parts.isEmpty { let to = free(want); try transfer(rom, to: to, move: mode == .move); return to }
        let here = rom.deletingLastPathComponent().standardizedFileURL
        if isPlaced(here, want.deletingLastPathComponent()) { return rom }
        let folder = free(want.deletingLastPathComponent()), all = [rom.standardizedFileURL] + parts
        let rel: (URL) -> String = { String($0.path.dropFirst(here.path.count + 1)) }
        try fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        if mode == .move, sameVolume(here, folder.deletingLastPathComponent()) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var done: [(URL, URL)] = []   // a set moves whole or not at all: what had moved goes back
            do { for f in all { let t = folder.appendingPathComponent(rel(f)); try fm.createDirectory(at: t.deletingLastPathComponent(), withIntermediateDirectories: true); try fm.moveItem(at: f, to: t); done.append((f, t)) } }
            catch {
                var stuck: [URL] = []
                for (a, b) in done.reversed() { do { try fm.moveItem(at: b, to: a) } catch { if fm.fileExists(atPath: b.path) { stuck.append(b) } } }
                if stuck.isEmpty { try? fm.removeItem(at: folder) } else { stuck.forEach(LeftBehind.note) }
                throw error
            }
            return folder.appendingPathComponent(rom.lastPathComponent)
        }
        if !sameVolume(here, folder.deletingLastPathComponent()) { try ensureSpace(all.reduce(0) { $0 + folderSize($1) }, at: folder.deletingLastPathComponent()) }
        let part = folder.deletingLastPathComponent().appendingPathComponent("." + folder.lastPathComponent + ".partial")
        try? fm.removeItem(at: part)
        do {
            for f in all { let t = part.appendingPathComponent(rel(f)); try fm.createDirectory(at: t.deletingLastPathComponent(), withIntermediateDirectories: true); try fm.copyItem(at: f, to: t) }
            try fm.moveItem(at: part, to: folder)
        } catch { try? fm.removeItem(at: part); throw error }
        if mode == .move { for f in all { LeftBehind.remove(f) } }
        return folder.appendingPathComponent(rom.lastPathComponent)
    }

    // A converted game into its console's folder
    static func fileApp(_ app: URL, mode: AddMode, organized: Bool = true, in lib: URL) throws -> URL {
        guard mode != .leave, let id = titleID(of: app) else { return app }
        let dir = organized ? folder(consoleOf(id), in: lib) : lib
        if isPlaced(app, dir.appendingPathComponent(app.lastPathComponent)) { return app }
        let to = free(dir.appendingPathComponent(app.lastPathComponent))
        try transfer(app, to: to, move: mode == .move); return to
    }

    // RetroArch names saves and save states after the game file, so they follow it when its name changes
    static func carrySaves(from old: URL, to new: URL, in dirs: [URL], move: Bool) {
        let fm = FileManager.default, a = old.deletingPathExtension().lastPathComponent, b = new.deletingPathExtension().lastPathComponent
        guard a != b else { return }
        for d in dirs {
            for f in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] where f.lastPathComponent.hasPrefix(a + ".") {
                let t = d.appendingPathComponent(b + f.lastPathComponent.dropFirst(a.count))
                guard !fm.fileExists(atPath: t.path) else { continue }
                if move { try? fm.moveItem(at: f, to: t) } else { try? fm.copyItem(at: f, to: t) }
            }
        }
    }

    // What Organize Library would do: games inside Docked's own folders that are not where the layout puts them
    static func plan(_ games: [Game], owned: [URL], lib: URL, naming: Naming) -> [Tidy] {
        let roots = owned.map { $0.standardizedFileURL.path }
        func inside(_ u: URL) -> Bool { let p = u.standardizedFileURL.path; return roots.contains { p.hasPrefix($0 + "/") } }
        return games.compactMap { g in
            guard !g.missing, inside(g.url) else { return nil }
            if let r = g.rom {
                let want = place(g.url, console: r.console, name: g.name, naming: naming, in: lib)
                let ok = companions(g.url).isEmpty ? isPlaced(g.url, want) : isPlaced(g.url.deletingLastPathComponent(), want.deletingLastPathComponent())
                return ok ? nil : Tidy(game: g, to: want)
            }
            let want = folder(consoleOf(g.titleID), in: lib).appendingPathComponent(g.url.lastPathComponent)
            return isPlaced(g.url, want) ? nil : Tidy(game: g, to: want)
        }
    }

    // Docked's build folders sit beside games in its Games folder; Finder hides them so the library reads clearly. Clean Up still finds them.
    static func hideBuildFolders(in dir: URL = Paths.games) {
        for u in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isHiddenKey])) ?? [] where u.lastPathComponent.hasSuffix("_build") {
            var u = u; if (try? u.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == false { var v = URLResourceValues(); v.isHidden = true; try? u.setResourceValues(v) }
        }
    }
}

struct Tidy: Identifiable, Equatable {
    let game: Game, to: URL
    var id: String { game.id }
}

// Originals that were copied but could not be removed afterwards: the game moved, but the room was not freed and two copies exist.
// Told to the player when the job ends (Model.filing and Model.moving).
enum LeftBehind {
    private static let lock = NSLock()
    private static var list: [URL] = []
    static func note(_ u: URL) { lock.lock(); list.append(u); lock.unlock() }
    static func take() -> [URL] { lock.lock(); defer { list = []; lock.unlock() }; return list }
    static func remove(_ u: URL) { do { try FileManager.default.removeItem(at: u) } catch { if FileManager.default.fileExists(atPath: u.path) { note(u) } } }
}

// MARK: - Drives

// A path on a disk that comes and goes, such as an SSD: its name, and whether it is here now.
// Here means the very drive the game was seen on: two drives can share a name ("Untitled", "T7"), and the other one being plugged in is not this one.
func drive(of path: String, ids: DriveIDs = .shared) -> (name: String, connected: Bool)? {
    let parts = (path as NSString).pathComponents
    guard parts.count > 2, parts[0] == "/", parts[1] == "Volumes" else { return nil }
    let root = "/Volumes/" + parts[2]
    return (parts[2], FileManager.default.fileExists(atPath: root) && ids.matches(path))
}

// Which drive each game on a drive was last seen on, by the drive's own ID (it survives renaming and is never shared)
final class DriveIDs {
    static let shared = DriveIDs()
    private let lock = NSLock(), store: UserDefaults, key = "driveIDs"
    private var seen: [String: String]
    let id: (String) -> String?   // a mounted drive's ID, from its folder in /Volumes
    init(store: UserDefaults = .standard, id: @escaping (String) -> String? = { (try? URL(fileURLWithPath: $0).resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString }) {
        self.store = store; self.id = id; seen = store.dictionary(forKey: "driveIDs") as? [String: String] ?? [:]
    }
    private static func root(_ path: String) -> String? {
        let p = (path as NSString).pathComponents; return p.count > 2 && p[0] == "/" && p[1] == "Volumes" ? "/Volumes/" + p[2] : nil
    }
    // A game found where it should be: remembered with the drive it is on
    func remember(_ paths: [String]) {
        var ids: [String: String?] = [:], changed = false
        lock.lock(); defer { lock.unlock(); if changed { store.set(seen, forKey: key) } }
        for p in paths { guard let r = Self.root(p) else { continue }
            if ids[r] == nil { ids[r] = .some(id(r)) }
            if let u = ids[r] ?? nil, seen[p] != u { seen[p] = u; changed = true }
        }
    }
    // The drive at that name now is the one the game was on (or it was never seen, so it can't be told apart)
    func matches(_ path: String) -> Bool {
        guard let r = Self.root(path) else { return true }
        lock.lock(); let want = seen[path]; lock.unlock()
        guard let want, let now = id(r) else { return true }
        return now == want
    }
}

// Why a game can't be found, in words
func whereMissing(_ path: String) -> String {
    if let d = drive(of: path), !d.connected { return "On \(d.name), which isn't connected" }
    return "Can't be found"
}

// MARK: - Finding games

struct Found: Identifiable, Equatable {
    enum Kind: Equatable { case app(String), rom(String), choose([String]), switchFile }
    let url: URL, name: String, kind: Kind, source: String
    var id: String { url.path }
    var console: String? { switch kind { case .app(let t): return consoleOf(t); case .rom(let c): return c; case .choose: return nil; case .switchFile: return "switch" } }
}

enum Discover {
    // Every file a few levels under these folders. Apps are not looked inside, nor hidden or build folders.
    static func files(in dirs: [URL], depth: Int = 5, limit: Int = 20000) -> [URL] {
        var out: [URL] = []
        for d in dirs {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: d.path, isDirectory: &isDir) else { continue }
            guard isDir.boolValue, d.pathExtension.lowercased() != "app" else { out.append(d); continue }
            guard let e = FileManager.default.enumerator(at: d, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let u as URL in e {
                if out.count >= limit { return out }
                let folder = (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if folder, u.pathExtension.lowercased() == "app" { e.skipDescendants() }
                else if folder {
                    if e.level >= depth || u.lastPathComponent.hasSuffix("_build") || u.lastPathComponent.hasSuffix(".partial") || u.standardizedFileURL.path == RetroArch.home.standardizedFileURL.path { e.skipDescendants() }
                    continue
                }
                out.append(u)
            }
        }
        return out
    }

    // What each file is. Known paths, and files that are only part of another game, are left out.
    static func look(_ urls: [URL], source: String, known: Set<String>, apps: Bool = true, roms: Bool = true, switchFiles: Bool = false) -> [Found] {
        var out: [Found] = []
        let kept = Set(urls.filter { ["cue", "gdi", "m3u", "ccd"].contains($0.pathExtension.lowercased()) }.flatMap { Organize.companions($0) }.map(\.path))
        for u in pickRoms(urls) where !known.contains(u.standardizedFileURL.path) && !kept.contains(u.standardizedFileURL.path) {
            let e = u.pathExtension.lowercased()
            if e == "app" {
                guard apps, let p = appInfo(u), let t = p["DMTitleID"] as? String else { continue }
                out.append(Found(url: u, name: p["CFBundleName"] as? String ?? u.deletingPathExtension().lastPathComponent, kind: .app(t), source: source))
            } else if packageTypes.contains(e) {
                if switchFiles { out.append(Found(url: u, name: cleanName(u), kind: .switchFile, source: source)) }
            } else if roms {
                let c = consolesFor(u)
                if c.count == 1 { out.append(Found(url: u, name: cleanName(u), kind: .rom(c[0].id), source: source)) }
                else if c.count > 1 { out.append(Found(url: u, name: cleanName(u), kind: .choose(c.map(\.id)), source: source)) }
            }
        }
        return out
    }

    static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }
    static var support: URL { home.appendingPathComponent("Library/Application Support") }

    // Games RetroArch knows, from its playlists
    static func retroArchGames(_ dir: URL = support.appendingPathComponent("RetroArch/playlists")) -> [URL] {
        let lists = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "lpl" }
        var out: [URL] = []
        for l in lists {
            guard let d = try? Data(contentsOf: l), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let items = o["items"] as? [[String: Any]] else { continue }
            for i in items { if let p = i["path"] as? String { let f = String(p.split(separator: "#", maxSplits: 1).first ?? ""); if !f.isEmpty, FileManager.default.fileExists(atPath: f) { out.append(URL(fileURLWithPath: f)) } } }
        }
        return out
    }
    // Folders Ryujinx was told to look in for Switch games
    static func ryujinxFolders(_ config: URL = support.appendingPathComponent("Ryujinx/Config.json")) -> [URL] {
        guard let d = try? Data(contentsOf: config), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return ((o["game_dirs"] as? [String]) ?? []).map { URL(fileURLWithPath: $0) }
    }

    // Everywhere games are usually kept on a Mac, without places macOS asks permission for (Desktop, Documents, Downloads)
    static func onThisMac(known: Set<String>, lib: URL) -> [Found] {
        let apps = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"), Paths.root, lib]
        var out = look(files(in: apps, depth: 3), source: "Converted", known: known, roms: false)
        out += look(files(in: [support.appendingPathComponent("OpenEmu/Game Library/roms")], depth: 3), source: "OpenEmu", known: known, apps: false)
        out += look(retroArchGames(), source: "RetroArch", known: known, apps: false)
        out += look(files(in: ryujinxFolders(), depth: 3), source: "Ryujinx", known: known, apps: false, roms: false, switchFiles: true)
        let own = ["ROMs", "Roms", "roms", "Games", "Emulation"].map { home.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        out += look(files(in: own, depth: 4), source: "Your folders", known: known, apps: false)
        var seen = Set<String>(); return out.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }
}
