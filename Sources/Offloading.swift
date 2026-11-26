import AppKit

// Offloading games to free space on this Mac, and downloading them again. See Offload.swift.
extension Model {
    var offloadFolder: URL? {
        get { UserDefaults.standard.string(forKey: "offloadFolder").map { URL(fileURLWithPath: Paths.now($0)) } }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue?.path, forKey: "offloadFolder") }
    }
    var offloadedCount: Int { games.filter { $0.away != nil }.count }

    // Where offloaded games go. A folder in the library, or one Docked watches, would bring them straight back, so those are refused.
    @discardableResult func pickOffloadFolder() -> URL? {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true; p.prompt = "Offload Here"
        let icloud = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs")
        p.directoryURL = offloadFolder ?? (FileManager.default.fileExists(atPath: icloud.path) ? icloud : nil)
        p.message = "Choose where offloaded games go: iCloud Drive, a Dropbox or Google Drive folder, or an external drive. Docked keeps them in a Docked Games folder there."
        guard p.runModal() == .OK, var u = p.url else { return nil }
        if let e = placeProblem(u) { message = e.localizedDescription; return nil }
        if u.lastPathComponent != "Docked Games" { u.appendPathComponent("Docked Games", isDirectory: true); try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true) }
        let path = u.standardizedFileURL.path
        if inLibrary(u.appendingPathComponent("x")) || ownedFolders.contains(where: { $0.standardizedFileURL.path == path }) || watched.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            message = "That folder is part of your library, so games offloaded there would come straight back. Choose a folder outside it."; return nil
        }
        offloadFolder = u; return u
    }

    // ---- Offload: the files go, the tile stays ----
    func offload(_ list: [Game]) {
        let go = list.filter { !$0.missing && $0.away == nil }
        guard !go.isEmpty else { return }
        guard moving == nil, filing == nil else { tell("Wait until Docked has finished its current job, then offload.", good: false); return }
        var root = offloadFolder
        if let r = root, placeProblem(r) != nil {
            if let d = drive(of: r.path), !d.connected {
                let a = NSAlert(); a.messageText = "\(d.name) isn't connected"; a.informativeText = "Connect it to offload games there, or choose another place."
                a.addButton(withTitle: "Choose Another Place…"); a.addButton(withTitle: "Cancel")
                guard a.runModal() == .alertFirstButtonReturn else { return }
            }
            root = nil
        }
        if root == nil { root = pickOffloadFolder() }
        guard let root else { return }
        let busy = go.filter { isOpen($0) || isRunning($0) }, send = go.filter { g in !busy.contains(g) }, place = offloadName(root.path)
        if send.isEmpty { message = "Quit \(busy.map(\.name).joined(separator: ", ")) first, then offload."; return }
        for g in send { snapshotSave(g, "before offload") }
        filing = send.count == 1 ? "Offloading \(send[0].name)…" : "Offloading \(send.count) games…"
        DispatchQueue.global(qos: .userInitiated).async {
            var sent: [(Game, URL)] = [], failed: [String] = []
            for (i, g) in send.enumerated() {
                if send.count > 1 { DispatchQueue.main.async { self.filing = "Offloading \(i + 1) of \(send.count)…" } }
                if g.rom == nil { Artwork.keepAppIcon(g.titleID, from: g.url) }   // keep the art before its app leaves this Mac
                do { sent.append((g, try Offload.send(g.url, console: g.rom?.console ?? consoleOf(g.titleID), set: g.rom != nil, to: root))) }
                catch { failed.append("\(g.name): \(error.localizedDescription)") }
            }
            DispatchQueue.main.async {
                self.filing = nil
                var l = self.library; for (g, u) in sent { l.offloaded[g.url.path] = u.path }; self.library = l
                self.reload(); self.sizes = [:]
                if !sent.isEmpty { self.evictOffloaded(force: true) }
                var say: [String] = []
                if !busy.isEmpty { say.append("Quit \(busy.map(\.name).joined(separator: ", ")) to offload \(busy.count == 1 ? "it" : "them").") }
                if !failed.isEmpty { say.append("These stayed on this Mac. " + failed.prefix(4).joined(separator: " ")) }
                if !say.isEmpty { self.message = say.joined(separator: "\n\n") }
                if !sent.isEmpty {
                    let what = sent.count == 1 ? "\(sent[0].0.name) is offloaded to \(place)." : "\(sent.count) games are offloaded to \(place)."
                    let detail = what + (drive(of: root.path) == nil ? " It leaves this Mac once \(place) has uploaded it. Saves stay here." : " Saves stay on this Mac.")
                    self.tell(detail); self.logActivity("Games offloaded", detail: detail)
                }
            }
        }
    }

    // A cloud folder keeps its own copy here until it has uploaded; this asks it to let go, now and again later
    func evictOffloaded(force: Bool = false) {
        struct Last { static var at = Date.distantPast }
        guard force || Date().timeIntervalSince(Last.at) > 600 else { return }
        Last.at = Date()
        let away = library.offloaded.values.map { URL(fileURLWithPath: $0) }.filter { drive(of: $0.path) == nil }
        guard !away.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { for u in away { Cloud.evict(u) } }
        if force { for s in [90.0, 600] { DispatchQueue.main.asyncAfter(deadline: .now() + s) { self.evictOffloaded(force: s < 600) } } }
    }

    // Play on an offloaded game: bring it back first
    func askDownload(_ g: Game, settings: Bool = false) {
        guard let away = g.away else { return }
        let a = NSAlert(); a.messageText = "Download \(g.name) to play?"
        a.informativeText = "It's offloaded to \(offloadName(away)). Docked brings it back to this Mac, then starts it."
        a.addButton(withTitle: "Download and Play"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { download([g]) { self.play($0, settings: settings) } }
    }

    // ---- Download: back to its place on this Mac, or into the library folder when that place is on a drive that isn't here ----
    func download(_ list: [Game], then: ((Game) -> Void)? = nil) {
        let go = list.filter { $0.away != nil }
        guard !go.isEmpty else { return }
        guard moving == nil, filing == nil else { tell("Wait until Docked has finished its current job, then download.", good: false); return }
        let off = go.filter { drive(of: $0.away!)?.connected == false }
        if off.count == go.count { message = "Connect \(drive(of: off[0].away!)!.name) to download \(off.count == 1 ? off[0].name : "these games")."; return }
        let get = go.filter { g in !off.contains(g) }, lib = libraryFolder
        filing = "Downloading \(get[0].name)…"
        DispatchQueue.global(qos: .userInitiated).async {
            var back: [(Game, URL)] = [], failed: [String] = []
            for (i, g) in get.enumerated() {
                let away = URL(fileURLWithPath: g.away!), name = offloadName(away.path)
                var home = g.url
                if let d = drive(of: home.path), !d.connected { home = Organize.free((g.rom == nil ? Organize.folder(consoleOf(g.titleID), in: lib) : Organize.folder(g.rom!.console, in: lib)).appendingPathComponent(home.lastPathComponent)) }
                let head = get.count > 1 ? "Downloading \(i + 1) of \(get.count)" : "Downloading \(g.name)"
                DispatchQueue.main.async { self.filing = head + "…" }
                do {
                    guard Cloud.exists(away) else { throw OffloadError.gone(name) }
                    let left = Cloud.waiting(away).left, need = left + (sameVolume(away, home.deletingLastPathComponent()) ? 0 : folderSize(away)), free = freeSpace(at: home)
                    if need > 0, free < need + 500_000_000 { throw OffloadError.room(need, free) }
                    try Cloud.fetch(away, from: name) { p in DispatchQueue.main.async { self.filing = "\(head), \(Int(p * 100))%…" } }
                    try Offload.bring(away, home: home)
                    back.append((g, home))
                } catch { failed.append("\(g.name): \(error.localizedDescription)") }
            }
            DispatchQueue.main.async {
                self.filing = nil
                var l = self.library
                for (g, home) in back {
                    l.offloaded[g.url.path] = nil
                    guard home != g.url else { continue }
                    if let i = l.roms.firstIndex(where: { $0.id == g.titleID }), g.rom != nil { l.roms[i].path = home.path } else { l.apps[g.url.path] = nil; l.addApp(home.path, g.titleID) }
                }
                self.library = l
                for (g, _) in back { self.icons[g.id] = nil }
                self.reload()
                var say: [String] = []
                if !off.isEmpty { say.append("Connect \(drive(of: off[0].away!)!.name) to download \(off.map(\.name).joined(separator: ", ")).") }
                if !failed.isEmpty { say.append("These are still offloaded. " + failed.prefix(4).joined(separator: " ")) }
                if !say.isEmpty { self.message = say.joined(separator: "\n\n") }
                if back.count == 1, let then, let g = self.games.first(where: { $0.url.path == back[0].1.path }) { then(g) }
                else if !back.isEmpty { self.tell(back.count == 1 ? "\(back[0].0.name) is back on this Mac." : "\(back.count) games are back on this Mac.") }
            }
        }
    }
}
