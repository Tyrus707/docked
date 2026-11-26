import SwiftUI
import AVFoundation

// Couch Mode: the library full screen, for a controller and a TV. One shelf at a time, the chosen game's art filling the room.
// It is drawn over the library in the same window, which goes properly full screen (a Space of its own) while it is open,
// so sheets and questions still appear on top of it. Leaving puts the window back as it was.

struct CouchShelf { var id: String, name: String, games: [Game] }

extension Model {
    var couchShelves: [CouchShelf] {
        var r = [CouchShelf(id: "continue", name: "Continue", games: Array(shown(.all, by: .recent).filter { library.entry($0.titleID).lastPlayed != nil }.prefix(12))),
                 CouchShelf(id: "favorites", name: "Favorites", games: shown(.favorites, by: .recent)),
                 CouchShelf(id: "all", name: "All Games", games: shown(.all))]
        for c in consolesShown { r.append(CouchShelf(id: "c" + c.id, name: c.name, games: shown(.console(c.id)))) }
        for c in library.collections { r.append(CouchShelf(id: "f" + c, name: c, games: shown(.collection(c)))) }
        for s in library.smart { r.append(CouchShelf(id: "s" + s.name, name: s.name, games: shown(.smart(s)))) }
        return r.filter { !$0.games.isEmpty }
    }
    func couchGame(_ shelves: [CouchShelf]? = nil) -> Game? {
        let l = shelves ?? couchShelves; guard l.indices.contains(couchSpot.shelf) else { return nil }
        let g = l[couchSpot.shelf].games; return g.isEmpty ? nil : g[couchSpot.index(g.count)]
    }
    // A sheet or question on the window is answered first; Couch Mode waits under it.
    var couchCovered: Bool { sheetUp || missingGame != nil || askLookUp || asking != nil || askingMode != nil || collecting != nil || retitling != nil || renaming != nil }
    private var libraryWindow: NSWindow? { NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.canBecomeMain && $0.isVisible } }

    func toggleCouch() { if couch { leaveCouch() } else { enterCouch() } }

    func enterCouch() {
        guard !couch, !games.isEmpty, !couchCovered, let w = libraryWindow else { return }
        couchSaved = search; search = ""   // the shelves show everything
        if couchSpot.shelf >= couchShelves.count { couchSpot = CouchSpot() }
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
        var s = couchSpot; let changed = s.shelf != shelf; s.shelf = shelf; s.at[shelf] = i
        guard s != couchSpot else { return }
        couchSpot = s; chime(changed ? .shelf : .move); couchPoke(); themeUpdate()
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
            let n = couchStep(couchSpot, m, counts: shelves.map(\.games.count))
            if n != couchSpot { let other = n.shelf != couchSpot.shelf; couchSpot = n; chime(other ? .shelf : .move); themeUpdate() }
        case .accept, .play:
            guard let g = couchGame(shelves) else { return }
            chime(.play); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.play(g) }
        case .favorite: if let g = couchGame(shelves) { let on = !library.entry(g.titleID).favorite; edit(g) { $0.favorite = on }; chime(.favorite) }
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
        let snap = g.rom.map { CouchArt.snap($0) } ?? CouchArt.banner(g.titleID), places = [snap, Cover.custom(g), g.rom.flatMap { RetroArch.art($0) }, g.url.appendingPathComponent("Contents/Resources/AppIcon.icns")].compactMap { $0 }
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
        let shelves = model.couchShelves, spot = model.couchSpot
        let shelf = shelves.indices.contains(spot.shelf) ? shelves[spot.shelf] : nil
        let i = shelf.map { spot.index($0.games.count) } ?? 0
        let game = shelf.flatMap { $0.games.isEmpty ? nil : $0.games[i] }
        GeometryReader { geo in
            let k = min(max(geo.size.height / 1080, 0.6), 2)   // sized for a 1080-line TV, read from across the room
            let cover = 196 * k, rowHeight = cover / Cover.shape + 120 * k   // fixed, so nothing below the title ever moves
            ZStack(alignment: .topLeading) {
                style.bottom
                if let game { CouchBackdrop(game: game, size: geo.size).id(game.id).transition(.opacity) }
                VStack(alignment: .leading, spacing: 0) {
                    rail(shelves, spot.shelf, k).frame(height: 50 * k).opacity(model.couchIdle ? 0 : 1)
                    ZStack(alignment: .bottomLeading) {   // the title and details sit on a fixed line, whatever their length
                        if let game { CouchInfo(game: game, k: k).id("i" + game.id).transition(still ? .opacity : .opacity.combined(with: .offset(x: -24 * k))).frame(maxWidth: geo.size.width * 0.55, alignment: .leading) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.bottom, 16 * k)
                    ZStack(alignment: .topLeading) {
                        if let shelf { row(shelf, spot.shelf, i, k).id(shelf.id).transition(still ? .opacity : .opacity.combined(with: .offset(y: 40 * k))) }
                        else { Text("Add games to your library to see them here.").font(.system(size: 28 * k)).foregroundStyle(style.soft) }
                    }
                    .frame(height: rowHeight, alignment: .topLeading).opacity(model.couchIdle ? 0 : 1)
                    hints(game, k).frame(height: 40 * k).opacity(model.couchIdle ? 0 : 1)
                }
                .padding(.horizontal, 80 * k).padding(.top, 54 * k).padding(.bottom, 40 * k)
                if let m = model.message { message(m, k) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(still ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.45), value: game?.id)
        .animation(still ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: spot.shelf)
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
                            Text(s.name).font(.system(size: 22 * k, weight: .semibold)).lineLimit(1)
                                .foregroundStyle(n == on ? style.bottom : style.soft)
                                .padding(.horizontal, 18 * k).padding(.vertical, 9 * k)
                                .background { if n == on { Capsule().fill(style.text).matchedGeometryEffect(id: "tab", in: tabs) } }
                                .contentShape(Capsule()).onTapGesture { model.couchFocus(n, model.couchSpot.at[n] ?? 0) }.id(s.id)
                                .accessibilityAddTraits(n == on ? [.isButton, .isSelected] : .isButton).accessibilityLabel(s.name)
                        }
                    }
                }
                .whenChanged(on) { if shelves.indices.contains(on) { withAnimation(still ? nil : .easeOut(duration: 0.3)) { p.scrollTo(shelves[on].id, anchor: .center) } } }
            }
            TimelineView(.everyMinute) { t in Text(t.date, style: .time).font(.system(size: 22 * k, weight: .medium)).monospacedDigit().foregroundStyle(style.soft) }.padding(.leading, 18 * k)
        }
    }

    func row(_ shelf: CouchShelf, _ n: Int, _ i: Int, _ k: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4 * k) {
            Text(shelf.name.uppercased() + "  ·  \(i + 1) of \(shelf.games.count)").font(.system(size: 17 * k, weight: .semibold)).tracking(2.5 * k).foregroundStyle(style.soft).monospacedDigit()
            ScrollViewReader { p in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 26 * k) {
                        ForEach(Array(shelf.games.enumerated()), id: \.element.id) { j, g in
                            CouchCover(game: g, on: j == i, k: k).id(g.id)
                                .onTapGesture { if j == i { model.couchMove(.accept, pad: false) } else { model.couchFocus(n, j) } }
                        }
                    }
                    .padding(.horizontal, 80 * k).padding(.vertical, 34 * k)   // room for the lifted cover and its glow
                }
                .padding(.horizontal, -80 * k)
                .onAppear { if shelf.games.indices.contains(i) { p.scrollTo(shelf.games[i].id, anchor: UnitPoint(x: 0.12, y: 0.5)) } }
                .whenChanged(i) { if shelf.games.indices.contains(i) { withAnimation(still ? nil : .easeOut(duration: 0.28)) { p.scrollTo(shelf.games[i].id, anchor: UnitPoint(x: 0.12, y: 0.5)) } } }
            }
        }
    }

    func hints(_ g: Game?, _ k: CGFloat) -> some View {
        let fav = g.map { model.library.entry($0.titleID).favorite } ?? false
        return HStack(spacing: 30 * k) {
            Spacer()
            hint("a", "Return", "Play", k); hint("y", "F", fav ? "Unfavorite" : "Favorite", k); hint("rb", "Tab", "Next shelf", k); hint("b", "Esc", "Leave", k)
        }
    }
    func hint(_ pad: String, _ key: String, _ what: String, _ k: CGFloat) -> some View {
        HStack(spacing: 9 * k) {
            if model.padUsed { Image(systemName: pad == "rb" ? "rb.rectangle.roundedbottom.fill" : pad + ".circle.fill").font(.system(size: 26 * k)).foregroundStyle(style.text) }
            else { Text(key).font(.system(size: 15 * k, weight: .semibold)).foregroundStyle(style.text).padding(.horizontal, 9 * k).padding(.vertical, 4 * k).overlay(RoundedRectangle(cornerRadius: 6 * k).strokeBorder(style.soft, lineWidth: 1.5)) }
            Text(what).font(.system(size: 20 * k, weight: .medium)).foregroundStyle(style.soft)
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
    let game: Game, k: CGFloat
    var body: some View {
        let e = model.library.entry(game.titleID), info = game.rom?.info
        let meta = [consoleName(consoleOf(game.titleID)), info?.year.map { String($0) }, info?.genre].compactMap { $0 }.joined(separator: "  ·  ")
        VStack(alignment: .leading, spacing: 14 * k) {
            Text(meta.uppercased()).font(.system(size: 19 * k, weight: .semibold)).tracking(3 * k).foregroundStyle(style.accent)
            Text(game.name).font(.system(size: 78 * k, weight: .heavy, design: .serif)).foregroundStyle(style.text).lineLimit(2).minimumScaleFactor(0.5).shadow(color: .black.opacity(style.dark ? 0.4 : 0), radius: 14 * k)
            if let a = info?.about, !a.isEmpty { Text(a).font(.system(size: 25 * k)).foregroundStyle(style.soft).lineLimit(3).lineSpacing(4 * k) }
            HStack(spacing: 30 * k) {
                stat("clock", playTimeText(e.seconds))
                if let d = e.lastPlayed { stat("calendar", "Last played " + RelativeDateTimeFormatter().localizedString(for: d, relativeTo: Date())) }
                if e.status != .none { stat("bookmark", e.status.rawValue) }
                if e.favorite { stat("heart.fill", "Favorite", style.accent) }
                if model.isRunning(game) { stat("play.fill", "Playing now", style.ok) }
            }
            if let why = game.cannot { stat("exclamationmark.triangle.fill", why, style.warn) }
        }
        .accessibilityElement(children: .combine)
    }
    func stat(_ icon: String, _ t: String, _ c: Color? = nil) -> some View {
        Label { Text(t) } icon: { Image(systemName: icon) }.font(.system(size: 21 * k, weight: .medium)).foregroundStyle(c ?? style.soft).lineLimit(1)
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
            .overlay { if game.missing { ZStack { Color.black.opacity(0.58); Label("Not connected", systemImage: "externaldrive.badge.xmark").font(.system(size: 15 * k, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center).padding(8 * k) }.clipShape(r) } }
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
