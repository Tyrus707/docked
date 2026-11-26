import SwiftUI
import AVFoundation

// Couch Mode: the library full screen, for a controller and a TV. Several shelves at a time, the chosen game's art filling the room.
// It is drawn over the library in the same window, which goes properly full screen (a Space of its own) while it is open,
// so sheets and questions still appear on top of it. Leaving puts the window back as it was.

struct CouchShelf { var id: String, name: String, games: [Game], note: String? = nil }

extension Model {
    // One flat list: the familiar shelves first, then ones that fill themselves from details already on this Mac.
    var couchShelves: [CouchShelf] {
        var r = [CouchShelf(id: "continue", name: "Continue", games: Array(shown(.all, by: .recent).filter { library.entry($0.titleID).lastPlayed != nil }.prefix(12)), note: "Pick up where you left off"),
                 CouchShelf(id: "favorites", name: "Favorites", games: shown(.favorites, by: .recent), note: "Saved by you"),
                 CouchShelf(id: "all", name: "All Games", games: shown(.all), note: "Everything in the library")]
        for c in consolesShown { r.append(CouchShelf(id: "console:" + c.id, name: c.name, games: shown(.console(c.id)))) }
        for c in library.collections { r.append(CouchShelf(id: "collection:" + c, name: c, games: shown(.collection(c)))) }
        for s in library.smart { r.append(CouchShelf(id: "smart:" + s.name, name: s.name, games: shown(.smart(s)))) }
        r.append(contentsOf: couchCuratedShelves)
        return r.filter { !$0.games.isEmpty }
    }

    // No new lookup or network call: these use critic scores, years and stars already on this Mac.
    var couchCuratedShelves: [CouchShelf] {
        let acclaimed = shown(.all, by: .critic).filter { g in
            let e = library.entry(g.titleID); return (e.meta?.critic ?? -1) >= 90 || e.rating >= 5
        }
        let nineties = shown(.all, by: .year).filter { couchYear($0).map { (1990...1999).contains($0) } ?? false }
        let gems = shown(.all, by: .critic).filter { g in
            guard let c = couchCritic(g) else { return false }
            return c >= 70 && c < 90 && !library.entry(g.titleID).favorite
        }
        return [CouchShelf(id: "critics", name: "Critically Acclaimed", games: Array(acclaimed.prefix(30)), note: "90 and up, or five stars from you"),
                CouchShelf(id: "90s", name: "Enjoy the 90's", games: Array(nineties.prefix(30)), note: "Released 1990–1999"),
                CouchShelf(id: "gems", name: "Hidden Gems", games: Array(gems.prefix(30)), note: "Well reviewed, not yet favorites")]
            .filter { !$0.games.isEmpty }
    }
    func couchYear(_ g: Game) -> Int? { library.year(g) }   // the same year the library sorts and groups by
    func couchCritic(_ g: Game) -> Int? { library.entry(g.titleID).meta?.critic }
    func couchRows(_ shelves: [CouchShelf]) -> [(id: String, games: [String])] { shelves.map { (id: $0.id, games: $0.games.map(\.id)) } }

    func couchSelection(_ shelves: [CouchShelf]? = nil, spot: CouchSpot? = nil) -> (shelf: CouchShelf, index: Int, game: Game)? {
        let l = shelves ?? couchShelves
        let p = (spot ?? couchSpot).resolved(couchRows(l))
        guard l.indices.contains(p.shelf) else { return nil }
        let s = l[p.shelf], i = p.index(s.id, s.games.map(\.id)); guard s.games.indices.contains(i) else { return nil }
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
        couchFocus(n, spot.index(id, shelves[n].games.map(\.id)))
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

struct CouchView: View {
    @EnvironmentObject var model: Model
    @Environment(\.accessibilityReduceMotion) private var still
    @Namespace private var tabs

    var body: some View {
        let shelves = model.couchShelves, spot = model.couchSpot.resolved(model.couchRows(shelves))
        let sel = model.couchSelection(shelves, spot: spot)
        let game = sel?.game
        let focus = sel?.shelf.id
        GeometryReader { geo in
            let k = min(max(geo.size.height / 1080, 0.6), 2)   // sized for a 1080-line TV, read from across the room
            ZStack(alignment: .topLeading) {
                style.bottom
                if let game { CouchBackdrop(game: game, size: geo.size).id(game.id).transition(.opacity) }
                VStack(alignment: .leading, spacing: 0) {
                    rail(shelves, spot.shelf, k).frame(height: 50 * k).opacity(model.couchIdle ? 0 : 1)
                    ScrollViewReader { p in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 24 * k) {
                                ForEach(Array(shelves.enumerated()), id: \.element.id) { n, s in
                                    row(s, n, spot.index(s.id, s.games.map(\.id)), n == spot.shelf, n == spot.shelf ? k : k * 0.76).id(s.id)
                                }
                            }
                            .padding(.horizontal, 80 * k).padding(.top, 16 * k).padding(.bottom, 230 * k)
                        }
                        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.06)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(model.couchIdle ? 0 : 1)
                        .onAppear { if let focus { withAnimation(still ? nil : .easeOut(duration: 0.3)) { p.scrollTo(focus, anchor: .center) } } }
                        .whenChanged(focus ?? "") { if let focus { withAnimation(still ? nil : .easeOut(duration: 0.35)) { p.scrollTo(focus, anchor: .center) } } }
                    }
                    hints(game, k).frame(height: 40 * k).opacity(model.couchIdle ? 0 : 1)
                }
                .padding(.top, 34 * k)
                .overlay(alignment: .bottomLeading) {
                    if let sel {
                        CouchInfo(game: sel.game, k: k * 0.8, badge: sel.shelf.note ?? "Couch Mode")
                            .id("i" + sel.game.id)
                            .transition(still ? .opacity : .opacity.combined(with: .offset(x: -24 * k)))
                            .frame(maxWidth: geo.size.width * 0.62, alignment: .leading)
                            .padding(.leading, 80 * k).padding(.bottom, 58 * k)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if shelves.count > 3 {
                        scrollCue(k).padding(.trailing, 80 * k).padding(.bottom, 60 * k).opacity(model.couchIdle ? 0 : 0.75)
                    }
                }
                if shelves.isEmpty { Text("Add games to your library to see them here.").font(.system(size: 28 * k)).foregroundStyle(style.soft).padding(80 * k) }
                if let m = model.message { message(m, k) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(still ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.45), value: game?.id)
        .animation(still ? nil : .easeInOut(duration: 0.3), value: spot.shelf)
        .animation(.easeInOut(duration: 1.2), value: model.couchIdle)
        .animation(.easeOut(duration: 0.2), value: model.message)
        .onContinuousHover { _ in if model.couchIdle { model.couchPoke() } }
        .ignoresSafeArea()
    }

    func rail(_ shelves: [CouchShelf], _ on: Int, _ k: CGFloat) -> some View {
        HStack(spacing: 14 * k) {
            HStack(spacing: 10 * k) { DPad().fill(style.accent).frame(width: 30 * k, height: 30 * k); Text("Docked").font(.system(size: 30 * k, weight: .heavy, design: .serif)).foregroundStyle(style.text) }
                .padding(.trailing, 22 * k).accessibilityHidden(true)
            ScrollViewReader { p in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6 * k) {
                        ForEach(Array(shelves.enumerated()), id: \.element.id) { n, s in
                            HStack(spacing: 6 * k) {
                                if n == on { Circle().fill(style.accent).frame(width: 5 * k, height: 5 * k) }
                                Text(s.name).font(.system(size: 22 * k, weight: .semibold)).lineLimit(1)
                            }
                            .foregroundStyle(n == on ? style.bottom : style.soft)
                            .padding(.horizontal, 18 * k).padding(.vertical, 9 * k)
                            .background { if n == on { Capsule().fill(style.text).matchedGeometryEffect(id: "tab", in: tabs) } }
                            .contentShape(Capsule()).onTapGesture { model.couchFocusShelf(s.id) }.id(s.id)
                            .accessibilityAddTraits(n == on ? [.isButton, .isSelected] : .isButton).accessibilityLabel(s.name)
                        }
                    }
                }
                .whenChanged(on) { if shelves.indices.contains(on) { withAnimation(still ? nil : .easeOut(duration: 0.3)) { p.scrollTo(shelves[on].id, anchor: .center) } } }
            }
            TimelineView(.everyMinute) { t in Text(t.date, style: .time).font(.system(size: 22 * k, weight: .medium)).monospacedDigit().foregroundStyle(style.soft) }.padding(.leading, 18 * k)
        }
    }

    func row(_ shelf: CouchShelf, _ n: Int, _ i: Int, _ active: Bool, _ k: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4 * k) {
            HStack(spacing: 10 * k) {
                if active { RoundedRectangle(cornerRadius: 2 * k).fill(style.accent).frame(width: 3 * k, height: 16 * k) }
                Text(shelf.name.uppercased() + (shelf.note.map { "  ·  " + $0 } ?? "") + "  ·  \(i + 1) of \(shelf.games.count)")
                    .font(.system(size: 13 * k, weight: .semibold)).tracking(1.8 * k).foregroundStyle(active ? style.text : style.soft).monospacedDigit().lineLimit(1)
            }
            ScrollViewReader { p in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 18 * k) {
                        ForEach(Array(shelf.games.enumerated()), id: \.element.id) { j, game in
                            CouchCover(game: game, on: active && j == i, k: k).id(game.id)
                                .onTapGesture { if active && j == i { model.couchMove(.accept, pad: false) } else { model.couchFocus(n, j) } }
                        }
                    }
                    .padding(.horizontal, 56 * k).padding(.vertical, 22 * k)   // room for the lifted cover and its glow
                }
                .padding(.horizontal, -56 * k)
                .onAppear { if shelf.games.indices.contains(i) { p.scrollTo(shelf.games[i].id, anchor: UnitPoint(x: 0.12, y: 0.5)) } }
                .whenChanged(i) { if active, shelf.games.indices.contains(i) { withAnimation(still ? nil : .easeOut(duration: 0.28)) { p.scrollTo(shelf.games[i].id, anchor: UnitPoint(x: 0.12, y: 0.5)) } } }
            }
        }
        .padding(.leading, active ? 12 * k : 0)
        .background { if active { LinearGradient(colors: [style.accent.opacity(0.14), .clear], startPoint: .leading, endPoint: .center).clipShape(RoundedRectangle(cornerRadius: 14 * k, style: .continuous)) } }
        .opacity(active ? 1 : 0.72)
        .animation(still ? nil : .easeOut(duration: 0.22), value: active)
    }

    func scrollCue(_ k: CGFloat) -> some View {
        HStack(spacing: 8 * k) {
            Image(systemName: "chevron.down").font(.system(size: 13 * k, weight: .bold))
            Text("MORE SHELVES").font(.system(size: 12 * k, weight: .bold)).tracking(2 * k)
        }
        .foregroundStyle(style.accent).accessibilityHidden(true)
    }

    func hints(_ g: Game?, _ k: CGFloat) -> some View {
        let fav = g.map { model.library.entry($0.titleID).favorite } ?? false
        return HStack(spacing: 28 * k) {
            Spacer()
            hint("a", "Return", "Play", k); hint("y", "F", fav ? "Unfavorite" : "Favorite", k)
            hint("row", "↑↓", "Row", k); hint("lb", "⇧Tab", "Previous shelf", k); hint("rb", "Tab", "Next shelf", k); hint("b", "Esc", "Leave", k)
        }
    }
    func hint(_ pad: String, _ key: String, _ what: String, _ k: CGFloat) -> some View {
        HStack(spacing: 9 * k) {
            if model.padUsed {
                let icon = pad == "rb" ? "rb.rectangle.roundedbottom.fill" : pad == "lb" ? "lb.rectangle.roundedtop.fill" : pad == "row" ? "arrow.up.arrow.down" : pad + ".circle.fill"
                Image(systemName: icon).font(.system(size: 24 * k)).foregroundStyle(style.text)
            }
            else { Text(key).font(.system(size: 15 * k, weight: .semibold)).foregroundStyle(style.text).padding(.horizontal, 9 * k).padding(.vertical, 4 * k).overlay(RoundedRectangle(cornerRadius: 6 * k).strokeBorder(style.soft, lineWidth: 1.5)) }
            Text(what).font(.system(size: 19 * k, weight: .medium)).foregroundStyle(style.soft)
        }
    }
    func message(_ m: String, _ k: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 22 * k) {
                Text(m).font(.system(size: 28 * k, weight: .medium)).foregroundStyle(style.text).multilineTextAlignment(.center)
                hint("a", "Return", "OK", k)
            }
            .padding(44 * k).frame(maxWidth: 900 * k).background(style.tile, in: RoundedRectangle(cornerRadius: 24 * k)).overlay(RoundedRectangle(cornerRadius: 24 * k).strokeBorder(style.line))
        }
        .onTapGesture { model.message = nil }.transition(.opacity)
    }
}

// Behind everything: the game's own art. A wide picture (an in-game shot) fills the room; a cover or icon stands large on the right
// over a blur of its own colours. Both drift very slowly, and fade into the theme where the words are.
struct CouchBackdrop: View {
    @EnvironmentObject var model: Model
    let game: Game, size: CGSize
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var drift = false
    var body: some View {
        let _ = model.couchArtTick
        let art = model.couchArt(game), wide = art.map { $0.size.width >= $0.size.height * 1.2 } ?? false, k = min(max(size.height / 1080, 0.6), 2)
        ZStack(alignment: .trailing) {
            Image(nsImage: wide ? art! : model.wash(game)).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height).clipped()
                .blur(radius: wide ? 0 : 6).opacity(wide ? 1 : (style.dark ? 0.85 : 0.65))
                .scaleEffect(drift ? 1.1 : 1.0, anchor: .topTrailing)
            if let art, !wide {
                let h = size.height * 0.62, w = min(h * art.size.width / max(art.size.height, 1), size.width * 0.42)
                Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: w, height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 22 * k, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 40 * k, y: 18 * k)
                    .rotation3DEffect(.degrees(drift ? -6 : -2), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .padding(.trailing, size.width * 0.07).offset(y: -size.height * 0.1)
                    .transition(.opacity)
            }
            LinearGradient(colors: [style.bottom.opacity(0.96), style.bottom.opacity(0.6), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5))
            LinearGradient(colors: [.clear, style.bottom.opacity(0.7), style.bottom], startPoint: UnitPoint(x: 0.5, y: 0.35), endPoint: .bottom)
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: 0.5), value: art != nil)
        .onAppear { if !still { withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) { drift = true } } }
        .accessibilityHidden(true)
    }
}

struct CouchInfo: View {
    @EnvironmentObject var model: Model
    let game: Game, k: CGFloat, badge: String
    var body: some View {
        let e = model.library.entry(game.titleID), info = game.rom?.info
        let meta = [consoleName(consoleOf(game.titleID)), model.couchYear(game).map { String($0) }, info?.genre ?? e.meta?.genre].compactMap { $0 }.joined(separator: "  ·  ")
        let facts = [e.meta?.critic.map { "\($0)% critic" }, e.meta?.views.map { readersText($0) }, e.seconds > 0 ? playTimeText(e.seconds) : nil, e.favorite ? "Favorite" : nil].compactMap { $0 }
        let cheevos = game.rom.flatMap { Cheevos.of($0) }
        let details: [(String, String, Color?)] = [
            model.isRunning(game) ? ("play.fill", "Playing now", style.ok) : nil,
            e.lastPlayed.map { ("calendar", "Last played " + RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()), nil) },
            e.status == .none ? nil : ("bookmark", e.status.rawValue, nil),
            cheevos.map { ("trophy", "\(Cheevos.text($0)) achievements", $0.earned == $0.total ? style.accent : nil) }
        ].compactMap { $0 }
        VStack(alignment: .leading, spacing: 10 * k) {
            Text("NOW CHOOSING  ·  " + badge.uppercased()).font(.system(size: 13 * k, weight: .heavy)).tracking(2.4 * k).foregroundStyle(style.accent).lineLimit(1)
            Text(game.name).font(.system(size: 54 * k, weight: .heavy, design: .serif)).foregroundStyle(style.text).lineLimit(2).minimumScaleFactor(0.5).shadow(color: .black.opacity(style.dark ? 0.4 : 0), radius: 12 * k)
            if !meta.isEmpty { Text(meta.uppercased()).font(.system(size: 14 * k, weight: .semibold)).tracking(2 * k).foregroundStyle(style.soft).lineLimit(1) }
            if let a = info?.about, !a.isEmpty { Text(a).font(.system(size: 18 * k)).foregroundStyle(style.soft).lineLimit(2).lineSpacing(3 * k) }
            HStack(spacing: 8 * k) {
                ForEach(facts.prefix(4), id: \.self) { t in
                    Text(t).font(.system(size: 13 * k, weight: .semibold)).foregroundStyle(style.text)
                        .padding(.horizontal, 10 * k).padding(.vertical, 5 * k)
                        .background(Capsule().fill(style.line.opacity(0.45)))
                }
            }
            if !details.isEmpty {
                HStack(spacing: 14 * k) {
                    ForEach(details.indices, id: \.self) { n in stat(details[n].0, details[n].1, details[n].2) }
                }
            }
            if let why = game.cannot { stat("exclamationmark.triangle.fill", why, style.warn) }
        }
        .padding(20 * k).frame(maxWidth: 720 * k, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18 * k, style: .continuous).fill(style.bottom.opacity(0.66)))
        .overlay(RoundedRectangle(cornerRadius: 18 * k, style: .continuous).strokeBorder(style.line.opacity(0.55)))
        .accessibilityElement(children: .combine)
    }
    func stat(_ icon: String, _ t: String, _ c: Color? = nil) -> some View {
        Label { Text(t) } icon: { Image(systemName: icon) }.font(.system(size: 16 * k, weight: .medium)).foregroundStyle(c ?? style.soft).lineLimit(1)
    }
}

struct CouchCover: View {
    @EnvironmentObject var model: Model
    let game: Game, on: Bool, k: CGFloat
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var shine: CGFloat = -1.4
    var body: some View {
        let w = 196 * k, h = w / Cover.shape, r = RoundedRectangle(cornerRadius: 12 * k, style: .continuous)
        Image(nsImage: model.cover(game) ?? model.icon(game)).resizable().aspectRatio(contentMode: .fill).frame(width: w, height: h).clipShape(r)
            .overlay {   // a streak of light across the cover as it is chosen
                LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing).frame(width: w * 0.45).rotationEffect(.degrees(18)).offset(x: shine * w).blendMode(.plusLighter).clipShape(r).allowsHitTesting(false)
            }
            .overlay { if game.missing { ZStack { Color.black.opacity(0.58); Label(game.away != nil ? "Offloaded" : "Not connected", systemImage: game.away != nil ? "icloud" : "externaldrive.badge.xmark").font(.system(size: 15 * k, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center).padding(8 * k) }.clipShape(r) } }
            .overlay(alignment: .topTrailing) { if model.library.entry(game.titleID).favorite { Image(systemName: "heart.fill").font(.system(size: 15 * k)).foregroundStyle(style.accent).padding(7 * k).background(.black.opacity(0.45), in: Circle()).padding(8 * k) } }
            .overlay(alignment: .topLeading) { if model.isRunning(game) { Circle().fill(style.ok).frame(width: 12 * k, height: 12 * k).padding(10 * k) } }
            .overlay { r.strokeBorder(on ? style.accent : .white.opacity(0.08), lineWidth: on ? 4 * k : 1) }
            .shadow(color: on ? style.accent.opacity(0.5) : .black.opacity(0.35), radius: on ? 26 * k : 10 * k, y: on ? 0 : 6 * k)
            .scaleEffect(on ? 1.12 : 0.95).offset(y: on ? -8 * k : 0).opacity(on ? 1 : 0.7).zIndex(on ? 1 : 0)
            .animation(still ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.7), value: on)
            .onAppear { if on { sweep() } }
            .whenChanged(on) { if on { sweep() } }
            .accessibilityElement().accessibilityLabel(game.name).accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
    private func sweep() { guard !still else { return }; shine = -1.4; withAnimation(.easeOut(duration: 0.75).delay(0.08)) { shine = 1.4 } }
}
