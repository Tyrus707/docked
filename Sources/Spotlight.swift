import AppKit
import CoreSpotlight
import UniformTypeIdentifiers

// Games in Spotlight: type a game's name and press Return, and it opens through Docked (so its play time counts).
extension Model {
    func refreshSpotlight() {
        let on = spotlight, list = on ? games.filter { !$0.missing && $0.away == nil } : []
        let sig = list.map { $0.id + "|" + $0.name }.joined(separator: "\n")
        guard sig != spotlightSig else { return }; spotlightSig = sig
        let items = list.map { g -> CSSearchableItem in
            let a = CSSearchableItemAttributeSet(contentType: UTType.application)
            a.title = g.name; a.displayName = g.name
            a.contentDescription = "Play in Docked · " + consoleName(g.rom?.console ?? consoleOf(g.titleID))
            a.keywords = [consoleName(g.rom?.console ?? consoleOf(g.titleID)), "game", "Docked"]
            return CSSearchableItem(uniqueIdentifier: g.id, domainIdentifier: "games", attributeSet: a)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: ["games"]) { _ in if !items.isEmpty { index.indexSearchableItems(items) { _ in } } }
    }
    // A Spotlight result, or a docked:// link
    func openSpotlight(_ a: NSUserActivity) {
        guard let id = a.userInfo?[CSSearchableItemActivityIdentifier] as? String, let g = games.first(where: { $0.id == id }) else { return }
        select(g); play(g)
    }
    func open(_ u: URL) {
        guard let l = DockedLink.parse(u) else { tell("Docked doesn't know that link.", good: false); return }
        switch l {
        case let .play(id, name):
            guard let g = gameFor(id: id, name: name, in: games) else { tell("No game in your library matches \(name ?? id ?? "that").", good: false); return }
            select(g); play(g)
        case .resume:
            guard let g = games.filter({ !$0.missing }).max(by: { (library.entry($0.titleID).lastPlayed ?? .distantPast) < (library.entry($1.titleID).lastPlayed ?? .distantPast) }), library.entry(g.titleID).lastPlayed != nil else { tell("You haven't played anything yet.", good: false); return }
            select(g); play(g)
        case .couch: if !couch { toggleCouch() }
        case .health: checkHealth()
        case let .join(i): joinOnline(i)
        case let .tv(r): tvLink(r)
        }
    }
    func copyLink(_ g: Game) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(DockedLink.play(g.titleID), forType: .string)
        tell("Link copied. In Shortcuts, use Open URLs with it to start \(g.name) from anywhere.")
    }
}

// A TV stream starting or ending (TVDisplay.swift)
extension Model {
    func tvLink(_ r: TVRequest) {
        let tv = TVDisplay.shared
        guard r.start else {
            tv.stop(); StreamingSound.back()
            if tv.madeCouch { tv.madeCouch = false; leaveCouch() }
            return
        }
        let ready = { try? Data().write(to: StreamingPaths.ready) }   // tv.sh stops waiting; Sunshine starts the picture
        guard streaming.on else { ready(); return }
        StreamingSound.toTV()
        tv.start(width: r.width, height: r.height, fps: r.fps) { [weak self] in
            ready()
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            if let id = r.play {
                if let g = gameFor(id: id, name: nil, in: games), !g.missing { select(g); play(g) }
                else { tell("That game isn't in your library now.", good: false) }
            } else if r.couch, !couch {
                // Full screen goes on the TV-sized screen, once it is the main one
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, !self.couch else { return }
                    self.enterCouch(); tv.madeCouch = self.couch
                }
            }
        }
    }
}
