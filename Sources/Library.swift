import SwiftUI
import UniformTypeIdentifiers

// Bringing games into the library, keeping it organized, and following games that move or sit on a drive that comes and goes.

struct Importing: Equatable {
    var found: [Found] = []
    var picked = Set<String>()
    var console: [String: String] = [:]   // the console chosen for a file several consoles use
    var looking = true
    // New finds join the list; games already in the library under another copy start unticked
    mutating func add(_ f: [Found], have: Set<String>) {
        for x in f where !found.contains(where: { $0.id == x.id }) {
            found.append(x)
            switch x.kind { case .app(let t): if !have.contains(t.uppercased()) { picked.insert(x.id) }; case .rom: picked.insert(x.id); default: break }
        }
    }
    var chosen: [Found] {
        found.compactMap { f in
            guard picked.contains(f.id) else { return nil }
            if case .choose = f.kind { return console[f.id].map { Found(url: f.url, name: f.name, kind: .rom($0), source: f.source) } }
            if case .switchFile = f.kind { return nil }
            return f
        }
    }
}

struct PendingAdd: Identifiable { let id = UUID(); let found: [Found] }

extension Model {
    var ownedFolders: [URL] { [Paths.games, libraryFolder] + folders.map { URL(fileURLWithPath: $0) } }
    var knownPaths: Set<String> { Set(games.map { $0.url.standardizedFileURL.path }) }
    func inLibrary(_ u: URL) -> Bool { let p = u.standardizedFileURL.path; return ownedFolders.contains { p.hasPrefix($0.standardizedFileURL.path + "/") } }
    // A console's folder in the library, made when first needed
    func consoleFolder(_ c: String) -> URL { let u = Organize.folder(c, in: libraryFolder); try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u }

    // Asks how to bring games in, unless the player chose to be asked no more, or they are all in the library already
    func bringIn(_ found: [Found]) {
        guard !found.isEmpty else { return }
        if found.allSatisfy({ inLibrary($0.url) }) { take(found, mode: .leave); return }
        if let m = addMode { take(found, mode: m) } else { askingMode = PendingAdd(found: found) }
    }

    // Files games off the main thread, then adds them. A game already in the library is not copied again: its place is updated.
    func take(_ found: [Found], mode: AddMode, quiet: Bool = false) {
        let lib = libraryFolder, naming = naming, organized = organized, inside = Set(found.filter { inLibrary($0.url) }.map(\.id))
        let known = Dictionary(library.roms.map { ($0.id, $0.path) }, uniquingKeysWith: { a, _ in a })
        filing = found.count == 1 ? "Adding \(found[0].name)…" : "Adding \(found.count) games…"
        DispatchQueue.global(qos: .userInitiated).async {
            var roms: [Rom] = [], apps: [(String, String)] = [], failed: [String] = []
            for (n, f) in found.enumerated() {
                if found.count > 1, mode != .leave { DispatchQueue.main.async { self.filing = "Adding \(n + 1) of \(found.count)…" } }
                let m = inside.contains(f.id) ? AddMode.leave : mode
                do {
                    switch f.kind {
                    case .app(let t): apps.append((try Organize.fileApp(f.url, mode: m, organized: organized, in: lib).path, t))
                    case .rom(let c):
                        let id = romID(f.url, c)
                        if let p = known[id], FileManager.default.fileExists(atPath: p) { roms.append(Rom(id: id, name: f.name, console: c, path: p)); continue }
                        roms.append(Rom(id: id, name: f.name, console: c, path: try Organize.file(f.url, console: c, name: f.name, mode: m, naming: naming, organized: organized, in: lib).path))
                    default: break
                    }
                } catch { failed.append("\(f.name): \(error.localizedDescription)") }
            }
            DispatchQueue.main.async { self.filing = nil; self.added(roms: roms, apps: apps, failed: failed, quiet: quiet) }
        }
    }

    private func added(roms: [Rom], apps: [(String, String)], failed: [String], quiet: Bool) {
        let fresh = roms.filter { r in !library.roms.contains { $0.id == r.id } }
        var l = library; for r in roms { l.addRom(r) }; for (p, t) in apps { l.addApp(p, t) }; library = l
        reload()
        for c in consoles where roms.contains(where: { $0.console == c.id }) { getReady(roms.filter { $0.console == c.id }.map { URL(fileURLWithPath: $0.path) }, as: c) }
        lookUpAdded(fresh.map(\.id))
        let n = fresh.count + apps.count
        if quiet { if n > 0 { newlyAdded = n == 1 ? "\(fresh.first?.name ?? "A game") was added from a watched folder." : "\(n) games were added from your watched folders." } }
        else if n > 0 { let kinds = Set(roms.map(\.console) + apps.map { consoleOf($0.1) }); section = kinds.count == 1 ? .console(kinds.first!) : .all; if n > 1 { newlyAdded = "\(n) games were added." } }
        if !failed.isEmpty { message = (failed.count == 1 ? "One game couldn't be added. " : "\(failed.count) games couldn't be added. ") + failed.prefix(4).joined(separator: " ") }
    }

    // ---- watched folders: new games there are added where they are ----
    func lookInWatched(force: Bool = false) {
        guard !watched.isEmpty, force || Date().timeIntervalSince(lastWatch) > 90, filing == nil else { return }
        lastWatch = Date()
        let dirs = watched.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }   // a drive that isn't connected is skipped
        let known = knownPaths.union(library.removed).union(skipped)
        DispatchQueue.global(qos: .utility).async {
            let f = Discover.look(Discover.files(in: dirs), source: "Watched", known: known)
            DispatchQueue.main.async {
                let ok = f.filter { if case .choose = $0.kind { return false }; return true }
                self.skipped.formUnion(f.filter { x in !ok.contains(x) }.map(\.id))   // a file several consoles use waits for the player to drop it in
                if !ok.isEmpty { self.take(ok, mode: .leave, quiet: true) }
            }
        }
    }
    func addWatched() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.allowsMultipleSelection = true; p.prompt = "Watch"
        p.message = "Choose folders, on this Mac or a drive, where you keep games. Docked adds what's in them now and anything you put there later."
        guard p.runModal() == .OK else { return }
        for u in p.urls where !watched.contains(u.path) { watched.append(u.path) }
        lookInWatched(force: true)
    }

    // ---- Find Games on This Mac ----
    func findGames() {
        if showSettings { leaveSettings { self.findGames() }; return }
        guard !sheetUp else { return }
        importing = Importing()
        let known = knownPaths, lib = libraryFolder, have = Set(games.map { $0.titleID.uppercased() })
        DispatchQueue.global(qos: .userInitiated).async {
            let f = Discover.onThisMac(known: known, lib: lib)
            DispatchQueue.main.async { self.importing?.add(f, have: have); self.importing?.looking = false }
        }
    }
    func findIn() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.allowsMultipleSelection = true; p.prompt = "Look Here"
        p.message = "Choose a folder or drive with games in it."
        guard p.runModal() == .OK else { return }
        let urls = p.urls, known = knownPaths, have = Set(games.map { $0.titleID.uppercased() })
        importing?.looking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let f = urls.flatMap { u in Discover.look(Discover.files(in: [u]), source: FileManager.default.displayName(atPath: u.path), known: known, switchFiles: true) }
            DispatchQueue.main.async { self.importing?.add(f, have: have); self.importing?.looking = false }
        }
    }
    func addFound() {
        let c = importing?.chosen ?? []; importing = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.bringIn(c) }
    }
    func convertFound(_ f: Found) { importing = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.add([f.url]) } }

    // ---- Organize Library ----
    func planTidy() {
        if showSettings { leaveSettings { self.planTidy() }; return }
        guard organized, !sheetUp else { return }
        tidying = Organize.plan(games, owned: ownedFolders, lib: libraryFolder, naming: naming)
    }
    func tidy(_ list: [Tidy]) {
        tidying = nil
        guard !builder.running, moving == nil, filing == nil else { message = "Wait until Docked has finished its current job, then organize."; return }
        let busy = list.filter { isOpen($0.game) || isRunning($0.game) }, go = list.filter { t in !busy.contains(t) }
        let lib = libraryFolder, naming = naming, saves = ["saves", "states"].map { RetroArch.support.appendingPathComponent($0) }
        filing = "Organizing…"
        DispatchQueue.global(qos: .userInitiated).async {
            var moved: [(Tidy, URL)] = [], failed: [String] = []
            for (i, t) in go.enumerated() {
                DispatchQueue.main.async { self.filing = "Organizing \(i + 1) of \(go.count)…" }
                do {
                    if let r = t.game.rom {
                        let u = try Organize.file(t.game.url, console: r.console, name: t.game.name, mode: .move, naming: naming, in: lib)
                        Organize.carrySaves(from: t.game.url, to: u, in: saves, move: true); moved.append((t, u))
                    } else { moved.append((t, try Organize.fileApp(t.game.url, mode: .move, in: lib))) }
                } catch { failed.append("\(t.game.name): \(error.localizedDescription)") }
            }
            Organize.hideBuildFolders()
            DispatchQueue.main.async {
                self.filing = nil
                var l = self.library
                for (t, u) in moved {
                    if let r = t.game.rom, let i = l.roms.firstIndex(where: { $0.id == r.id }) { l.roms[i].path = u.path }
                    else if t.game.rom == nil { l.apps[t.game.url.path] = nil; l.apps[u.path] = t.game.titleID.uppercased() }
                }
                self.library = l; self.icons = [:]; self.covers = [:]; self.reload()
                var say: [String] = []
                if !busy.isEmpty { say.append("Quit \(busy.map(\.game.name).joined(separator: ", ")) and organize again to move \(busy.count == 1 ? "it" : "them").") }
                if !failed.isEmpty { say.append("These stayed where they were. " + failed.prefix(4).joined(separator: " ")) }
                if !say.isEmpty { self.message = say.joined(separator: "\n\n") } else if !moved.isEmpty { self.newlyAdded = moved.count == 1 ? "\(moved[0].0.game.name) is organized." : "\(moved.count) games are organized." }
            }
        }
    }

    // ---- the library folder, which can be on another drive ----
    func pickLibraryFolder() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true; p.directoryURL = libraryFolder; p.prompt = "Use This Folder"
        p.message = "Choose where your library lives. It can be on an external drive."
        guard p.runModal() == .OK, let u = p.url else { return }
        if let e = placeProblem(u) { message = e.localizedDescription; return }
        guard u.standardizedFileURL.path != libraryFolder.standardizedFileURL.path else { return }
        let old = libraryFolder
        if !folders.contains(old.path), old.path != Paths.games.path { folders.append(old.path) }   // games left in the old one stay in the library
        libraryFolder = u
        let left = organized ? Organize.plan(games, owned: ownedFolders, lib: u, naming: naming) : []
        guard !left.isEmpty else { return }
        let a = NSAlert(); a.messageText = "Move your games to the new library folder?"
        a.informativeText = "\(left.count) \(left.count == 1 ? "game is" : "games are") in Docked's folders elsewhere. You can see the list first. Games you keep in other places stay where they are."
        a.addButton(withTitle: "Show List"); a.addButton(withTitle: "Not Now")
        if a.runModal() == .alertFirstButtonReturn { leaveSettings { self.tidying = left } }
    }

    // ---- a game that moved ----
    func locate(_ g: Game) {
        let p = NSOpenPanel(); p.message = "Where is \(g.name) now?"; p.canChooseDirectories = false
        if g.rom == nil { p.allowedContentTypes = [.application] }
        var d = g.url.deletingLastPathComponent(); while !FileManager.default.fileExists(atPath: d.path), d.pathComponents.count > 1 { d.deleteLastPathComponent() }; p.directoryURL = d
        guard p.runModal() == .OK, let u = p.url else { return }
        var l = library
        if g.rom == nil {
            guard let t = titleID(of: u), t.uppercased() == g.titleID.uppercased() else { message = "That isn't \(g.name). Choose the game Docked converted."; return }
            l.apps[g.url.path] = nil; l.addApp(u.path, t)
        } else if let i = l.roms.firstIndex(where: { $0.id == g.titleID }) { l.roms[i].path = u.path }
        library = l; icons[g.id] = nil; covers[g.id] = nil; reload()
    }
}
