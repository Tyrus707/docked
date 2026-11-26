import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Saves, cheats, the game's log, and what Docked says when a game closes unexpectedly. The files are the engine's own (GameData.swift).
struct SaveMenu: View {
    @EnvironmentObject var model: Model
    let game: Game
    var body: some View {
        let d = GameData(game.titleID), list = d.list()
        Menu("Saves") {
            Button("Back Up Now") { model.backUpSave(game) }.disabled(!d.hasSave)
            Menu("Restore a Backup") {
                ForEach(Array(list.prefix(12)), id: \.url) { b in Button("\(b.date.formatted(date: .abbreviated, time: .shortened)), \(ByteCountFormatter.string(fromByteCount: b.bytes, countStyle: .file))") { model.restoreSave(game, from: b.url) } }
            }.disabled(list.isEmpty)
            Button("Import Save…") { model.importSave(game) }
            Divider()
            Button("Show Saves in Finder") { model.reveal(d.hasSave ? d.save : d.root) }
        }
        Menu("Cheats") {
            Button("Add Cheat File…") { model.addCheat(game) }
            Button("Show Cheats in Finder") { try? FileManager.default.createDirectory(at: d.cheats, withIntermediateDirectories: true); model.reveal(d.cheats) }
        }
        Button("Show Game Log") { model.reveal(d.log) }.disabled(!FileManager.default.fileExists(atPath: d.log.path))
    }
}

extension Model {
    // The removable drives the library's games are on, and whether each is plugged in now: one look per drive, not per game
    var drivesInUse: [(name: String, connected: Bool)] {
        var names: [String] = []
        for g in games { let p = (g.url.path as NSString).pathComponents; if p.count > 2, p[1] == "Volumes", !names.contains(p[2]) { names.append(p[2]) } }
        return names.sorted().map { ($0, FileManager.default.fileExists(atPath: "/Volumes/" + $0)) }
    }

    func reveal(_ u: URL) { if FileManager.default.fileExists(atPath: u.path) { NSWorkspace.shared.activateFileViewerSelecting([u]) } else { _ = NSWorkspace.shared.open(u.deletingLastPathComponent()) } }

    func backUpSave(_ g: Game) {
        do { if try GameData(g.titleID).backUp() != nil { tell("\(g.name)'s save is backed up.") } else { tell("\(g.name) has no save yet.", good: false) } }
        catch { message = "Docked couldn't back up \(g.name)'s save. \(error.localizedDescription)" }
    }

    // Always asked first, with the save's date and size: the newer save is not always the one with more progress.
    func restoreSave(_ g: Game, from u: URL) {
        guard !isOpen(g) else { message = "Save and quit \(g.name) first."; return }
        guard let src = GameData.saveIn(u) else { message = "That folder has no save in it."; return }
        let when = ((try? src.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()).formatted(date: .abbreviated, time: .shortened)
        let a = NSAlert(); a.messageText = "Use this save for \(g.name)?"
        a.informativeText = "From \(when), \(ByteCountFormatter.string(fromByteCount: GameData.size(src), countStyle: .file)). Docked backs up the save you have now first, so you can go back to it."
        a.addButton(withTitle: "Use This Save"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { try GameData(g.titleID).restore(src); tell("\(g.name) will start from that save.") }
        catch { message = "Docked couldn't bring in that save. Your save is as it was. \(error.localizedDescription)" }
    }

    func importSave(_ g: Game) {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.prompt = "Use"
        p.message = "Choose a save folder for \(g.name), or a backup that holds one."
        guard p.runModal() == .OK, let u = p.url else { return }
        restoreSave(g, from: u)
    }

    func addCheat(_ g: Game) {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.allowedContentTypes = [.plainText]; p.prompt = "Add"
        p.message = "Choose cheat files for \(g.name). They're named after the game's build, like 0123456789ABCDEF.txt."
        guard p.runModal() == .OK else { return }
        var added = 0, odd: [String] = []
        for u in p.urls { if (try? GameData(g.titleID).addCheat(u)) != nil { added += 1; if !GameData.isCheatFile(u) { odd.append(u.lastPathComponent) } } }
        if !odd.isEmpty { tell("\(odd.joined(separator: ", ")) isn't named after a game build, so the game may not find it.", good: false) }
        else if added > 0 { tell("Cheats added. Turn them on from the game's Cheats menu while it plays.") }
    }

    func applyCloudSaves(was: String) { for g in games where g.rom == nil && !g.missing { CloudSaves.apply(cloudSaves, was: was, to: g.url) } }

    func pickCloudSaves() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true; p.prompt = "Use"
        p.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs")
        p.message = "Choose a folder in iCloud Drive (or another synced folder). Each game keeps one file there."
        if p.runModal() == .OK, let u = p.url { cloudSaves = u.path }
    }

    func refreshCompat() { guard lookUp == true, Compat.stale else { return }; Compat.refresh { [weak self] in self?.compat = $0 } }

    // After a game closes: a crash report from while it ran means it didn't close by itself.
    func checkCrash(_ id: String, since: Date) {
        guard let g = games.first(where: { $0.titleID.uppercased() == id && $0.rom == nil }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in   // the report is written a moment after the game ends
            DispatchQueue.global(qos: .utility).async {
                guard crashReport(for: g.url, since: since) != nil else { return }
                DispatchQueue.main.async { self?.tell("\(g.name) closed unexpectedly. Your save is from its last save point. Show Game Log in its ••• menu has the details.", good: false) }
            }
        }
    }
}
