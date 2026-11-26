import SwiftUI
import AVFoundation

// Couch Mode: the library full screen, for a controller and a TV. Several shelves at a time, the chosen game's art filling the room.
// It is drawn over the library in the same window, which goes properly full screen (a Space of its own) while it is open,
// so sheets and questions still appear on top of it. Leaving puts the window back as it was.

struct CouchShelf {
    var id: String, name: String, games: [Game], note: String? = nil
    var ids: [String] = []   // the games by id, worked out once, so a move does not walk the whole shelf
    var sig = 0              // changes only when the games, or whether one is connected, change
    init(id: String, name: String, games: [Game], note: String? = nil) {
        self.id = id; self.name = name; self.games = games; self.note = note; ids = games.map(\.id)
        var h = Hasher(); for g in games { h.combine(g.id); h.combine(g.missing) }; sig = h.finalize()
    }
}

extension Model {
    // Worked out once and kept until the games or the library change, not on every press of the D-pad.
    var couchShelves: [CouchShelf] {
        if let s = memo.couch { return s }
        let s = makeCouchShelves(); memo.couch = s; return s
    }

    // Continue and Favorites first, then the collections Docked fills itself, then the player's own shelves, with everything last.
    private func makeCouchShelves() -> [CouchShelf] {
        var r = [CouchShelf(id: "continue", name: "Continue Playing", games: Array(shown(.all, by: .recent).prefix { library.entry($0.titleID).lastPlayed != nil }.prefix(15)), note: "Pick up where you left off"),
                 CouchShelf(id: "favorites", name: "Favorites", games: shown(.favorites, by: .recent), note: "Your hearted games")]
        r.append(contentsOf: couchCuratedShelves)
        for c in consolesShown { r.append(CouchShelf(id: "console:" + c.id, name: c.name, games: shown(.console(c.id)))) }
        for c in library.collections { r.append(CouchShelf(id: "collection:" + c, name: c, games: shown(.collection(c)), note: "Your collection")) }
        for s in library.smart { r.append(CouchShelf(id: "smart:" + s.name, name: s.name, games: shown(.smart(s)), note: "Your smart collection")) }
        r.append(CouchShelf(id: "all", name: "All Games", games: shown(.all), note: "Everything in your library"))
        return r.filter { !$0.games.isEmpty }
    }

    // Collections that fill themselves from details already on this Mac (critic scores, years, readers, play time, stars).
    // Nothing new is looked up. A collection with too few games to be worth a row stays hidden.
    var couchCuratedShelves: [CouchShelf] {
        let all = shown(.all, by: .critic)
        func critic(_ g: Game) -> Int? { library.entry(g.titleID).meta?.critic }
        func best(_ l: [Game]) -> [Game] {   // by critics, then by how many people read about it, then the player's stars
            l.sorted { a, b in
                let x = library.entry(a.titleID), y = library.entry(b.titleID)
                if (x.meta?.critic ?? -1) != (y.meta?.critic ?? -1) { return (x.meta?.critic ?? -1) > (y.meta?.critic ?? -1) }
                if (x.meta?.views ?? 0) != (y.meta?.views ?? 0) { return (x.meta?.views ?? 0) > (y.meta?.views ?? 0) }
                return x.rating > y.rating
            }
        }
        var r: [CouchShelf] = []
        let acclaimed = all.filter { (critic($0) ?? -1) >= 85 || library.entry($0.titleID).rating >= 5 }
        if acclaimed.count >= 3 { r.append(CouchShelf(id: "acclaimed", name: "Critically Acclaimed", games: Array(acclaimed.prefix(30)), note: "Scored 85 or more, or five stars from you")) }
        // One row per decade, newest last, each with its best-reviewed games first
        let byDecade = Dictionary(grouping: all.filter { library.year($0) != nil }) { (library.year($0)! / 10) * 10 }
        for d in byDecade.keys.sorted() where byDecade[d]!.count >= 4 {
            guard let name = couchDecadeName(d) else { continue }
            r.append(CouchShelf(id: "decade:\(d)", name: name, games: Array(best(byDecade[d]!).prefix(30)), note: "Released \(d) to \(d + 9)"))
        }
        // Well reviewed but read about by fewer people than most of the library
        let views = all.compactMap { library.entry($0.titleID).meta?.views }.sorted(), middle = views.isEmpty ? 0 : views[views.count / 2]
        let gems = all.filter { g in
            guard let c = critic(g), c >= 75 else { return false }
            let e = library.entry(g.titleID); return !e.favorite && (e.meta?.views.map { $0 <= middle } ?? true)
        }
        if gems.count >= 3 { r.append(CouchShelf(id: "gems", name: "Hidden Gems", games: Array(gems.prefix(30)), note: "Well reviewed and easy to miss")) }
        let fresh = best(all.filter { library.entry($0.titleID).lastPlayed == nil && !$0.missing })
        if fresh.count >= 3 { r.append(CouchShelf(id: "unplayed", name: "Not Played Yet", games: Array(fresh.prefix(30)), note: "Waiting on your shelf")) }
        let month = Date().addingTimeInterval(-60 * 86400)
        let back = all.filter { let e = library.entry($0.titleID); return e.seconds >= 3600 && (e.lastPlayed.map { $0 < month } ?? false) }
            .sorted { library.entry($0.titleID).seconds > library.entry($1.titleID).seconds }
        if back.count >= 3 { r.append(CouchShelf(id: "rediscover", name: "Rediscover", games: Array(back.prefix(30)), note: "Games you loved, not played in a while")) }
        return r
    }
    func couchYear(_ g: Game) -> Int? { library.year(g) }   // the same year the library sorts and groups by
    func couchRows(_ shelves: [CouchShelf]) -> [(id: String, games: [String])] { shelves.map { (id: $0.id, games: $0.ids) } }

    func couchSelection(_ shelves: [CouchShelf]? = nil, spot: CouchSpot? = nil) -> (shelf: CouchShelf, index: Int, game: Game)? {
        let l = shelves ?? couchShelves
        let p = (spot ?? couchSpot).resolved(couchRows(l))
        guard l.indices.contains(p.shelf) else { return nil }
        let s = l[p.shelf], i = p.index(s.id, s.ids); guard s.games.indices.contains(i) else { return nil }
        return (s, i, s.games[i])
    }
    func couchGame(_ shelves: [CouchShelf]? = nil) -> Game? { couchSelection(shelves)?.game }

    // A sheet or question on the window is answered first; Couch Mode waits under it.
    var couchCovered: Bool { sheetUp || missingGame != nil || askLookUp || asking != nil || askingMode != nil || collecting != nil || retitling != nil || renaming != nil }
    private var libraryWindow: NSWindow? { NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.canBecomeMain && $0.isVisible } }

    func toggleCouch() { if couch { leaveCouch() } else { enterCouch() } }

    func enterCouch() {
        guard !couch, !games.isEmpty, !couchCovered, let w = libraryWindow else { return }
        couchSaved = search; search = ""   // the shelves show everything
        couchSpot = couchSpot.resolved(couchRows(couchShelves))
        couch = true
        w.makeFirstResponder(nil)   // out of the search field, so the arrows move around the shelves
        w.toolbar?.isVisible = false
        couchMadeFull = !w.styleMask.contains(.fullScreen)
        if couchMadeFull { w.collectionBehavior.insert(.fullScreenPrimary); w.toggleFullScreen(nil) }
        if couchSounds { couchSound.start() }; chime(.open)
        NSCursor.setHiddenUntilMouseMoves(true)
        couchPoke(); themeUpdate()
    }

    func leaveCouch() {
        guard couch else { return }
        couch = false; couchTimer?.invalidate(); couchTimer = nil; couchIdle = false
        chime(.back); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in if self?.couch == false { self?.couchSound.stop() } }
        if let s = couchSaved { search = s }; couchSaved = nil
        if let w = libraryWindow { w.toolbar?.isVisible = true; if couchMadeFull, w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) } }
        couchMadeFull = false
        couchArts = [:]; couchArtOrder = []   // the big pictures are let go
        themeUpdate()
    }

    // Back from a game: the same cover, still full screen
    func couchBack() { couchPoke(); themeUpdate() }

    // After a while with nothing pressed, the words and buttons fade and only the art and the game's name stay.
    func couchPoke() {
        if couchIdle { couchIdle = false }
        couchTimer?.invalidate()
        couchTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in if self?.couch == true { self?.couchIdle = true } }
    }
    func chime(_ k: CouchSound.Kind) { if couchSounds { couchSound.start(); couchSound.play(k) } }

    func couchFocus(_ shelf: Int, _ i: Int) {
        let shelves = couchShelves; guard shelves.indices.contains(shelf), shelves[shelf].games.indices.contains(i) else { return }
        let s = shelves[shelf], g = s.games[i]
        var spot = couchSpot
        let changed = spot.shelfID != s.id
        spot.shelf = shelf; spot.shelfID = s.id; spot.at[s.id] = i; spot.gameID[s.id] = g.id; spot.game = g.id
        guard spot != couchSpot else { return }
        couchSpot = spot; chime(changed ? .shelf : .move); couchPoke(); themeUpdate()
    }
    func couchFocusShelf(_ id: String) {
        let shelves = couchShelves; guard let n = shelves.firstIndex(where: { $0.id == id }) else { return }
        let spot = couchSpot.resolved(couchRows(shelves))
        couchFocus(n, spot.index(id, shelves[n].ids))
    }

    func couchMove(_ m: Move, pad: Bool) {
        if pad != padUsed { padUsed = pad }
        let wasIdle = couchIdle; couchPoke()
        guard !couchCovered else { return }
        if message != nil { if m == .accept || m == .back || m == .play { message = nil; chime(.back) }; return }
        if wasIdle, m != .back { return }   // the first press only wakes it
        let shelves = couchShelves
        switch m {
        case .left, .right, .up, .down, .nextSection, .previousSection:
            let n = couchStep(couchSpot, m, rows: couchRows(shelves))
            if n != couchSpot { let other = n.shelfID != couchSpot.shelfID; couchSpot = n; chime(other ? .shelf : .move); themeUpdate() }
        case .accept, .play:
            guard let g = couchGame(shelves) else { return }
            chime(.play); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.play(g) }
        case .favorite:
            guard let g = couchGame(shelves) else { return }
            let on = !library.entry(g.titleID).favorite; edit(g) { $0.favorite = on }
            couchSpot = couchSpot.resolved(couchRows(couchShelves))   // a Favorites or Hidden Gems row may have come or gone
            chime(.favorite)
        case .back: leaveCouch()
        case .home: break
        }
    }

    // ---- the big picture behind the chosen game ----
    // The best art already on this Mac, at a size worth showing across a TV: an in-game picture for an older game or the
    // eShop banner for a Switch game, else its box art, a picture the player chose, or the game's own icon. Loaded in the background, a few kept.
    func couchArt(_ g: Game) -> NSImage? {
        if let a = couchArts[g.id] { return a }
        guard couchTried.insert("art" + g.id).inserted else { return nil }
        let snap = g.rom.map { CouchArt.snap($0) } ?? CouchArt.banner(g.titleID), places = [snap, Cover.custom(g), Artwork.appIcon(g.titleID), g.rom.flatMap { RetroArch.art($0) }, g.url.appendingPathComponent("Contents/Resources/AppIcon.icns")].compactMap { $0 }
        Cover.work.addOperation {
            let a = places.lazy.compactMap { CouchArt.load($0) }.first
            DispatchQueue.main.async {
                self.couchTried.remove("art" + g.id)
                guard self.couch, let a else { return }
                self.couchArts[g.id] = a; self.couchArtOrder.append(g.id)
                if self.couchArtOrder.count > 12 { self.couchArts[self.couchArtOrder.removeFirst()] = nil }
                self.couchArtTick += 1
            }
        }
        if g.rom == nil, lookUp == true, CouchArt.switchID(g.titleID), !FileManager.default.fileExists(atPath: CouchArt.banner(g.titleID).path), couchTried.insert("snap" + g.id).inserted {
            Lookup.queue.async { if CouchArt.fetchBanner(g.titleID) { DispatchQueue.main.async { self.couchArts[g.id] = nil; if self.couch { _ = self.couchArt(g) } } } }
        }
        if let r = g.rom, lookUp == true, let info = r.info, !FileManager.default.fileExists(atPath: CouchArt.snap(r).path), couchTried.insert("snap" + g.id).inserted {
            Lookup.queue.async { if CouchArt.fetchSnap(r, names: [info.title, URL(fileURLWithPath: r.path).deletingPathExtension().lastPathComponent]) { DispatchQueue.main.async { self.couchArts[g.id] = nil; if self.couch { _ = self.couchArt(g) } } } }
        }
        return nil
    }
}

enum CouchArt {
    static func snap(_ r: Rom) -> URL { Lookup.home.appendingPathComponent("Snaps/" + r.id.replacingOccurrences(of: ":", with: "-") + ".png") }
    // At most 1920 pixels across, so a big picture costs little memory
    static func load(_ u: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: u.path), let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        let n = CGImageSourceGetCount(src), best = (0..<n).max { a, b in ((CGImageSourceCopyPropertiesAtIndex(src, a, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int ?? 0) < ((CGImageSourceCopyPropertiesAtIndex(src, b, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int ?? 0) } ?? 0
        let o = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1920, kCGImageSourceCreateThumbnailWithTransform: true] as [CFString: Any] as CFDictionary
        guard let c = CGImageSourceCreateThumbnailAtIndex(src, best, o) else { return nil }
        return NSImage(cgImage: c, size: NSSize(width: c.width, height: c.height))
    }
    // A Switch game's wide eShop banner (1920 x 1080), from the nlib title API, which serves Nintendo's own store art by title ID.
    // Only the title ID is sent, and only when the player allowed lookups. Kept in Docked/Metadata/Banners.
    static func switchID(_ t: String) -> Bool { t.count == 16 && t.allSatisfy(\.isHexDigit) }
    static func banner(_ titleID: String) -> URL { Lookup.home.appendingPathComponent("Banners/" + titleID.uppercased() + ".jpg") }
    static var banners = "https://api.nlib.cc/nx/"
    static func fetchBanner(_ titleID: String) -> Bool {
        guard switchID(titleID), let u = URL(string: banners + titleID.uppercased() + "/banner/1080p"), let d = try? Lookup.get(u, limit: 8 << 20),
              d.starts(with: [0xFF, 0xD8, 0xFF]) || d.starts(with: [0x89, 0x50, 0x4E, 0x47]), let src = CGImageSourceCreateWithData(d as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any], let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int, w >= 320, w <= 4096, h >= 180, h <= 4096 else { return false }
        let out = banner(titleID); try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? d.write(to: out, options: .atomic)) != nil
    }
    // An in-game picture from libretro's collection, at the same fixed commit as the covers. Only when the player allowed lookups.
    static func fetchSnap(_ r: Rom, names: [String]) -> Bool {
        guard let c = console(r.console), let commit = Lookup.covers[c.folder] else { return false }
        let repo = c.folder.replacingOccurrences(of: " ", with: "_")
        for n in names { if let d = try? Lookup.get(Lookup.url("libretro-thumbnails/\(repo)/\(commit)/Named_Snaps/\(Lookup.thumbnail(n)).png"), limit: 8 << 20), Lookup.keep(d, at: snap(r)) { return true } }
        return false
    }
}

// Little sounds, made here from a few sine notes: nothing to download or license, and the audio engine runs only while Couch Mode is open.
final class CouchSound {
    enum Kind { case move, shelf, play, back, favorite, open }
    private var engine: AVAudioEngine?, node: AVAudioPlayerNode?, made: [Kind: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    func start() {
        guard engine == nil else { return }
        let e = AVAudioEngine(), n = AVAudioPlayerNode(); e.attach(n); e.connect(n, to: e.mainMixerNode, format: format); e.mainMixerNode.outputVolume = 0.3
        guard (try? e.start()) != nil else { return }
        n.play(); engine = e; node = n
        if made.isEmpty {
            made = [.move: notes([(1568, 0, 0.05)], 0.16), .shelf: notes([(784, 0, 0.08), (1175, 0.035, 0.1)], 0.18),
                    .favorite: notes([(1319, 0, 0.1), (1760, 0.06, 0.16)], 0.17), .back: notes([(880, 0, 0.09), (659, 0.06, 0.14)], 0.17),
                    .play: notes([(523, 0, 0.2), (659, 0.08, 0.22), (784, 0.16, 0.4)], 0.2), .open: notes([(392, 0, 0.3), (587, 0.1, 0.35), (784, 0.2, 0.55)], 0.16)]
        }
    }
    func stop() { node?.stop(); engine?.stop(); node = nil; engine = nil }
    func play(_ k: Kind) { guard let n = node, let b = made[k] else { return }; n.scheduleBuffer(b, at: nil, options: .interrupts, completionHandler: nil); if !n.isPlaying { n.play() } }
    // Each note: a soft attack, a quick fall, and a quiet octave above for a little shine
    private func notes(_ l: [(hz: Double, at: Double, long: Double)], _ gain: Float) -> AVAudioPCMBuffer {
        let rate = format.sampleRate, count = AVAudioFrameCount((l.map { $0.at + $0.long }.max() ?? 0.1) * rate + 400)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!; b.frameLength = count
        let d = b.floatChannelData![0]; for i in 0..<Int(count) { d[i] = 0 }
        for n in l {
            let start = Int(n.at * rate), len = Int(n.long * rate)
            for i in 0..<len where start + i < Int(count) {
                let t = Double(i) / rate, env = min(1, t / 0.005) * exp(-t * 5 / n.long)
                d[start + i] += gain * Float(env * (sin(2 * .pi * n.hz * t) + 0.22 * sin(4 * .pi * n.hz * t)))
            }
        }
        return b
    }
}

// ---- how it looks ----
// Laid out for a TV seen from the sofa, on a 1080-line grid that scales with the screen:
//   the chosen game large at the top left over its own art; under it, the chosen shelf on a fixed line, the next shelf peeking below.
// The chosen cover always sits in the same place and the shelf slides under it, so the eye never has to chase the focus.
// Only the few shelves and covers near the focus are drawn, so a shelf of ten thousand games costs the same as one of ten.

struct CouchRowSlot: Identifiable { let n: Int, shelf: CouchShelf; var id: String { shelf.id } }

enum CouchLayout {
    static func scale(_ size: CGSize) -> CGFloat { min(max(size.height / 1080, 0.6), 2) }
    static let margin: CGFloat = 96         // the safe edge a TV may crop into
    static let coverWidth: CGFloat = 212
    static let gap: CGFloat = 28
    static let shelfTop: CGFloat = 0.545    // where the chosen shelf's name sits, as a share of the height
    static func slide(_ still: Bool) -> Animation { still ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86) }
}

struct CouchView: View {
    @EnvironmentObject var model: Model
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let shelves = model.couchShelves, spot = model.couchSpot.resolved(model.couchRows(shelves))
        let sel = model.couchSelection(shelves, spot: spot), idle = model.couchIdle
        GeometryReader { geo in
            let k = CouchLayout.scale(geo.size), m = CouchLayout.margin * k
            ZStack(alignment: .topLeading) {
                style.bottom
                if let g = sel?.game { CouchBackdrop(game: g, size: geo.size) }
                if let sel {
                    // The new title arrives with a short rise; the old one leaves at once, so two names never overlap
                    CouchHero(game: sel.game, k: k, idle: idle)
                        .id(sel.game.id)
                        .transition(still ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8 * k)), removal: .identity))
                        .frame(maxWidth: geo.size.width * 0.58, alignment: .leading)
                        .padding(.leading, m).padding(.top, 150 * k)
                }
                shelfStack(shelves, spot, geo.size, k).opacity(idle ? 0 : 1)
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: style.bottom.opacity(0.97), location: 0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 240 * k).frame(maxHeight: .infinity, alignment: .bottom).allowsHitTesting(false).opacity(idle ? 0 : 1)
                topBar(sel?.shelf, shelves.count, spot.shelf, k).padding(.horizontal, m).padding(.top, 44 * k).opacity(idle ? 0 : 1)
                hints(sel?.game, k).padding(.horizontal, m).padding(.bottom, 40 * k)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).opacity(idle ? 0 : 1)
                if shelves.isEmpty {
                    Text("Add games to your library to see them here.").font(.system(size: 30 * k, weight: .medium)).foregroundStyle(style.soft)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let msg = model.message { message(msg, k) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeOut(duration: 0.2), value: sel?.game.id)
        .animation(.easeInOut(duration: 1.2), value: idle)
        .animation(.easeOut(duration: 0.2), value: model.message)
        .onContinuousHover { _ in if model.couchIdle { model.couchPoke() } }
        .ignoresSafeArea()
    }

    // The chosen shelf on its fixed line, one shelf above (fading away) and two below. Up and down slide the stack.
    func shelfStack(_ shelves: [CouchShelf], _ spot: CouchSpot, _ size: CGSize, _ k: CGFloat) -> some View {
        let r = spot.shelf, coverH = CouchLayout.coverWidth * k / Cover.shape, pitch = coverH + 112 * k
        let lo = max(0, r - 1), hi = min(shelves.count - 1, r + 2)
        let near = lo <= hi ? (lo...hi).map { CouchRowSlot(n: $0, shelf: shelves[$0]) } : []
        return ZStack(alignment: .topLeading) {
                ForEach(near) { slot in
                    let n = slot.n, s = slot.shelf, d = n - r
                    CouchRow(shelf: s, index: spot.index(s.id, s.ids), active: d == 0, k: k, width: size.width, tick: model.coverTick, model: model,
                             pick: { j in if d == 0 && j == spot.index(s.id, s.ids) { model.couchMove(.accept, pad: false) } else { model.couchFocus(n, j) } })
                        .equatable()
                        .scaleEffect(d == 0 ? 1 : 0.9, anchor: .topLeading)
                        .opacity(d < 0 ? 0 : d == 0 ? 1 : d == 1 ? 0.62 : 0)
                        .offset(y: CGFloat(d) * pitch - (d > 0 ? CGFloat(d) * 10 * k : 0))
                        .zIndex(d == 0 ? 1 : 0)
                        .transition(.opacity)
                }
        }
        .frame(width: size.width, alignment: .topLeading)
        .offset(y: size.height * CouchLayout.shelfTop)
        .animation(CouchLayout.slide(still), value: r)
    }

    func topBar(_ shelf: CouchShelf?, _ count: Int, _ at: Int, _ k: CGFloat) -> some View {
        HStack(spacing: 14 * k) {
            DPad().fill(style.accent).frame(width: 30 * k, height: 30 * k)
            Text("Docked").font(.system(size: 28 * k, weight: .heavy, design: .serif)).foregroundStyle(style.text)
            Spacer()
            if count > 1 { CouchPager(count: count, at: at, k: k) }
            TimelineView(.everyMinute) { t in Text(t.date, style: .time).font(.system(size: 22 * k, weight: .medium)).monospacedDigit().foregroundStyle(style.soft) }
                .padding(.leading, 18 * k)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(shelf.map { "Couch Mode, \($0.name), shelf \(at + 1) of \(count)" } ?? "Couch Mode")
    }

    func hints(_ g: Game?, _ k: CGFloat) -> some View {
        let fav = g.map { model.library.entry($0.titleID).favorite } ?? false
        return HStack(spacing: 34 * k) {
            hint(["a.circle.fill"], "Return", "Play", k)
            hint(["y.circle.fill"], "F", fav ? "Unfavorite" : "Favorite", k)
            hint(["lb.rectangle.roundedtop.fill", "rb.rectangle.roundedtop.fill"], "Tab", "Shelves", k)
            hint(["b.circle.fill"], "Esc", "Leave", k)
        }
        .accessibilityHidden(true)
    }
    func hint(_ pad: [String], _ key: String, _ what: String, _ k: CGFloat) -> some View {
        HStack(spacing: 10 * k) {
            if model.padUsed { HStack(spacing: 4 * k) { ForEach(pad, id: \.self) { Image(systemName: $0).font(.system(size: 26 * k)).foregroundStyle(style.text) } } }
            else { Text(key).font(.system(size: 15 * k, weight: .semibold)).foregroundStyle(style.text).padding(.horizontal, 9 * k).padding(.vertical, 4 * k).overlay(RoundedRectangle(cornerRadius: 6 * k).strokeBorder(style.soft.opacity(0.7), lineWidth: 1.5)) }
            Text(what).font(.system(size: 19 * k, weight: .medium)).foregroundStyle(style.soft)
        }
    }
    func message(_ m: String, _ k: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 26 * k) {
                Text(m).font(.system(size: 30 * k, weight: .medium)).foregroundStyle(style.text).multilineTextAlignment(.center)
                hint(["a.circle.fill"], "Return", "OK", k)
            }
            .padding(48 * k).frame(maxWidth: 900 * k).background(style.tile, in: RoundedRectangle(cornerRadius: 26 * k, style: .continuous))
        }
        .onTapGesture { model.message = nil }.transition(.opacity)
    }
}

// Where you are among the shelves: one small mark per shelf, the chosen one long. Past twelve it is a count instead.
struct CouchPager: View {
    let count: Int, at: Int, k: CGFloat
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        if count > 12 {
            Text("\(at + 1) of \(count)").font(.system(size: 18 * k, weight: .semibold)).monospacedDigit().foregroundStyle(style.soft)
        } else {
            HStack(spacing: 6 * k) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule().fill(i == at ? style.accent : style.soft.opacity(0.35)).frame(width: i == at ? 26 * k : 7 * k, height: 7 * k)
                }
            }
            .animation(CouchLayout.slide(still), value: at)
        }
    }
}

// One shelf: its name, and the covers near the chosen one. The chosen cover stays put and the shelf slides.
// Drawn again only when its own games, its place, or the covers on this Mac change, never because something elsewhere in the app did.
struct CouchRow: View, Equatable {
    let shelf: CouchShelf, index: Int, active: Bool, k: CGFloat, width: CGFloat, tick: Int
    let model: Model                 // read for covers only; not watched
    let pick: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var still
    static func == (a: CouchRow, b: CouchRow) -> Bool {
        a.shelf.id == b.shelf.id && a.shelf.sig == b.shelf.sig && a.index == b.index && a.active == b.active && a.k == b.k && a.width == b.width && a.tick == b.tick
    }
    struct Slot: Identifiable { let at: Int, game: Game; var id: String { game.id } }

    var body: some View {
        let m = CouchLayout.margin * k, w = CouchLayout.coverWidth * k, h = w / Cover.shape, pitch = w + CouchLayout.gap * k
        let lo = max(0, index - 1), hi = min(shelf.games.count - 1, index + Int(width / pitch) + 1)
        let slots = lo <= hi ? (lo...hi).map { Slot(at: $0, game: shelf.games[$0]) } : []
        VStack(alignment: .leading, spacing: 18 * k) {
            HStack(alignment: .firstTextBaseline, spacing: 16 * k) {
                Text(shelf.name).font(.system(size: 30 * k, weight: .bold)).foregroundStyle(style.text).lineLimit(1)
                if active, let note = shelf.note { Text(note).font(.system(size: 19 * k)).foregroundStyle(style.soft).lineLimit(1).transition(.opacity) }
                Spacer(minLength: 0)
                if active, shelf.games.count > 1 { Text("\(index + 1) of \(shelf.games.count)").font(.system(size: 17 * k, weight: .medium)).monospacedDigit().foregroundStyle(style.soft).transition(.opacity) }
            }
            .padding(.leading, m).padding(.trailing, m)
            ZStack(alignment: .topLeading) {
                ForEach(slots) { s in
                    let d = s.at - index
                    CouchCover(game: s.game, image: model.cover(s.game) ?? model.icon(s.game), on: active && d == 0, k: k)
                        .offset(x: m + CGFloat(d) * pitch)
                        .opacity(d < 0 ? 0.28 : 1)
                        .onTapGesture { pick(s.at) }
                        .transition(.opacity)
                }
            }
            .frame(width: width, height: h, alignment: .topLeading)
        }
        .animation(CouchLayout.slide(still), value: index)
        .animation(.easeOut(duration: 0.2), value: active)
        .accessibilityElement(children: .contain).accessibilityLabel(shelf.name)
    }
}

struct CouchCover: View {
    let game: Game, image: NSImage, on: Bool, k: CGFloat
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        let w = CouchLayout.coverWidth * k, h = w / Cover.shape, r = RoundedRectangle(cornerRadius: 12 * k, style: .continuous)
        Image(nsImage: image).resizable().interpolation(.medium).aspectRatio(contentMode: .fill).frame(width: w, height: h)
            .background(style.tile).clipShape(r)
            .overlay { if game.missing { ZStack { Color.black.opacity(0.6); Label(game.away != nil ? "Offloaded" : "Not connected", systemImage: game.away != nil ? "icloud" : "externaldrive.badge.xmark").font(.system(size: 15 * k, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center).padding(8 * k) }.clipShape(r) } }
            .overlay { r.strokeBorder(.white.opacity(on ? 0 : 0.07), lineWidth: 1) }
            // The chosen cover: lifted, with a ring a little way out from its edge, the way a TV shows focus from across a room
            .overlay { if on { RoundedRectangle(cornerRadius: 17 * k, style: .continuous).strokeBorder(style.accent, lineWidth: 4 * k).padding(-7 * k).transition(.opacity) } }
            .shadow(color: .black.opacity(on ? 0.55 : 0), radius: on ? 24 * k : 0, y: on ? 16 * k : 0)
            .scaleEffect(on ? 1.1 : 1)
            .zIndex(on ? 1 : 0)
            .animation(still ? .easeOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.8), value: on)
            .accessibilityElement().accessibilityLabel(game.name).accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

// The chosen game, large, where the eye lands first. Changes quickly and quietly as the focus moves.
struct CouchHero: View {
    @EnvironmentObject var model: Model
    let game: Game, k: CGFloat, idle: Bool
    var body: some View {
        let e = model.library.entry(game.titleID), info = game.rom?.info
        let kind = [consoleName(consoleOf(game.titleID)), model.couchYear(game).map { String($0) }, (info?.genre ?? e.meta?.genre)?.capitalized].compactMap { $0 }
        let cheevos = game.rom.flatMap { Cheevos.of($0) }
        VStack(alignment: .leading, spacing: 18 * k) {
            Text(game.name).font(.system(size: 76 * k, weight: .heavy, design: .serif)).foregroundStyle(style.text)
                .lineLimit(2).minimumScaleFactor(0.55).shadow(color: .black.opacity(style.dark ? 0.45 : 0), radius: 18 * k)
            if !kind.isEmpty {
                HStack(spacing: 22 * k) { ForEach(kind, id: \.self) { Text($0) } }
                    .font(.system(size: 22 * k, weight: .semibold)).foregroundStyle(style.soft).lineLimit(1)
            }
            Group {
                if let a = info?.about, !a.isEmpty {
                    Text(a).font(.system(size: 22 * k)).foregroundStyle(style.text.opacity(0.82)).lineLimit(2).lineSpacing(5 * k).frame(maxWidth: 820 * k, alignment: .leading)
                }
                HStack(spacing: 12 * k) {
                    if let c = e.meta?.critic { score(c) }
                    if model.isRunning(game) { chip("play.fill", "Playing now", style.ok) }
                    if e.favorite { chip("heart.fill", "Favorite", style.accent) }
                    if e.seconds > 0 { chip("clock", playTimeText(e.seconds) + " played") }
                    else if !game.missing { chip("sparkles", "Not played yet") }
                    if let c = cheevos { chip("trophy", "\(Cheevos.text(c)) achievements", c.earned == c.total ? style.accent : nil) }
                    if let why = game.cannot { chip("exclamationmark.triangle.fill", why, style.warn) }
                }
            }
            .opacity(idle ? 0 : 1)
        }
        .accessibilityElement(children: .combine)
    }
    // The critics' score as a small solid badge, the one bright mark beside the title
    func score(_ c: Int) -> some View {
        HStack(spacing: 8 * k) {
            Text("\(c)").font(.system(size: 20 * k, weight: .heavy)).monospacedDigit()
            Text("Critics").font(.system(size: 15 * k, weight: .semibold))
        }
        .foregroundStyle(style.dark ? style.bottom : .white)
        .padding(.horizontal, 13 * k).padding(.vertical, 7 * k)
        .background(style.accent, in: RoundedRectangle(cornerRadius: 9 * k, style: .continuous))
        .accessibilityLabel("Critics' score \(c)")
    }
    func chip(_ icon: String, _ t: String, _ c: Color? = nil) -> some View {
        Label { Text(t) } icon: { Image(systemName: icon) }
            .font(.system(size: 17 * k, weight: .semibold)).foregroundStyle(c ?? style.text).lineLimit(1)
            .padding(.horizontal, 13 * k).padding(.vertical, 8 * k)
            .background(style.text.opacity(0.1), in: RoundedRectangle(cornerRadius: 9 * k, style: .continuous))
    }
}

// Behind everything: the chosen game's own art. A wide picture (an in-game shot or eShop banner) fills the room;
// a cover or icon stands large on the right over a soft wash of its own colours. It changes only once the focus rests
// for a moment, so holding the D-pad does not flash pictures, and nothing moves while it sits still.
struct CouchBackdrop: View {
    @EnvironmentObject var model: Model
    let game: Game, size: CGSize
    @State private var shown: Game?
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        let _ = model.couchArtTick
        ZStack {
            if let g = shown { layer(g).id(g.id).transition(.opacity) }
            // Dark where the words are: across the left for the title, along the bottom for the shelves
            LinearGradient(stops: [.init(color: style.bottom.opacity(0.97), location: 0), .init(color: style.bottom.opacity(0.72), location: 0.38), .init(color: style.bottom.opacity(0.05), location: 0.78)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.28), .init(color: style.bottom.opacity(0.82), location: 0.55), .init(color: style.bottom, location: 0.8)], startPoint: .top, endPoint: .bottom)
        }
        .frame(width: size.width, height: size.height).clipped()
        .animation(.easeInOut(duration: still ? 0.15 : 0.5), value: shown?.id)
        .task(id: game.id) {
            if shown == nil { shown = game; return }
            try? await Task.sleep(nanoseconds: 180_000_000)
            if !Task.isCancelled { shown = game }
        }
        .accessibilityHidden(true)
    }
    @ViewBuilder func layer(_ g: Game) -> some View {
        let art = model.couchArt(g), wide = art.map { $0.size.width >= $0.size.height * 1.2 } ?? false, k = CouchLayout.scale(size)
        ZStack(alignment: .trailing) {
            if let art, wide {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height).clipped().modifier(CouchSettle())
            } else {
                Image(nsImage: model.wash(g)).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height).clipped()
                    .opacity(style.dark ? 0.75 : 0.55)
                if let art {
                    let h = size.height * 0.46, w = min(h * art.size.width / max(art.size.height, 1), size.width * 0.34)   // clear of the shelves below
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: 22 * k, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 36 * k, y: 18 * k)
                        .rotation3DEffect(.degrees(-7), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .padding(.trailing, size.width * 0.08).offset(y: -size.height * 0.18)
                        .modifier(CouchSettle())
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// A picture arriving settles in once, from a touch larger, and then holds still: no animation runs while nothing is pressed.
struct CouchSettle: ViewModifier {
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var still
    func body(content: Content) -> some View {
        content.scaleEffect(settled || still ? 1 : 1.04)
            .onAppear { withAnimation(.easeOut(duration: 1.4)) { settled = true } }
    }
}
