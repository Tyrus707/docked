import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var builder: Builder?
    static var moving: () -> Bool = { false }
    static var leaving: () -> Void = {}
    static var waiting: () -> Int = { 0 }
    func applicationWillFinishLaunching(_ n: Notification) { Style.apply() }
    func applicationWillTerminate(_ n: Notification) { Self.leaving() }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { !(Self.builder?.running ?? false) && !Self.moving() }
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        if Self.moving() { let a = NSAlert(); a.messageText = "A game is being moved."; a.informativeText = "Quit Docked when it has finished."; a.runModal(); return .terminateCancel }
        guard let b = Self.builder, b.running else { return .terminateNow }
        let a = NSAlert()
        a.messageText = "Stop converting \(b.title)?"
        a.informativeText = Self.waiting() > 0 ? "Finished steps are kept. This game and the \(Self.waiting()) waiting stay in the queue, ready to continue next time." : "Finished steps are kept, and the game stays in the queue, ready to continue next time."
        a.addButton(withTitle: "Keep Converting"); a.addButton(withTitle: "Stop and Quit")
        if a.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        b.onFinish = { s.reply(toApplicationShouldTerminate: true) }
        b.cancel()
        return .terminateLater
    }
}

@main struct DockedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = Model()
    var body: some Scene {
        Window("Docked", id: "main") {
            ContentView().environmentObject(model).environmentObject(model.builder).frame(minWidth: 720, minHeight: 480).onAppear { model.windowAppeared() }
        }
        .defaultSize(width: 1000, height: 660)
        .commands {
            CommandGroup(replacing: .appSettings) { Button("Settings…") { model.openSettings() }.keyboardShortcut(",") }
            CommandGroup(after: .appInfo) { Button("Check for Updates…") { model.lookForUpdate() }.disabled(model.checkingUpdate) }
            CommandGroup(replacing: .newItem) {
                Button("Add Game…") { model.pickGame() }.keyboardShortcut("o")
                Button("Find Games on This Mac…") { model.findGames() }.keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Organize Library…") { model.planTidy() }.disabled(!model.organized)
                Menu("Add Update or DLC") { ForEach(model.games.filter { $0.rom == nil }) { g in Button(g.name) { model.addTo(g) } } }.disabled(model.games.isEmpty)
                Button("Clean Up…") { model.cleanUp(nil) }
                Menu("Move Game to Folder") { ForEach(model.games.filter { $0.rom == nil }) { g in Button(g.name) { model.moveGame(g) } } }.disabled(model.games.isEmpty)
            }
            CommandGroup(after: .sidebar) { Button(model.couch ? "Leave Couch Mode" : "Couch Mode") { model.toggleCouch() }.keyboardShortcut("b", modifiers: [.command, .shift]).disabled(model.games.isEmpty && !model.couch) }
            CommandGroup(replacing: .help) { Button("How to Use Docked") { model.showHelp = true }.keyboardShortcut("?") }
        }
    }
}

final class Model: ObservableObject {
    @Published var games: [Game] = [] { didSet { memo = Memo() } }
    @Published var checks: [Check] = []
    @Published var checking = false
    @Published var message: String?   // an alert, for a problem the player must act on
    @Published var notice: Notice?     // a quiet word in the tray (Tray.swift)
    @Published var showSetup = false
    @Published var showHelp = false
    @Published var showReview = false
    @Published var review = Review(parts: [])
    @Published var reviewNote: String?   // shown on the review sheet, where the window's own alert can't appear
    @Published var keys: String? = UserDefaults.standard.string(forKey: "keysPath").map({ Paths.now($0) }) {
        didSet { UserDefaults.standard.set(keys, forKey: "keysPath") }   // only the location; the keys are never copied
    }
    // ---- library ----
    @Published var library = LibraryData.load() { didSet { if library != oldValue { memo = Memo(); saveSoon() } } }
    @Published var section = Section.home
    @Published var search = "" { didSet { if search != oldValue { memo = Memo() } } }
    // Each shelf's games, sorted, and each section's count, worked out once until the games or the library change: a big library is never sorted again just to redraw
    private struct Memo { var shown: [ShownKey: [Game]] = [:]; var counts: [Section: Int] = [:] }
    private struct ShownKey: Hashable { let section: Section, by: SortBy }
    private var memo = Memo()
    // Saved a moment after the last change, off the main thread, and at once when Docked quits: a thousand covers found in a row is one write, not a thousand
    private var saveLater: DispatchWorkItem?
    private static let saver = DispatchQueue(label: "library-save", qos: .utility)
    func saveSoon() {
        saveLater?.cancel()
        let w = DispatchWorkItem { [weak self] in guard let self else { return }; self.saveLater = nil; let l = self.library; Model.saver.async { l.save() } }
        saveLater = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }
    func saveNow() { if let w = saveLater { w.cancel(); saveLater = nil; let l = library; Model.saver.sync { l.save() } } else { Model.saver.sync {} } }
    @Published var sort = SortBy(rawValue: UserDefaults.standard.string(forKey: "sort") ?? "") ?? .recent { didSet { UserDefaults.standard.set(sort.rawValue, forKey: "sort") } }
    @Published var group = GroupBy(rawValue: UserDefaults.standard.string(forKey: "group") ?? "") ?? .auto { didSet { UserDefaults.standard.set(group.rawValue, forKey: "group") } }
    @Published var compact = UserDefaults.standard.bool(forKey: "compact") { didSet { UserDefaults.standard.set(compact, forKey: "compact") } }
    @Published var collecting: Game?
    @Published var renaming: String?
    @Published var runningIDs = Set<String>()
    private let tracker = PlayTracker()
    private var washes: [String: NSImage] = [:]

    var consolesShown: [Console] { let have = Set(games.map { consoleOf($0.titleID) }); return consoles.filter { $0.id == "switch" || have.contains($0.id) } }
    @Published var asking: (files: [URL], choices: [Console])?   // a file several consoles use
    @Published var retitling: Game?
    @Published var showConsoles = false
    // ---- covers and details, found online once the player has said yes (Lookup.swift) ----
    @Published var lookUp = UserDefaults.standard.object(forKey: "lookUp") as? Bool { didSet { UserDefaults.standard.set(lookUp, forKey: "lookUp") } }
    @Published var askLookUp = false
    @Published var picking: Picking?
    @Published var finding = Set<String>()
    @Published var scoring = Set<String>()   // games whose scores and details are being looked up, by title ID
    // Converted Switch games get their details when they are done; nil follows "Find covers and details"
    @Published var metaConverted = UserDefaults.standard.object(forKey: "metaConverted") as? Bool { didSet { UserDefaults.standard.set(metaConverted, forKey: "metaConverted") } }
    var waitingLookUp: [String] = [], picks: [Picking] = []

    // Games for other consoles, and converted games, chosen or dropped: looked through off the main thread, then brought in (Library.swift).
    func addRoms(_ urls: [URL]) {
        filing = "Looking…"
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Discover.look(urls, source: "Added", known: [])
            DispatchQueue.main.async {
                self.filing = nil
                let ready = found.filter { if case .choose = $0.kind { return false }; return true }
                let ask = found.compactMap { f -> (URL, [String])? in if case let .choose(c) = f.kind { return (f.url, c) }; return nil }
                if !ready.isEmpty { self.bringIn(ready) }
                if !ask.isEmpty { self.asking = (ask.map(\.0), consoles.filter { c in ask.contains { $0.1.contains(c.id) } }) }
                else if ready.isEmpty { self.message = "Docked doesn't recognise that. It reads Switch games, games Docked converted, and game files for the consoles listed under Consoles in Settings." }
            }
        }
    }
    func answer(_ c: Console) {
        let files = (asking?.files ?? []).filter { consolesFor($0).contains(c) }
        asking = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.bringIn(files.map { Found(url: $0, name: cleanName($0), kind: .rom(c.id), source: "Added") }) }
    }
    // ---- RetroArch, set up inside Docked the first time a console's game is added ----
    @Published var retro: RetroWork?
    @Published var wantsBios: BiosAsk?
    private var settingUp: [(console: Console, then: (() -> Void)?)] = []
    // Right after adding: RetroArch and the core download in the background, and a BIOS is asked for at once.
    func getReady(_ files: [URL], as chosen: Console? = nil) {
        var seen: [Console] = []
        for u in files { if let c = chosen ?? consolesFor(u).first, !c.native, !seen.contains(c) { seen.append(c); setUpRetro(c) } }
        if let u = files.first(where: { u in (chosen ?? consolesFor(u).first).map { RetroArch.missingBios($0, rom: u.path) != nil && !biosAsked($0) } ?? false }), let c = chosen ?? consolesFor(u).first { askBios(c) }
    }
    func setUpRetro(_ c: Console, then: (() -> Void)? = nil) {
        if RetroArch.ready(c) { then?(); return }
        settingUp.append((c, then)); if settingUp.count == 1 { nextRetro() }
    }
    private func nextRetro() {
        guard let c = settingUp.first?.console else { retro = nil; return }
        retro = RetroWork(what: "Getting \(c.name) games ready…", fraction: nil)
        var last = Date.distantPast
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try RetroArch.setUp(c) { w, f in
                guard Date().timeIntervalSince(last) > 0.25 || f == nil else { return }; last = Date()
                DispatchQueue.main.async { if self.retro != nil { self.retro = RetroWork(what: w, fraction: f) } }
            } }
            DispatchQueue.main.async {
                let waiting = self.settingUp.filter { $0.console == c }; self.settingUp.removeAll { $0.console == c }
                switch r {
                case .success: self.objectWillChange.send(); for w in waiting { w.then?() }
                case .failure(let e): self.message = "\(c.name) games can't play yet. \(e.localizedDescription)"
                }
                self.nextRetro()
            }
        }
    }
    private func biosAsked(_ c: Console) -> Bool { UserDefaults.standard.bool(forKey: "biosAsked." + c.id) }
    func askBios(_ c: Console, then: (() -> Void)? = nil) {
        if sheetUp, then == nil { return }
        UserDefaults.standard.set(true, forKey: "biosAsked." + c.id)
        wantsBios = BiosAsk(console: c, then: then)
    }
    func biosDone(play: Bool) {
        let a = wantsBios; wantsBios = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if self.picking == nil { self.nextPick() } }
        if play, let t = a?.then { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: t) }
    }
    // Files the player chose, checked and kept where the core looks. Returns what to tell them.
    func addBios(_ c: Console) -> String? {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = false; p.showsHiddenFiles = true
        p.message = "Choose the BIOS from your own \(c.name)."
        guard p.runModal() == .OK else { return nil }
        var kept: [String] = [], problem: String?
        for u in p.urls { do { kept.append(try RetroArch.addBios(u, for: c)) } catch { problem = error.localizedDescription } }
        objectWillChange.send()
        return kept.isEmpty ? problem : "Docked kept " + kept.joined(separator: " and ") + "."
    }
    func removeRom(_ g: Game) { library.removeRom(g.titleID); reload() }   // its file and its play time stay
    func forget(_ g: Game) { if g.rom != nil { removeRom(g) } else { library.removeApp(g.url.path); reload() } }   // the same for a converted game; its file stays
    func retitle(_ g: Game, _ n: String) {
        let t = String(n.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)); guard !t.isEmpty, let i = library.roms.firstIndex(where: { $0.id == g.titleID }) else { return }
        library.roms[i].name = t; reload()
    }
    func pickArt(_ g: Game) {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg, .heic, .webP, .tiff]; p.message = "Choose a cover for \(g.name)."
        if p.runModal() == .OK, let u = p.url { setArt(g, u) }
    }
    func setArt(_ g: Game, _ u: URL) {
        guard let n = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, n < 60_000_000, let i = NSImage(contentsOf: u), Cover.keep(i, at: Cover.custom(g)) else { message = "That picture couldn't be used."; return }
        forgetArt(g)
    }
    func clearArt(_ g: Game) { try? FileManager.default.removeItem(at: Cover.custom(g)); forgetArt(g) }
    func hasArt(_ g: Game) -> Bool { FileManager.default.fileExists(atPath: Cover.custom(g).path) }
    func forgetArt(_ g: Game) { dropArt(g); reload() }
    func dropArt(_ g: Game) { icons[g.id] = nil; washes[g.id] = nil; covers.removeObject(forKey: g.id as NSString); coverReady() }
    // Dropped on a game: a picture becomes its cover, sound its theme, anything else is added as usual.
    func dropped(_ urls: [URL], on g: Game) { if urls.count == 1, pictureTypes.contains(urls[0].pathExtension.lowercased()) { setArt(g, urls[0]) } else if urls.count == 1, soundTypes.contains(urls[0].pathExtension.lowercased()) { setTheme(g, urls[0]) } else { add(urls) } }
    let covers: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.totalCostLimit = 220 << 20; return c }()   // about 500 covers; the rest load again from disk
    private var making = Set<String>()
    @Published private var coverTick = 0
    private var tickSoon = false
    // Made or loaded in the background the first time it is wanted; the tile waits with a plain one.
    func cover(_ g: Game) -> NSImage? {
        if let c = covers.object(forKey: g.id as NSString) { return c }
        guard making.insert(g.id).inserted else { return nil }
        let key = g.id, id = g.titleID, rom = g.rom, app = g.url
        Cover.work.addOperation {
            let c = autoreleasepool { Cover.tile(id: id, rom: rom, app: app) }
            DispatchQueue.main.async { self.making.remove(key); self.covers.setObject(c, forKey: key as NSString, cost: Cover.cost); self.coverReady() }
        }
        return nil
    }
    // Covers that arrive together show together: one redraw at most every tenth of a second, not one per cover
    private func coverReady() {
        guard !tickSoon else { return }; tickSoon = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.tickSoon = false; self.coverTick &+= 1 }
    }
    // ---- the chosen game, or several chosen to remove together ----
    @Published var marking = false { didSet { if !marking { marked = [] } } }
    @Published var marked = Set<String>()
    func mark(_ g: Game) { if marked.contains(g.id) { marked.remove(g.id) } else { marked.insert(g.id) } }
    @Published var selected: String? { didSet { if selected != oldValue { themeUpdate() } } }
    // ---- theme music ----
    let theme = ThemePlayer()
    @Published var themes = UserDefaults.standard.object(forKey: "themes") as? Bool ?? true { didSet { UserDefaults.standard.set(themes, forKey: "themes"); themeUpdate() } }
    @Published var addingTheme = false
    func hasTheme(_ g: Game) -> Bool { Theme.has(g) }
    // Only in front, and never over a game
    func themeUpdate() { theme.play(couch ? couchGame() : chosen, on: themes && NSApp?.isActive != false && runningIDs.isEmpty) }
    func pickTheme(_ g: Game) {
        let p = NSOpenPanel(); p.allowedContentTypes = [.audio, .mpeg4Audio]; p.message = "Choose music for \(g.name). Docked keeps the first 90 seconds and leaves your file as it is."
        if p.runModal() == .OK, let u = p.url { setTheme(g, u) }
    }
    func setTheme(_ g: Game, _ u: URL) {
        guard !addingTheme else { return }; addingTheme = true; theme.stop(0.1)
        Theme.keep(u, for: g) { e in self.addingTheme = false; if let e { self.message = e } else if !self.themes { self.tell("The music is saved. Theme music is off in Settings.") }; self.themeUpdate() }
    }
    func clearTheme(_ g: Game) { theme.stop(0.2); Theme.remove(g); objectWillChange.send() }
    var chosen: Game? { selected.flatMap { id in games.first { $0.id == id } } }
    func select(_ g: Game) { if cursor != nil, cursor?.game != g.id { cursor = nil }; if selected != g.id { selected = g.id } }   // a second click of a double-click must not close it again
    private var sizes: [String: Int64] = [:], noted: [String: [String]] = [:]
    func notes(_ g: Game) -> [String] { if let n = noted[g.titleID] { return n }; let n = GameNotes.of(g.titleID); noted[g.titleID] = n; return n }
    func size(_ g: Game) -> Int64? {
        if let s = sizes[g.id] { return s }
        guard making.insert("size" + g.id).inserted else { return nil }
        DispatchQueue.global(qos: .utility).async { let s = folderSize(g.url); DispatchQueue.main.async { self.making.remove("size" + g.id); self.sizes[g.id] = s; self.coverTick += 1 } }
        return nil
    }
    // Docked's own theme, chosen in Settings; it does not follow the Mac's light or dark setting
    @Published var palette = Style.current { didSet { UserDefaults.standard.set(palette.id, forKey: "theme"); Style.current = palette; Style.apply() } }
    @Published var look = Look(rawValue: UserDefaults.standard.string(forKey: "look") ?? "") ?? .covers { didSet { UserDefaults.standard.set(look.rawValue, forKey: "look") } }
    var arrived: String?   // a game that has just been converted, until its tile has come down on the shelf
    private func playRom(_ g: Game, _ r: Rom) {
        guard let c = console(r.console) else { return }
        if let p = RetroArch.problem(c, rom: r.path) { message = p; return }
        if !RetroArch.ready(c) { setUpRetro(c) { [weak self] in self?.playRom(g, r) }; if retro == nil { tell("Docked is getting \(c.name) games ready. The game starts when it's done.") }; return }
        if let b = RetroArch.missingBios(c, rom: r.path), b.required || !biosAsked(c) { askBios(c) { [weak self] in self?.playRom(g, r) }; return }
        let look = Shaders.look(r)
        if look != .off && !Shaders.installed { getLooks { [weak self] in self?.playRom(g, r) }; return }
        let shader = Shaders.preset(look)
        if !Pads.installed { DispatchQueue.global(qos: .utility).async { try? Pads.install() } }
        do { try RetroArch.prepare(shader: shader != nil) } catch { message = "RetroArch's settings couldn't be written. \(error.localizedDescription)"; return }
        let ra = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == RetroArch.app.path }
        if let ra { if isRunning(g) { ra.activate() } else { message = "RetroArch is already open. Quit it first, then play \(g.name)." }; return }
        do {
            let pid = try RetroArch.launch(core: RetroArch.core(c)!, rom: r.path, shader: shader) { [weak self] in self?.backFromGame() }
            adoptRetro(pid, as: g.titleID.uppercased(), tries: 20); stepAside()
        } catch { message = "RetroArch couldn't start. \(error.localizedDescription)" }
    }
    // RetroArch is known to the system a moment after it starts; play time counts from then.
    private func adoptRetro(_ pid: pid_t, as id: String, tries: Int) {
        if let a = NSRunningApplication(processIdentifier: pid) { tracker.adopt(a, as: id); a.activate(options: []); return }   // in front, so the game doesn't start behind Docked
        guard tries > 0, kill(pid, 0) == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.adoptRetro(pid, as: id, tries: tries - 1) }
    }
    // A RetroArch game closed: back to the library.
    func backFromGame() {
        NSApp.unhide(nil); refreshCheevos()
        for w in NSApp.windows where w.isMiniaturized { w.deminiaturize(nil) }
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?.makeKeyAndOrderFront(nil); if couch { couchBack() }
    }
    // Retro looks: libretro's shaders, downloaded the first time a game uses one; the game starts when they're here
    private var gettingLooks: [() -> Void] = []
    func getLooks(then: @escaping () -> Void) {
        gettingLooks.append(then); guard gettingLooks.count == 1 else { return }
        retro = RetroWork(what: "Downloading retro looks…", fraction: nil); var last = Date.distantPast
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try Shaders.install { w, f in
                guard Date().timeIntervalSince(last) > 0.25 else { return }; last = Date()
                DispatchQueue.main.async { self.retro = RetroWork(what: w, fraction: f) }
            } }
            DispatchQueue.main.async {
                self.retro = nil; let waiting = self.gettingLooks; self.gettingLooks = []
                switch r { case .success: waiting.forEach { $0() }; case .failure(let e): self.message = "The retro looks couldn't be downloaded. \(e.localizedDescription)" }
            }
        }
    }
    // RetroAchievements progress, fetched again after a retro game and when asked, at most once a minute
    func refreshCheevos(force: Bool = false) {
        guard Cheevos.signedIn, Cheevos.hasWebKey, force || Date().timeIntervalSince(Cheevos.checked) > 60 else { return }
        Cheevos.checked = Date()
        DispatchQueue.global(qos: .utility).async { let e = Result { try Cheevos.refresh() }; DispatchQueue.main.async { self.objectWillChange.send(); if force, case .failure(let x) = e { self.message = x.localizedDescription } } }
    }

    func shown(_ s: Section, by: SortBy = .name) -> [Game] {
        let k = ShownKey(section: s, by: by); if let l = memo.shown[k] { return l }
        let l = library.show(games, in: s, search: search, by: by); memo.shown[k] = l; return l
    }
    func count(_ s: Section) -> Int {
        if let n = memo.counts[s] { return n }
        let n = games.reduce(0) { $0 + (library.has($1, s) ? 1 : 0) }; memo.counts[s] = n; return n
    }
    func edit(_ g: Game, _ c: (inout Entry) -> Void) { library.edit(g.titleID, c) }
    func isRunning(_ g: Game) -> Bool { runningIDs.contains(g.titleID.uppercased()) }
    func newCollection(_ name: String, adding g: Game?) { if let n = library.addCollection(name), let g { edit(g) { if !$0.collections.contains(n) { $0.collections.append(n) } } } }
    func removeCollection(_ c: String) { if section == .collection(c) { section = .home }; library.removeCollection(c) }
    func renameCollection(_ o: String, _ n: String) { let was = section; library.renameCollection(o, n); if was == .collection(o) { section = library.collections.contains(o) ? was : .home } }
    func wash(_ g: Game) -> NSImage {
        if let w = washes[g.id] { return w }
        let w = Cover.glow(icon(g), NSRect(x: 0.14, y: 0.14, width: 0.72, height: 0.72), width: 480, height: 240, blur: 34); washes[g.id] = w; return w
    }
    private func trackPlay() {
        tracker.identify = { [weak self] u in self?.games.first { u.path == $0.url.path || u.path.hasPrefix($0.url.path + "/") }?.titleID.uppercased() }
        tracker.countedUntil = { [weak self] id in self?.library.entry(id).lastPlayed }
        AppDelegate.leaving = { [weak self] in self?.tracker.flush(); self?.saveNow() }
        tracker.finished = { [weak self] id, a, b in self?.library.played(id, from: a, to: b); self?.comeBack() }
        tracker.changed = { [weak self] in guard let s = self else { return }; s.runningIDs = s.tracker.running; s.themeUpdate() }
        tracker.start()
    }

    // ---- while a game plays, Docked steps aside; when the last game closes, the library is back in front ----
    @Published var hideWhilePlaying = UserDefaults.standard.object(forKey: "hideWhilePlaying") as? Bool ?? true { didSet { UserDefaults.standard.set(hideWhilePlaying, forKey: "hideWhilePlaying") } }
    private var asideForGame = false
    func stepAside() { guard hideWhilePlaying else { return }; asideForGame = true; NSApp.hide(nil) }
    private func comeBack() {
        guard asideForGame, tracker.running.isEmpty else { return }
        asideForGame = false
        NSApp.unhide(nil)
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil); if couch { couchBack() }
    }

    let builder = Builder()
    var ready: Bool { !checks.isEmpty && checks.allSatisfy(\.ok) }

    init() {
        AppDelegate.builder = builder
        AppDelegate.moving = { [weak self] in self?.moving != nil }
        AppDelegate.waiting = { [weak self] in self?.queue.waiting.count ?? 0 }
        builder.onFinish = { [weak self] in self?.finished() }
        let hide = organized
        DispatchQueue.global(qos: .utility).async { finishRemovals(); Engine.tidy(); RetroArch.hideEarlier(); if hide { Organize.hideBuildFolders() } }
        reload(); trackPlay(); recheck(first: true)
    }

    // ---- the library folder: one folder per console (Organize.swift, Library.swift) ----
    @Published var libraryFolder = UserDefaults.standard.string(forKey: "libraryFolder").map { URL(fileURLWithPath: Paths.now($0)) } ?? Paths.games { didSet { UserDefaults.standard.set(libraryFolder.path, forKey: "libraryFolder"); reload() } }
    @Published var organized = UserDefaults.standard.object(forKey: "organized") as? Bool ?? true { didSet { UserDefaults.standard.set(organized, forKey: "organized") } }
    @Published var addMode = AddMode(rawValue: UserDefaults.standard.string(forKey: "addMode") ?? "") { didSet { UserDefaults.standard.set(addMode?.rawValue, forKey: "addMode") } }   // nil: ask each time
    @Published var naming = Naming(rawValue: UserDefaults.standard.string(forKey: "naming") ?? "") ?? .game { didSet { UserDefaults.standard.set(naming.rawValue, forKey: "naming") } }
    @Published var watched = UserDefaults.standard.stringArray(forKey: "watchedFolders") ?? [] { didSet { UserDefaults.standard.set(watched, forKey: "watchedFolders") } }
    @Published var importing: Importing?
    @Published var tidying: [Tidy]?
    @Published var askingMode: PendingAdd?
    @Published var filing: String?
    @Published var newlyAdded: String?
    @Published var missingGame: Game?
    var lastWatch = Date.distantPast, skipped = Set<String>()

    // Folders games have been saved to, besides Docked's own, so the library still shows them.
    var folders: [String] {
        get { (UserDefaults.standard.stringArray(forKey: "gameFolders") ?? []).map { Paths.now($0) } }
        set { UserDefaults.standard.set(newValue, forKey: "gameFolders") }
    }
    @Published var destination = UserDefaults.standard.string(forKey: "destination").map { URL(fileURLWithPath: Paths.now($0)) } ?? Paths.games {
        didSet { UserDefaults.standard.set(destination.path, forKey: "destination") }
    }
    @Published var reviewPlace = Paths.games   // where the game on the review screen will go
    private var buildPlace = Paths.games
    @Published var queue = Queue.load() { didSet { if queue != oldValue { queue.save() } } }
    @Published var after = After(rawValue: UserDefaults.standard.string(forKey: "afterConverting") ?? "") ?? .ask { didSet { UserDefaults.standard.set(after.rawValue, forKey: "afterConverting") } }
    @Published var cleaning: CleanUp?
    @Published var removing = false
    private var retry: DispatchWorkItem?
    @Published var moving: String?
    @Published var quick = UserDefaults.standard.bool(forKey: "skipPipeline") { didSet { UserDefaults.standard.set(quick, forKey: "skipPipeline") } }
    @Published var speed = UserDefaults.standard.string(forKey: "conversionSpeed").flatMap(Speed.init(rawValue:)) ?? (UserDefaults.standard.object(forKey: "conversionEffort") as? Int).map(Speed.init(effort:)) ?? .full { didSet { UserDefaults.standard.set(speed.rawValue, forKey: "conversionSpeed") } }
    @Published var checkingGame = false   // a game just converted is being checked
    @Published var converting = false   // kept apart from the builder, whose every progress report would redraw the library
    var arrivingIcon: NSImage? { builder.titleID.flatMap { id in games.first { $0.titleID.uppercased() == id } }.map { icon($0) } }
    @Published var offers: [Game] = []   // just finished: what is left over can go
    var icons: [String: NSImage] = [:]

    func icon(_ g: Game) -> NSImage {
        if let i = icons[g.id] { return i }
        if let r = g.rom { let i = Model.romIcon(r); icons[g.id] = i; return i }
        let has = FileManager.default.fileExists(atPath: g.url.appendingPathComponent("Contents/Resources/AppIcon.icns").path)
        let i = autoreleasepool { Cover.small(has ? NSWorkspace.shared.icon(forFile: g.url.path) : Model.plainIcon(), 256) }; icons[g.id] = i; return i   // the full-size art is let go at once
    }

    // A game's box art, cropped to a tile, or its console's colour and name
    static func romIcon(_ r: Rom) -> NSImage {
        let art = RetroArch.art(r).flatMap { NSImage(contentsOf: $0) }, c = console(r.console)
        return NSImage(size: NSSize(width: 256, height: 256), flipped: false) { _ in
            let box = NSRect(x: 25, y: 25, width: 206, height: 206), p = NSBezierPath(roundedRect: box, xRadius: 47, yRadius: 47); p.addClip()
            if let art, art.size.width > 0 {
                NSColor(white: 0.1, alpha: 1).setFill(); box.fill(); let k = max(206 / art.size.width, 206 / art.size.height), w = art.size.width * k, h = art.size.height * k
                art.draw(in: NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)); return true
            }
            NSGradient(starting: NSColor(hue: c?.hue ?? 0.5, saturation: 0.55, brightness: 0.55, alpha: 1), ending: NSColor(hue: c?.hue ?? 0.5, saturation: 0.6, brightness: 0.3, alpha: 1))?.draw(in: box, angle: -90)
            let s = NSMutableParagraphStyle(); s.alignment = .center
            let letter = NSAttributedString(string: String(r.name.prefix(1)).uppercased(), attributes: [.font: NSFont.systemFont(ofSize: 96, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: s]); letter.draw(in: NSRect(x: 25, y: 84, width: 206, height: 118))
            let name = NSAttributedString(string: c?.name ?? "", attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.9), .paragraphStyle: s]); name.draw(in: NSRect(x: 29, y: 48, width: 198, height: 28)); return true
        }
    }

    // A game without art of its own
    static func plainIcon() -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.addPath(CGPath(roundedRect: CGRect(x: 25, y: 25, width: 206, height: 206), cornerWidth: 47, cornerHeight: 47, transform: nil)); c.setFillColor(CGColor(srgbRed: 0.12, green: 0.37, blue: 0.42, alpha: 1)); c.fillPath()
            c.addPath(DPad().path(in: CGRect(x: 80, y: 80, width: 96, height: 96)).cgPath); c.setFillColor(CGColor(srgbRed: 0.88, green: 0.95, blue: 0.96, alpha: 1)); c.fillPath(); return true
        }
    }

    // Where each game's files came from: title ID -> files.
    private var sources: [String: [SourceFile]] {
        get { UserDefaults.standard.data(forKey: "sources").flatMap { try? JSONDecoder().decode([String: [SourceFile]].self, from: $0) }?.mapValues { $0.map { SourceFile(path: Paths.now($0.path), size: $0.size) } } ?? [:] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "sources") }
    }
    private var buildSources: [SourceFile] = []
    private var phoneOut: URL?   // where the engine writes an iPhone app until it is whole

    func originals(_ g: Game) -> Originals { findOriginals(links: keptFiles(g.titleID), sources: sources[g.titleID.uppercased()] ?? []) }

    // ---- cleaning up ----
    var busyBuilds: Set<String> { Set(queue.all.map { ($0.family.map { buildFolderKey($0) } ?? buildKey($0.urls)) + "_build" }) }
    private var keysNeeded: Bool { queue.all.contains { $0.needsKeys } }

    // One game, or everything. Measured off the main thread: a conversion's folder holds thousands of files.
    func cleanUp(_ g: Game?) {
        guard moving == nil, !removing else { tell("Wait until Docked has finished its current job.", good: false); return }
        let lib = games.filter { $0.rom == nil }, busy = busyBuilds, src = sources, inUse = Set(queue.all.compactMap(\.family)), k = findKeys(keys), needed = keysNeeded
        cleaning = CleanUp(one: g)
        DispatchQueue.global(qos: .userInitiated).async {
            var c = CleanUp(one: g); c.ready = true
            for var l in findLeftovers(library: lib, busy: busy) where g == nil || l.id == g!.titleID.uppercased() {
                l.bytes = l.folders.reduce(0) { $0 + folderSize($1) }
                let game = lib.first { $0.titleID.uppercased() == l.id }, safe = game.map { selfContained($0.url, titleID: $0.titleID) } ?? lib.allSatisfy { selfContained($0.url, titleID: $0.titleID) }   // whose it was is unknown, so no game may need it
                let xc = l.folders.contains(where: hasXcodeProject); c.items.append(CleanItem(kind: .leftovers(l), game: game, name: l.name, bytes: l.bytes, on: !xc && safe && (g != nil || game != nil), blocked: safe ? nil : game == nil ? "A game may still use these files, so they stay." : "This game still uses these files, so they stay.", xcode: xc))
            }
            for x in (g.map { [$0] } ?? lib) where !inUse.contains(x.titleID.uppercased()) {
                let o = findOriginals(links: keptFiles(x.titleID), sources: src[x.titleID.uppercased()] ?? [])
                if !o.isEmpty { c.items.append(CleanItem(kind: .originals(o), game: x, name: x.name, bytes: o.bytes, on: false)) }
            }
            if let k { c.items.append(CleanItem(kind: .keys(k), name: (k as NSString).lastPathComponent, bytes: 0, on: false, blocked: needed ? "Games waiting to convert need it." : nil)) }
            DispatchQueue.main.async { if self.cleaning?.one?.id == g?.id, self.cleaning?.ready == false { if c.items.isEmpty || (g != nil && !c.items.contains { $0.game != nil }) { self.cleaning = nil; self.tell(g == nil ? "There is nothing to clean up." : "There is nothing left over from \(g!.name)."); if let g { self.offers.removeAll { $0.id == g.id } } } else { self.cleaning = c } } }
        }
    }
    func doCleanUp(_ c: CleanUp) {
        cleaning = nil; removing = true; let lib = games.filter { $0.rom == nil }, busy = busyBuilds, inUse = Set(queue.all.compactMap(\.family)), needed = keysNeeded
        DispatchQueue.global(qos: .userInitiated).async {
            var failed: [String] = [], gone: [String] = [], keysGone = false
            for i in c.items where i.on && i.blocked == nil {
                switch i.kind {
                case let .leftovers(l):
                    guard (i.game.map { [$0] } ?? lib).allSatisfy({ selfContained($0.url, titleID: $0.titleID) }) else { failed.append("\(l.name)'s leftovers"); continue }
                    if !removeLeftovers(l.folders, busy: busy).isEmpty { failed.append("\(l.name)'s leftovers") } else { removeNotes(for: i.game?.url, title: l.id) }
                case let .originals(o):
                    guard let g = i.game, !inUse.contains(g.titleID.uppercased()) else { failed.append(i.name); continue }
                    let f = trashOriginals(o); if f.isEmpty { gone.append(g.titleID.uppercased()); removeNotes(for: nil, title: g.titleID.uppercased()) } else { failed += f.map(\.lastPathComponent) }
                case let .keys(k): if needed || !trashKeys(k) { failed.append(i.name) } else { keysGone = true }
                }
            }
            DispatchQueue.main.async {
                self.removing = false; if !gone.isEmpty { var s = self.sources; gone.forEach { s[$0] = nil }; self.sources = s }; if keysGone { self.keys = nil }
                let touched = Set(c.items.compactMap { $0.game?.id }); self.offers.removeAll { touched.contains($0.id) }
                if !failed.isEmpty { self.message = "These were left alone: " + failed.joined(separator: ", ") }
                self.reload(); self.startNext()
            }
        }
    }
    // Chosen before converting. Never the keys; the originals only to the Trash; and only once the finished game is proven to stand on its own.
    private func automatic(_ j: Job, _ g: Game) {
        guard j.after != .ask else { offers.removeAll { $0.id == g.id }; offers.append(g); return }
        removing = true; let busy = busyBuilds, src = sources[g.titleID.uppercased()] ?? [], id = g.titleID.uppercased()
        DispatchQueue.global(qos: .userInitiated).async {
            let safe = selfContained(g.url, titleID: g.titleID); var failed: [String] = [], trashed = false, kept = false
            if safe {
                let mine = findLeftovers(library: [g], busy: busy).filter { $0.id == id }.flatMap(\.folders); kept = mine.contains(where: hasXcodeProject); failed += removeLeftovers(mine.filter { !hasXcodeProject($0) }, busy: busy).map(\.lastPathComponent)
                if j.after == .everything { let f = trashOriginals(findOriginals(links: keptFiles(id), sources: src)); failed += f.map(\.lastPathComponent); trashed = f.isEmpty }
                if !kept { removeNotes(for: g.url, title: id) }
            }
            DispatchQueue.main.async {
                self.removing = false; if trashed { var s = self.sources; s[id] = nil; self.sources = s }
                if !safe { self.queue.problems.append(Problem(title: g.name, reason: "Converted, but it still uses its leftovers, so nothing was removed.")) }
                else if !failed.isEmpty { self.queue.problems.append(Problem(title: g.name, reason: "Converted, but these could not be removed: " + failed.joined(separator: ", "))) }
                else if kept { self.queue.problems.append(Problem(title: g.name, reason: "Converted. Its leftovers stay, because Xcode needs them to install it on an iPhone. Clean Up can remove them.")) }
                self.startNext()
            }
        }
    }

    // Every game Docked knows: converted games in its folders and wherever they were added from, games for other consoles where they are kept.
    // One that can't be found stays, marked missing, so a drive that is unplugged takes nothing out of the library.
    // One whose file was deleted, from a folder that is still there, leaves the library; its play time stays in case it comes back.
    func reload() {
        var seen = Set<String>(), l = library
        let removed = Set(l.removed), dirs = ([Paths.games, libraryFolder] + folders.map { URL(fileURLWithPath: $0) }).flatMap(libraryFolders)
        var found = (dirs.flatMap { scanLibrary($0) } + l.apps.keys.compactMap { p in seen.contains(p) ? nil : gameAt(URL(fileURLWithPath: p)) }).filter { seen.insert($0.id).inserted && !removed.contains($0.url.path) }
        found += l.settle(found: found)
        var all = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        all += l.roms.map { Game(url: URL(fileURLWithPath: $0.path), name: $0.name, titleID: $0.id, rom: $0, missing: !FileManager.default.fileExists(atPath: $0.path)) }
        let busy = moving != nil || filing != nil || removing
        let deleted = busy ? [] : all.filter { $0.missing && deletedFile($0.url.path) }
        if !deleted.isEmpty {
            for g in deleted { if g.rom != nil { l.removeRom(g.titleID) } else { l.removeApp(g.url.path) } }
            let gone = Set(deleted.map(\.id)); all.removeAll { gone.contains($0.id) }
            tell(deleted.count == 1 ? "\(deleted[0].name) was deleted, so it has left the library. Add it again and its play time comes back." : "\(deleted.count) games were deleted, so they have left the library. Add one again and its play time comes back.")
        }
        games = all
        l.meet(games); if l != library { library = l }; offers = offers.filter { o in games.contains { $0.id == o.id } }; if let s = selected, !games.contains(where: { $0.id == s }) { selected = nil }
    }
    // Many games out of the library at once. Their files stay where they are. A converted game kept in the library's own folders stays, as its file is the library.
    @discardableResult func forget(_ list: [Game]) -> (gone: Int, kept: Int) {
        var l = library, gone = 0, kept = 0
        for g in list {
            if g.rom != nil { l.removeRom(g.titleID); gone += 1 }
            else if g.missing || !inLibrary(g.url) { l.removeApp(g.url.path); gone += 1 }
            else { kept += 1 }
        }
        library = l; reload(); return (gone, kept)
    }

    private func finished() {
        icons = [:]; covers.removeAllObjects(); sizes = [:]; converting = false; if builder.stage == "Done" { arrived = builder.titleID; if let t = builder.titleID { metaArrived(t) } }; let job = queue.current
        switch builder.stage {
        case "Done":
            if let id = builder.titleID, !buildSources.isEmpty { var s = sources; s[id] = buildSources; sources = s }
            queue.done()
            if let j = job, j.phone { finishPhone(j); return }
            // Checked before it is called done, off the main thread: the signature check reads the app
            guard let id = builder.titleID else { if let app = builder.output, buildPlace.path != Paths.games.path { move(app, to: buildPlace) { self.settle(job) } } else { reload(); settle(job) }; return }
            guard let app = builder.output ?? scanLibrary().first(where: { $0.titleID.uppercased() == id })?.url else { queue.problems.append(Problem(title: job?.title ?? builder.title, reason: "It finished, but there is no game where it should be. Its leftovers were kept.", report: builder.report)); reload(); startNext(); return }
            let quick = builder.skipsPipeline, warned = builder.warnings, place = buildPlace; checkingGame = true
            DispatchQueue.global(qos: .userInitiated).async {
                let c = checkGame(app, titleID: id, quick: quick, warned: warned)
                DispatchQueue.main.async {
                    self.checkingGame = false
                    if place.path != Paths.games.path { self.move(app, to: place) { self.settle(job, c) } } else { self.reload(); self.settle(job, c) }
                }
            }
        case "Stopped": queue.stopped(); reload()
        default:
            let (t, b) = Notify.text(done: nil, failed: job?.title ?? builder.title, left: queue.waiting.count, problems: 0); Notify.say(t, b)
            queue.failed(builder.error ?? "It stopped without saying why.", report: builder.report); reload(); startNext()
        }
    }
    // ---- apps for iPhone and iPad ----
    @Published var target = Target.mac
    @Published var phoneChecks: [Check] = []
    @Published var phoneReady: [URL] = []   // just made
    @Published var xcodeReady: [String] = []
    @Published var showXcode = false
    @Published var way = InstallWay(rawValue: UserDefaults.standard.string(forKey: "installWay") ?? "") ?? .xcode { didSet { UserDefaults.standard.set(way.rawValue, forKey: "installWay") } }
    var forXcode: Bool { target == .phone && way == .xcode }
    var phoneSet: Bool { !phoneChecks.isEmpty && phoneChecks.allSatisfy(\.ok) }
    func recheckPhone() { DispatchQueue.global(qos: .userInitiated).async { let c = runPhoneChecks(); DispatchQueue.main.async { self.phoneChecks = c; self.startNext() } } }
    private func finishPhone(_ j: Job) {
        let name = builder.title, id = builder.titleID
        if j.xcode {
            guard let w = builder.work, hasXcodeProject(w), xcodeGames().contains(where: { $0.project.standardizedFileURL.resolvingSymlinksInPath().path == xcodeProject(in: w).standardizedFileURL.resolvingSymlinksInPath().path }) else { queue.problems.append(Problem(title: j.title, reason: "It finished, but there is no Xcode project where it should be.")); reload(); startNext(); return }
            xcodeReady.removeAll { $0 == name }; xcodeReady.append(name)
            let (t, b) = Notify.text(done: name + " for Xcode", failed: nil, left: queue.waiting.count, problems: queue.problems.count); Notify.say(t, b); reload(); startNext(); return
        }
        guard let from = phoneOut, looksLikeIPA(from) else { queue.problems.append(Problem(title: j.title, reason: "It finished, but there is no iPhone app where it should be.")); reload(); startNext(); return }
        let to = phoneFile(name); do { try FileManager.default.moveItem(at: from, to: to); phoneReady.append(to) } catch { queue.problems.append(Problem(title: j.title, reason: error.localizedDescription)); reload(); startNext(); return }
        let (t, b) = Notify.text(done: name + " for iPhone", failed: nil, left: queue.waiting.count, problems: queue.problems.count); Notify.say(t, b); reload()
        guard j.after != .ask, let id else { startNext(); return }
        // The app file holds everything. A Mac version made from the same folder must stand on its own before the folder goes.
        removing = true; let busy = busyBuilds, src = sources[id] ?? [], mac = games.filter { $0.titleID.uppercased() == id }
        DispatchQueue.global(qos: .userInitiated).async {
            let safe = mac.allSatisfy { selfContained($0.url, titleID: $0.titleID) }; var failed: [String] = []
            if safe { failed += removeLeftovers(findLeftovers(library: mac, busy: busy).filter { $0.id == id }.flatMap(\.folders).filter { !hasXcodeProject($0) }, busy: busy).map(\.lastPathComponent); if j.after == .everything { failed += trashOriginals(findOriginals(links: keptFiles(id), sources: src)).map(\.lastPathComponent) } }
            DispatchQueue.main.async { self.removing = false; if !safe || !failed.isEmpty { self.queue.problems.append(Problem(title: name, reason: "Made for iPhone, but some of what's left over could not be removed.")) }; self.startNext() }
        }
    }
    // ---- the first-run guide ----
    @Published var showGuide = false
    @Published var showSettings = false
    // From settings to another sheet: one has to be gone before the next can come
    var sheetUp: Bool { showReview || showSetup || showGuide || showSettings || showHelp || showConsoles || showXcode || cleaning != nil || editing != nil || wantsBios != nil || picking != nil || importing != nil || tidying != nil }
    func openSettings() { if !sheetUp { showSettings = true } }
    func leaveSetup(_ f: @escaping () -> Void) { showSetup = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: f) }
    func leaveSettings(_ f: @escaping () -> Void) { showSettings = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: f) }
    @Published var guided = UserDefaults.standard.bool(forKey: "guided") { didSet { UserDefaults.standard.set(guided, forKey: "guided") } }
    @Published var fetching = false
    func offerKeys(_ u: URL) { if readKeys(u.path) == .notKeys { message = KeysVerdict.notKeys.text } else { keys = u.path } }
    func fetchMetal() {
        guard !fetching else { return }; fetching = true; installProblem = nil
        DispatchQueue.global(qos: .userInitiated).async { let r = run("/usr/bin/xcodebuild", ["-downloadComponent", "MetalToolchain"], timeout: 3600); DispatchQueue.main.async { self.fetching = false; if r.code != 0 { self.installProblem = "Apple's download didn't finish. Check your connection and try again." }; self.recheck() } }
    }
    private func settle(_ j: Job?, _ c: GameCheck = GameCheck()) {
        let g = builder.titleID.flatMap { id in games.first(where: { $0.titleID.uppercased() == id }) }
        // One that did not pass is converted once more, first in line: the engine keeps what it finished, so only the missing part is redone
        if !c.ok, c.mendable, let j, j.again != true { var a = j; a.id = UUID(); a.again = true; queue.waiting.insert(a, at: 0); startNext(); return }
        // A game that still did not pass keeps everything it was made from: nothing is removed, whatever was chosen
        if !c.ok { queue.problems.append(Problem(title: g?.name ?? builder.title, reason: c.text(again: j?.again == true), report: c.problems.isEmpty ? nil : builder.report)) }
        let (t, b) = Notify.text(done: builder.title, failed: nil, left: queue.waiting.count, problems: queue.problems.count); Notify.say(t, b)
        guard let g else { startNext(); return }
        if !c.ok { offers.removeAll { $0.id == g.id }; if c.problems.isEmpty { offers.append(g) }; startNext(); return }
        if let j, j.after != .ask { automatic(j, g) } else { offers.removeAll { $0.id == g.id }; offers.append(g); startNext() }
    }

    // Off the main thread: another disk means a long copy.
    private func move(_ app: URL, to dir: URL, then: (() -> Void)? = nil) {
        moving = app.deletingPathExtension().lastPathComponent
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try placeGame(app, in: dir) }
            DispatchQueue.main.async {
                self.moving = nil; self.icons = [:]; self.covers.removeAllObjects()
                switch result {
                case .success: if dir.path != Paths.games.path, !self.folders.contains(dir.path) { self.folders.append(dir.path) }
                case .failure(let e): self.message = "\(app.deletingPathExtension().lastPathComponent) stayed in \(app.deletingLastPathComponent().lastPathComponent). \(e.localizedDescription)"
                }
                self.reload()
                self.offers = self.offers.compactMap { o in self.games.first { $0.titleID == o.titleID } }
                if let then { then() } else { self.startNext() }
            }
        }
    }

    func pickFolder(_ start: URL) -> URL? {
        let p = NSOpenPanel()
        p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true; p.directoryURL = start
        p.prompt = "Choose"; p.message = "Choose where to keep the game."
        guard p.runModal() == .OK, let u = p.url else { return nil }
        if let e = placeProblem(u) { if showReview { reviewNote = e.localizedDescription } else { message = e.localizedDescription }; return nil }
        return u
    }

    func pickDestination() { if let u = pickFolder(reviewPlace) { reviewPlace = u; reviewNote = nil } }

    func isOpen(_ g: Game) -> Bool { NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == g.url.standardizedFileURL } }

    func moveGame(_ g: Game) {
        guard !isOpen(g) else { message = "Save and quit \(g.name) first."; return }
        guard !builder.running, moving == nil else { tell("Wait until Docked has finished its current job.", good: false); return }
        if let u = pickFolder(g.url.deletingLastPathComponent()) { move(g.url, to: u) }
    }

    // A game already converted is replaced where it is; a new one is sorted into its console folder,
    // or into the player's chosen folder when automatic organizing is off.
    private func setReviewPlace() {
        let own = existing.map { $0.url.deletingLastPathComponent() } ?? (organized ? consoleFolder(review.family.map(consoleOf) ?? "switch") : destination)
        reviewPlace = placeProblem(own) == nil ? own : Paths.games
    }

    func recheck(first: Bool = false) {
        checking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let c = runChecks()
            DispatchQueue.main.async { self.checks = c; self.checking = false; self.startNext(); if first, !self.ready, cannotConvert() == nil, !self.queue.waiting.isEmpty { self.showSetup = true }; self.pickUpSwitch() }
        }
    }

    @Published var installing = false
    @Published var installProblem: String?

    func install() {
        guard let p = bundledPayload, !installing, !builder.running, !engineBusy else { return }
        installing = true; installProblem = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try installTools(p, sha: bundledPayloadSHA) }; Engine.forget()
            DispatchQueue.main.async {
                self.installing = false
                if case .failure(let e) = r { self.installProblem = e.localizedDescription }
                self.recheck()
            }
        }
    }

    func pickGame() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true; p.canChooseDirectories = true; p.canChooseFiles = true
        p.message = "Choose a Switch game with its update and DLC, or games for other consoles."
        if p.runModal() == .OK { add(p.urls) }
    }

    func pickKeys() -> Bool {
        let p = NSOpenPanel()
        p.message = "Choose the prod.keys file from your own Switch."; p.showsHiddenFiles = true
        guard p.runModal() == .OK, let u = p.url else { return false }
        if readKeys(u.path) == .notKeys { let a = NSAlert(); a.messageText = "That isn't a keys file"; a.informativeText = KeysVerdict.notKeys.text; a.runModal(); return false }   // shown at once, even over a sheet
        keys = u.path; return true
    }

    // Nothing starts here: files are collected and checked first, and converting waits for the Convert button.
    func add(_ picked: [URL]) {
        let fm = FileManager.default
        let isSwitch: (URL) -> Bool = { u in packageTypes.contains(u.pathExtension.lowercased()) || u.pathExtension.lowercased() == "nup" }
        let urls = picked.filter { u in
            var d: ObjCBool = false; guard fm.fileExists(atPath: u.path, isDirectory: &d) else { return false }
            guard d.boolValue else { return isSwitch(u) }
            let names = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []
            return names.contains { isSwitch($0) || ["base", "updates", "exefs"].contains($0.lastPathComponent) }
        }
        let others = picked.filter { !urls.contains($0) }
        if !others.isEmpty && !showReview { addRoms(others) }
        if urls.isEmpty { if showReview && !others.isEmpty { reviewNote = InputError.unsupported.errorDescription }; return }
        // The first Switch game: this Mac gets ready for it, and the game is kept until it is
        guard ready else { if cannotConvert() == nil { for u in urls where !waitingSwitch.contains(u) { waitingSwitch.append(u) } }; if !sheetUp { showSetup = true }; recheck(); return }
        let good = urls.filter { u in
            var d: ObjCBool = false
            return fm.fileExists(atPath: u.path, isDirectory: &d) && (d.boolValue || packageTypes.contains(u.pathExtension.lowercased()) || u.pathExtension.lowercased() == "nup")
        }
        review.add(good)
        if good.count < urls.count { showReview ? (reviewNote = InputError.unsupported.errorDescription) : (message = InputError.unsupported.errorDescription) }
        if !good.isEmpty { if !showReview { setReviewPlace() }; showReview = true }
    }

    // Switch games added before this Mac was ready: brought back once it is, unless something else is on screen
    @Published var waitingSwitch: [URL] = []
    func pickUpSwitch() {
        guard ready, !waitingSwitch.isEmpty, !sheetUp else { return }
        let u = waitingSwitch; waitingSwitch = []; add(u)
    }

    // A game that is already converted: start from the files it was made from, then add to them.
    func addTo(_ g: Game) {
        guard ready else { showSetup = true; return }
        review = Review(parts: []); review.add(keptFiles(g.titleID))
        reviewNote = review.parts.isEmpty ? "Docked doesn't have \(g.name)'s original files. Add them again, together with the update or DLC." : nil
        setReviewPlace(); showReview = true
    }

    var existing: Game? { review.family.flatMap { f in games.first { $0.titleID.uppercased() == f } } }

    // Adds the game on the review screen to the queue. It starts at once when nothing else is converting.
    func convert() -> Bool {
        guard review.blocker == nil else { return false }
        if let e = placeProblem(reviewPlace), reviewPlace.path != Paths.games.path { reviewNote = e.localizedDescription; return false }
        do {
            let parts = review.parts.map(\.url), dir = (try? parts.first?.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let packages = dir ? try resolveInput(parts, family: review.family).needsKeys : parts.contains { packageTypes.contains($0.pathExtension.lowercased()) }
            if packages, findKeys(keys) == nil, !pickKeys() { return false }
            let kept = Set(review.family.map { keptFiles($0).map(\.path) } ?? []), before = review.family.flatMap { sources[$0] } ?? []
            let now = review.parts.filter { !kept.contains($0.url.path) && packageTypes.union(["nup"]).contains($0.url.pathExtension.lowercased()) }.map { SourceFile(path: $0.url.path, size: $0.bytes) }
            let job = Job(title: existing?.name ?? jobTitle, family: review.family, parts: parts.map(\.path), place: reviewPlace.path, quick: quick, after: forXcode ? .ask : after, bytes: parts.reduce(0) { $0 + folderSize($1) }, needsKeys: packages, sources: before.filter { b in !now.contains { $0.path == b.path } } + now, target: target, viaXcode: forXcode ? true : nil, speed: speed)
            if existing == nil, !organized { destination = reviewPlace }
            let idle = queue.current == nil && queue.waiting.isEmpty
            // With nothing ahead of it, a problem is said here and now; otherwise it is checked again when its turn comes.
            if idle, !builder.running { switch verdict(job) { case let .no(why): reviewNote = why; return false; case .wait where existing.map(isOpen) == true: reviewNote = "Save and quit \(existing!.name) first."; return false; default: break } }
            if target == .phone, !phoneSet { reviewNote = "Finish the iPhone steps first."; return false }
            guard queue.add(job) else { reviewNote = "\(job.title) is already in the queue."; return false }
            if idle { queue.paused = false }; Notify.ask()
            builder.error = builder.running ? builder.error : nil
            review.parts = []; startNext(); return true
        } catch { reviewNote = error.localizedDescription; return false }
    }
    private var jobTitle: String { (review.parts.first { $0.kind == .base } ?? review.parts.first).map { cleanName($0.url) } ?? "Game" }

    private func verdict(_ j: Job) -> Queue.Verdict {
        if j.phone { if !phoneChecks.isEmpty, !phoneSet { return .no("The iPhone steps are no longer finished. Add the game again to see them.") }; if phoneChecks.isEmpty { recheckPhone(); return .wait } }
        else if let f = j.family, let g = games.first(where: { $0.titleID.uppercased() == f }), isOpen(g) { return .wait }
        for p in j.parts where !FileManager.default.fileExists(atPath: p) { return .no("\((p as NSString).lastPathComponent) can't be found.") }
        if !j.phone, let e = placeProblem(j.placeURL), j.place != Paths.games.path { return .no(e.localizedDescription) }
        if j.needsKeys, findKeys(keys) == nil { return .no("Your prod.keys file can't be found.") }
        let free = freeSpace(), need = spaceNeeded(j.bytes), f = ByteCountFormatter()
        if free < need { return .no("Not enough disk space. It needs about \(f.string(fromByteCount: need)) while converting and you have \(f.string(fromByteCount: free)).") }
        return .go
    }
    private func phoneStart(_ key: String) -> URL { try? FileManager.default.createDirectory(at: phoneFolder, withIntermediateDirectories: true); let u = phoneFolder.appendingPathComponent(".\(key).ipa"); try? FileManager.default.removeItem(at: u); phoneOut = u; return u }
    private func xcodeStart(_ key: String) -> XcodeBuild { try? FileManager.default.createDirectory(at: phoneFolder, withIntermediateDirectories: true); return xcodeBuild(for: key) }
    func startNext() {
        retry?.cancel(); retry = nil
        guard !builder.running, moving == nil, !removing, !installing, !queue.paused, !engineBusy, !checkingGame else { return }
        guard ready else { if !checks.isEmpty, !queue.waiting.isEmpty { queue.paused = true }; return }
        while let j = queue.next(verdict) {
            do {
                let input = try resolveInput(j.urls, family: j.family)
                buildPlace = j.placeURL; buildSources = j.sources
                builder.start(BuildInput(path: input.path, key: input.key, title: j.title, needsKeys: input.needsKeys, bytes: input.bytes), keys: findKeys(keys), quick: j.quick, speed: j.speed, phone: j.phone && !j.xcode ? phoneStart(input.key) : nil, xcode: j.xcode ? xcodeStart(input.key) : nil); converting = builder.running && !j.phone
                if builder.running { return }
                queue.failed(builder.error ?? "The conversion engine did not start.")
            } catch { queue.problems.append(Problem(title: j.title, reason: error.localizedDescription)); queue.done() }
        }
        // Only games that are open are left: look again shortly.
        if !queue.waiting.isEmpty { let w = DispatchWorkItem { [weak self] in self?.startNext() }; retry = w; DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: w) }
    }
    var waits: Bool { builder.running || moving != nil || removing || !queue.waiting.isEmpty }
    func queueTime(_ now: Double) -> Double { now + queue.waiting.reduce(0) { $0 + builder.whole(quick: $1.quick, phone: $1.phone, xcode: $1.xcode) } }
    func copyReport(_ t: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string); tell("Report copied, with your name, folders and keys taken out. Read it before you post it.") }
    // ---- moving with a controller or the arrow keys ----
    @Published var cursor: Cursor?
    @Published var padUsed = false
    var columns = 4, navigator = Navigator()
    @Published var editing: SmartCollection?
    @Published var tuning: Game?   // the game whose Game Settings sheet is open
    var rows: [(id: String, games: [String])] {
        if section != .home || !search.isEmpty { return ((jumpBack(columns).isEmpty ? [] : [(Self.jumpRow, jumpBack(columns))]) + gridGroups).map { (id: $0.0, games: $0.1.map(\.id)) } }
        var r: [(String, [String])] = [("recent", shown(.all, by: .recent).prefix(5).map(\.id)), ("Favorites", shown(.favorites).map(\.id))]
        for c in consolesShown { r.append((c.name, shown(.console(c.id)).map(\.id))) }; for c in library.collections { r.append((c, shown(.collection(c)).map(\.id))) }
        return r.map { (id: $0.0, games: $0.1) }
    }
    // The open section as it is drawn: its games in runs (one untitled run when not grouped), and a short row of the ones played lately above a long console's list.
    static let jumpRow = "Jump Back In"
    var gridList: [Game] { shown(section == .home ? .all : section, by: sort) }
    var gridGroups: [(String, [Game])] { library.groups(gridList, by: group, sort: sort).map { ($0.title.isEmpty ? "grid" : $0.title, $0.games) } }
    func jumpBack(_ n: Int) -> [Game] {
        guard search.isEmpty, case .console = section, sort != .recent else { return [] }
        let l = gridList; guard l.count >= GroupBy.enough else { return [] }
        return Array(library.show(l, in: .all, by: .recent).prefix { library.entry($0.titleID).lastPlayed != nil }.prefix(max(n, 1)))   // one line of the grid, so it moves like one
    }
    var sections: [Section] { [.home, .all, .favorites] + consolesShown.map { .console($0.id) } + [.status(.playing), .status(.finished), .status(.aside), .status(.none)] + library.collections.map { .collection($0) } + library.smart.map { .smart($0) } }
    // ---- Couch Mode (Couch.swift) ----
    @Published var couch = false
    @Published var couchSpot = CouchSpot()
    @Published var couchIdle = false
    var couchTimer: Timer?, couchSaved: String?, couchMadeFull = false
    var couchArts: [String: NSImage] = [:], couchArtOrder: [String] = [], couchTried = Set<String>()
    @Published var couchArtTick = 0
    let couchSound = CouchSound()
    @Published var couchSounds = UserDefaults.standard.object(forKey: "couchSounds") as? Bool ?? true { didSet { UserDefaults.standard.set(couchSounds, forKey: "couchSounds") } }
    func move(_ m: Move, pad: Bool) {
        if m == .home { toggleCouch(); return }
        if couch { couchMove(m, pad: pad); return }
        guard !sheetUp else { return }
        if pad != padUsed { padUsed = pad }
        let on = cursor.flatMap { c in games.first { $0.id == c.game } } ?? chosen
        switch m {
        case .left, .right, .up, .down: if let c = step(cursor ?? selected.flatMap { s in rows.first { $0.games.contains(s) }.map { Cursor(row: $0.id, game: s) } }, m, rows: rows, columns: section != .home || !search.isEmpty ? columns : nil) { cursor = c; if selected != nil { selected = c.game } }
        case .accept: if let g = on { if selected == g.id { play(g) } else { select(g) } } else { move(.right, pad: pad) }
        case .back: if selected != nil { selected = nil } else if section != .home { go(.home) }
        case .favorite: if let g = on { edit(g) { $0.favorite.toggle() } }
        case .play: if let g = on { play(g) }
        case .home: break
        case .nextSection, .previousSection: let l = sections, i = l.firstIndex(of: section) ?? 0; go(l[(i + (m == .nextSection ? 1 : l.count - 1)) % l.count])
        }
    }
    private func go(_ s: Section) { section = s; cursor = nil; selected = nil }
    // ---- updating in place ----
    @Published var updating = false
    // Opened from where it was downloaded
    private func arrive(_ o: Arrive.Offer) {
        let n = NSAlert(); n.messageText = Arrive.title(o); n.informativeText = Arrive.text(o); if case .update = o { n.addButton(withTitle: "Update and Reopen") } else { n.addButton(withTitle: "Move and Reopen") }; n.addButton(withTitle: "Not Now")
        guard n.runModal() == .alertFirstButtonReturn else { UserDefaults.standard.set(appVersion, forKey: "stayedPut"); return }
        updating = true
        // The older one may be open, and converting: it asks before it stops
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").filter { $0.processIdentifier != getpid() }; others.forEach { $0.activate(options: []); $0.terminate() }
        DispatchQueue.global(qos: .userInitiated).async {
            let end = Date().addingTimeInterval(60); while others.contains(where: { !$0.isTerminated }), Date() < end { Thread.sleep(forTimeInterval: 0.3) }
            let r = Result { if others.contains(where: { !$0.isTerminated }) { throw UpdateError("The older Docked is still open. Quit it, then open this one again.") }; try Arrive.go(Bundle.main.bundleURL, o) }
            DispatchQueue.main.async { self.updating = false; switch r { case let .failure(e): self.message = e.localizedDescription; case .success: Update.reopen(o.app); NSApp.terminate(nil) } }
        }
    }
    func installUpdate(_ v: String) {
        guard !updating else { return }
        guard !builder.running, moving == nil, !removing, !installing, !engineBusy, !checkingGame else { tell("Docked can update once it has finished its current job.", good: false); return }
        updating = true
        Update.fetch(v) { r in
            switch r {
            case let .failure(e): self.updating = false; self.message = e.localizedDescription + " You can get it from the Docked page."
            case let .success((z, g)):
                DispatchQueue.global(qos: .userInitiated).async {
                    let r = Result { try Update.install(z, g, version: v, over: Bundle.main.bundleURL) }
                    DispatchQueue.main.async {
                        self.updating = false
                        switch r { case let .failure(e): self.message = e.localizedDescription
                        case .success: self.update = nil; if self.builder.running || self.moving != nil || self.removing { self.tell("Docked \(v) is in place. It opens next time.") } else { Update.reopen(Bundle.main.bundleURL); NSApp.terminate(nil) } }
                    }
                }
            }
        }
    }
    // ---- engine updates: signed by Docked's maker, put in place only while nothing converts, and the one before is kept ----
    @Published var engine: EngineInfo?   // a newer engine, ready to install
    private var engineSigned: (Data, Data)?
    @Published var engineBusy = false
    @Published var checkingEngine = false
    var carriesEngine: Bool { bundledPayload != nil || Paths.unpacked }
    var engineFree: Bool { !builder.running && queue.current == nil && moving == nil && !removing && !installing && !updating && !checkingGame }
    func lookForEngine(quiet: Bool = false) {
        guard !checkingEngine, !engineBusy else { return }
        guard Paths.unpacked else { if !quiet { tell("Install the conversion tools first. A newer engine can come after that.", good: false) }; return }
        checkingEngine = true
        Engine.check { a, m, s in
            self.checkingEngine = false
            switch a {
            case let .available(i): if let m, let s { self.engine = i; self.engineSigned = (m, s) }
            case .newest: self.engine = nil; if !quiet { self.tell("You have the newest conversion engine.") }
            case let .needsApp(v): self.engine = nil; if !quiet { self.message = "A newer conversion engine needs Docked \(v). Update Docked first." }
            case .unknown: if !quiet { self.tell("Docked could not check for a newer engine. Try again later.", good: false) }
            }
        }
    }
    func installEngine() {
        guard !engineBusy, let signed = engineSigned else { return }
        let (m, s) = signed
        guard engineFree else { tell("Docked can update its engine once it has finished its current job.", good: false); return }
        engineBusy = true; let day = engine?.when.map(engineDay)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try Engine.prepare(manifest: m, sig: s) }
            DispatchQueue.main.async {
                switch r {
                case let .failure(e): self.message = e.localizedDescription
                case let .success(next):
                    // Nothing can have started meanwhile, but the swap is the one step that must never happen during a conversion
                    guard self.engineFree else { try? FileManager.default.removeItem(at: next); self.tell("Docked can update its engine once it has finished its current job.", good: false); break }
                    do { try Engine.swapIn(next); self.engine = nil; self.engineSigned = nil; self.tell("The conversion engine is updated" + (day.map { " to the one from \($0)" } ?? "") + ". Converted games stay as they are, and Settings can switch back.") }
                    catch { self.message = error.localizedDescription }
                }
                self.engineBusy = false; self.recheck()
            }
        }
    }
    func engineBack() {
        guard !engineBusy else { return }
        guard engineFree else { tell("Docked can change its engine once it has finished its current job.", good: false); return }
        do { try Engine.goBack(); engine = nil; tell("Docked has switched engines. Settings can switch back.") } catch { message = error.localizedDescription }
        recheck()
    }
    @Published var checkingUpdate = false
    @Published var update: String?   // a newer version, found at launch
    @Published var updatesAtLaunch = UserDefaults.standard.object(forKey: "updatesAtLaunch") as? Bool ?? true { didSet { UserDefaults.standard.set(updatesAtLaunch, forKey: "updatesAtLaunch") } }
    @Published var fullScreen = UserDefaults.standard.object(forKey: "fullScreen") as? Bool ?? true { didSet { UserDefaults.standard.set(fullScreen, forKey: "fullScreen") } }
    private var launched = false
    // Once, when the window first appears. A failed look says nothing: being offline is not a problem worth a message.
    func windowAppeared() {
        guard !launched else { return }; launched = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.findMetaAll() }   // games not looked up this month fill in slowly, in the background
        for n in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] { NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] x in if x.name == NSApplication.didResignActiveNotification { self?.theme.stop() } else { self?.themeUpdate(); self?.lookInWatched() } } }
        // A drive plugged in or out: its games come back, or show as not connected, and its watched folders are looked through
        for n in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] { NSWorkspace.shared.notificationCenter.addObserver(forName: n, object: nil, queue: .main) { [weak self] x in self?.icons = [:]; self?.covers.removeAllObjects(); self?.reload(); if x.name == NSWorkspace.didMountNotification { self?.lookInWatched(force: true) } } }
        lookInWatched(force: true)
        if ProcessInfo.processInfo.environment["DOCKED_ROOT"] == nil { DispatchQueue.global(qos: .utility).async { Update.clearBackups(Paths.root.appendingPathComponent("Backups")) } }
        if ProcessInfo.processInfo.environment["DOCKED_ROOT"] == nil, let o = Arrive.offer(me: Bundle.main.bundleURL), UserDefaults.standard.string(forKey: "stayedPut") != appVersion { DispatchQueue.main.async { self.arrive(o) } }
        // Fills the screen the way the green button does with Option held: still a window on the desktop, no Space of its own. Control-Command-F still gives true full screen.
        else if fullScreen { DispatchQueue.main.async { if let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }), !w.styleMask.contains(.fullScreen), let s = w.screen ?? NSScreen.main { w.setFrame(s.visibleFrame, display: true) } } }
        navigator.act = { [weak self] m, pad in self?.move(m, pad: pad) }; navigator.couch = { [weak self] in self?.couch == true }; navigator.start()
        if updatesAtLaunch { checkForUpdate { if case let .available(v) = $0 { self.update = v } }; if Paths.unpacked, cannotConvert() == nil { lookForEngine(quiet: true) } }
    }
    func lookForUpdate() {
        guard !checkingUpdate else { return }; checkingUpdate = true
        checkForUpdate { a in
            self.checkingUpdate = false
            switch a {
            case .newest: self.tell("You have the newest Docked (\(appVersion)).")
            case .unknown: self.tell("Docked could not check for updates. Try again later.", good: false)
            case let .available(v): let n = NSAlert(); n.messageText = "Docked \(v) is available"; n.informativeText = "You have \(appVersion). Docked checks the update is genuine, keeps a copy of this version, and reopens. Your games and settings stay."; n.addButton(withTitle: "Update and Reopen"); n.addButton(withTitle: "Not Now"); if n.runModal() == .alertFirstButtonReturn { self.update = v; self.installUpdate(v) }
            }
        }
    }
    func resumeQueue() { queue.paused = false; builder.error = nil; startNext(); if !ready { showSetup = true } }

    func play(_ g: Game, settings: Bool = false) {
        theme.stop(0.3)
        if g.missing { missingGame = g; return }
        if let r = g.rom { playRom(g, r); return }
        if isRunning(g), let a = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == g.url.path }) { a.activate(); return }
        if let why = g.cannot { message = "\(g.name) cannot run here. \(why)."; return }
        let c = NSWorkspace.OpenConfiguration()
        if !settings { c.environment = ["DM_LAUNCHER": "0"] }   // straight into the game
        NSWorkspace.shared.openApplication(at: g.url, configuration: c) { _, e in
            DispatchQueue.main.async { if let e { self.message = e.localizedDescription } else { self.stepAside() } }
        }
    }

    func trash(_ u: URL) {
        do { try FileManager.default.trashItem(at: u, resultingItemURL: nil); library.removeApp(u.path) } catch { message = error.localizedDescription }
        reload()
    }
}

struct ContentView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var builder: Builder
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var dropping = false
    @State private var deleting: Game?
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            if model.games.isEmpty && !model.converting { empty } else {
                Shell(deleting: $deleting)
                    .overlay(alignment: .bottom) { if let g = model.offers.first, model.chosen == nil { FinishCard(game: g, more: model.offers.count - 1).id(g.id).padding(20).transition(still ? .opacity : .move(edge: .bottom).combined(with: .opacity)) } }
                    .animation(still ? nil : .spring(response: 0.42, dampingFraction: 0.8), value: model.chosen == nil ? model.offers.first?.id : nil)
            }
            Tray()
        }
        .background(Backdrop())
        .overlay { if model.couch { CouchView().transition(.opacity) } }
        .animation(still ? nil : .easeInOut(duration: 0.35), value: model.couch)
        .preferredColorScheme(model.palette.dark ? .dark : .light)
        .overlay { if dropping && !model.games.isEmpty { RoundedRectangle(cornerRadius: 12).strokeBorder(style.accent, lineWidth: 3).padding(6).allowsHitTesting(false) } }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { loadDropped($0) { model.add($0) }; return true }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search games")
        .alert("New Collection", isPresented: .init(get: { model.collecting != nil }, set: { if !$0 { model.collecting = nil } })) { TextField("Name", text: $newName); Button("Create") { model.newCollection(newName, adding: model.collecting); newName = "" }; Button("Cancel", role: .cancel) { newName = "" } }
        .alert("Rename Collection", isPresented: .init(get: { model.renaming != nil }, set: { if !$0 { model.renaming = nil } })) { TextField("Name", text: $newName); Button("Rename") { if let o = model.renaming { model.renameCollection(o, newName) }; newName = "" }; Button("Cancel", role: .cancel) { newName = "" } }
        .toolbar {
            Button { model.pickGame() } label: { Label("Add Game", systemImage: "plus") }
            Button { model.toggleCouch() } label: { Label("Couch Mode", systemImage: "tv") }.help("Couch Mode: your library full screen, for a controller (Command-Shift-B)").disabled(model.games.isEmpty)
            Button { model.openSettings() } label: { Label("Settings", systemImage: "gearshape") }.help("Settings (Command-Comma)")
        }
        .sheet(isPresented: $model.showSettings) { SettingsSheet() }
        .sheet(isPresented: $model.showGuide) { GuideView() }
        .sheet(isPresented: $model.showSetup) { SetupView() }
        .sheet(isPresented: $model.showXcode) { XcodeStepsView() }
        .sheet(isPresented: $model.showConsoles) { ConsolesView() }
        .sheet(item: $model.wantsBios) { BiosView(ask: $0) }
        .sheet(isPresented: .init(get: { model.importing != nil }, set: { if !$0 { model.importing = nil } })) { ImportView() }
        .sheet(isPresented: .init(get: { model.tidying != nil }, set: { if !$0 { model.tidying = nil } })) { TidyView() }
        .sheet(item: $model.askingMode) { AddModeView(pending: $0) }
        .alert(model.missingGame.map { "\($0.name) can't be found" } ?? "", isPresented: .init(get: { model.missingGame != nil }, set: { if !$0 { model.missingGame = nil } }), presenting: model.missingGame) { g in
            Button("Locate…") { model.locate(g) }; Button("Remove from Library") { model.forget(g) }; Button("Cancel", role: .cancel) {}
        } message: { g in Text(drive(of: g.url.path).map { !$0.connected ? "It's on \($0.name). Connect the drive and it plays as before." : "It was in \($0.name), but isn't there now. If you moved it, show Docked where it is." } ?? "It was in \(FileManager.default.displayName(atPath: g.url.deletingLastPathComponent().path)), but isn't there now. If you moved it, show Docked where it is.") }
        .confirmationDialog("Which console is \(model.asking?.files.first.map { cleanName($0) } ?? "this")\((model.asking?.files.count ?? 1) > 1 ? " and the others" : "") for?", isPresented: .init(get: { model.asking != nil }, set: { if !$0 { model.asking = nil } })) { ForEach(model.asking?.choices ?? []) { c in Button(c.name) { model.answer(c) } } }
        .alert("Rename Game", isPresented: .init(get: { model.retitling != nil }, set: { if !$0 { model.retitling = nil } })) { TextField("Name", text: $newName); Button("Rename") { if let g = model.retitling { model.retitle(g, newName) }; newName = "" }; Button("Cancel", role: .cancel) { newName = "" } }
        .alert("Find covers and details for your games?", isPresented: .init(get: { model.askLookUp && model.wantsBios == nil }, set: { if !$0 { model.askLookUp = false } })) { Button("Find Them") { model.allowLookUp(true) }; Button("Not Now", role: .cancel) { model.allowLookUp(false) } } message: { Text(Lookup.consent) }
        .sheet(item: $model.picking, onDismiss: { model.nextPick() }) { GamePicker(pick: $0) }
        .sheet(isPresented: $model.showHelp) { HelpView() }
        .sheet(isPresented: $model.showReview) { ReviewView() }
        .sheet(item: $model.editing) { SmartEditor(s: $0) }
        .sheet(item: $model.tuning) { g in if let gs = GameSettings(app: g.url) { GameSettingsView(game: g, gs: gs) } }
        .sheet(isPresented: .init(get: { model.cleaning != nil }, set: { if !$0 { model.cleaning = nil } })) { CleanUpView() }
        .alert("Docked", isPresented: .init(get: { model.message != nil && !model.couch }, set: { if !$0 { model.message = nil } })) { Button("OK") {} } message: { Text(model.message ?? "") }
        .confirmationDialog("Move \(deleting?.name ?? "") to the Trash?", isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { g in
            Button("Move to Trash", role: .destructive) { model.trash(g.url) }
        } message: { _ in Text("Your saved progress is kept.") }
    }

    // The first thing a new player sees: their shelf, not a converter. Switch setup waits until a Switch game arrives.
    var empty: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                DPad().fill(style.accent).frame(width: 46, height: 46).accessibilityHidden(true)
                Text("Your games, all on one shelf").font(.largeTitle.weight(.semibold)).foregroundStyle(style.text).multilineTextAlignment(.center)
                Text("Drop games anywhere in this window. From the NES to the Switch, they live together here.").foregroundStyle(style.soft).multilineTextAlignment(.center)
            }
            HStack(alignment: .top, spacing: 14) {
                card("gamecontroller", "Add games", "Game files from this Mac or a drive. Docked works out the console, finds the cover and gets it ready to play.", "Add Games…", primary: true) { model.pickGame() }
                card("magnifyingglass", "Bring in games you have", "Docked looks in OpenEmu, RetroArch, Ryujinx, folders called ROMs and your drives, then shows you the list first.", "Find Games…") { model.findGames() }
            }.fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                Text("Plays games from \(consoleCount) consoles").font(.caption.weight(.semibold)).foregroundStyle(style.soft)
                HStack(spacing: 6) {
                    ForEach(["nes", "snes", "n64", "gba", "genesis", "ps1", "switch"].compactMap(console), id: \.id) { c in
                        HStack(spacing: 6) { Circle().fill(c.color).frame(width: 8, height: 8).accessibilityHidden(true); Text(c.name).font(.caption).foregroundStyle(style.text).lineLimit(1) }
                            .padding(.horizontal, 10).frame(height: 24).background(style.tile, in: Capsule())
                    }
                    Text("and \(consoleCount - 7) more").font(.caption).foregroundStyle(style.soft).padding(.horizontal, 6)
                }
            }.accessibilityElement(children: .combine)
            if cannotConvert() == nil {
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars").foregroundStyle(style.accent).accessibilityHidden(true)
                    Text("Have Switch games you own? Docked can turn them into real Mac apps. It sets that up the first time you add one.").font(.callout).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("How It Works") { model.showHelp = true }.buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(style.accent)
                }
            } else {
                Button("How to Use Docked") { model.showHelp = true }.buttonStyle(.plain).foregroundStyle(style.accent)
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 30).frame(maxWidth: 800)
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(dropping ? style.accent : style.line.opacity(0.9), style: StrokeStyle(lineWidth: dropping ? 2.5 : 1.5, dash: [7, 6])) }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var consoleCount: Int { consoles.filter { !$0.native }.count + 1 }   // the retro ones, and Switch
    func card(_ s: String, _ t: String, _ d: String, _ b: String?, primary: Bool = false, _ f: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: s).font(.title).foregroundStyle(style.accent).frame(height: 30, alignment: .leading).accessibilityHidden(true)
            Text(t).font(.headline).foregroundStyle(style.text)
            Text(d).font(.callout).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let b { if primary { Button(b, action: f).buttonStyle(.borderedProminent).tint(style.button) } else { Button(b, action: f) } }
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(style.tile, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct BuildBar: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var builder: Builder
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(builder.title).font(.headline).foregroundStyle(style.text)
                    Text(status).font(.callout).foregroundStyle(builder.error == nil ? style.soft : style.danger).lineLimit(4).textSelection(.enabled)
                    if builder.tested == false { Text("Nobody has tested this game yet, so it may not start.").font(.caption).foregroundStyle(style.warn) }
                }
                Spacer()
                Button(showLog ? "Hide Details" : "Details") { showLog.toggle() }
                if builder.running { Button("Stop") { builder.cancel() } } else { Button("Copy Report") { model.copyReport(builder.report) }; Button("Dismiss") { builder.error = nil } }
            }
            if builder.running {
                TimelineView(.periodic(from: .now, by: 5)) { t in VStack(spacing: 8) {
                    HStack {
                        if let left = builder.remaining(t.date) { Text(timeLeftText(left)! + (model.queue.waiting.isEmpty ? "" : ". All \(model.queue.waiting.count + 1) games: " + shortTime(model.queueTime(left)))) }
                        Spacer()
                        Text(elapsedText(t.date.timeIntervalSince(builder.started))).foregroundStyle(.secondary)
                    }.font(.callout)
                    ProgressView(value: builder.overall(t.date)).tint(style.accent).accessibilityLabel("Conversion progress")
                } }
            }
            if showLog {
                ScrollView { Text(builder.log.suffix(200).joined(separator: "\n")).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(height: 140).fromBottom()
            }
        }.padding(16)
    }

    var status: String {
        if let e = builder.error { return e }
        let s = builder.stageCount > 0 ? "Step \(builder.stageIndex) of \(builder.stageCount): \(builder.stage)" : builder.stage
        if let p = builder.parts { return s + ", \(p.done) of \(p.total) parts done" }
        return s
    }
}

struct ConsolesView: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss
    @State private var note: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Consoles").font(.title2.weight(.semibold))
            Text(RetroArch.installed ? "Switch games run natively. The others play in RetroArch \(RetroArch.installedVersion ?? ""), which Docked keeps inside its own folder with their saves." : "Switch games run natively. The others play in RetroArch, which Docked downloads and keeps inside its own folder the first time you add one of their games.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(consoles) { c in
                        let ok = c.native || (RetroArch.ready(c) && (RetroArch.bios[c.id].map { !$0.required || !$0.onlyFor.isEmpty } ?? true || RetroArch.hasBios(c)))
                        HStack {
                            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? style.ok : Color.secondary).accessibilityLabel(ok ? "Ready" : "Not ready")
                            VStack(alignment: .leading, spacing: 1) { Text(c.name); Text(detail(c)).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if RetroArch.bios[c.id] != nil { Button(RetroArch.hasBios(c) ? "Replace BIOS…" : "Add BIOS…") { note = model.addBios(c) }.controlSize(.small) }
                            Text((c.types + c.shared).prefix(5).map { "." + $0 }.joined(separator: " ")).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                        Divider()
                    }
                }
            }.frame(height: 330)
            if let note { Text(note).font(.callout).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).tint(style.button) }
        }.padding(24).frame(width: 560).background(AllowQuit()).background(Backdrop())
    }
    func detail(_ c: Console) -> String {
        if c.native { return "Native" }
        let core = RetroArch.core(c).map { u in c.cores.first { u.lastPathComponent == "\($0.file)_libretro.dylib" }?.label ?? "" }
        var s = core.map { "Plays with \($0)" } ?? "Docked downloads the \(c.cores[0].label) core when you add a game"
        if RetroArch.bios[c.id] != nil { s += RetroArch.hasBios(c) ? ". BIOS added" : ". Needs \(c.needs)" }
        return s
    }
}

struct RetroWork: Equatable { var what: String; var fraction: Double? }
struct BiosAsk: Identifiable { let console: Console; let then: (() -> Void)?; var id: String { console.id } }

// Asks for a system file only the player's own console has. Docked never downloads one.
struct BiosView: View {
    @EnvironmentObject var model: Model
    let ask: BiosAsk
    @State private var note: String?
    var c: Console { ask.console }
    var b: Bios { RetroArch.bios[c.id] ?? Bios() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(b.required ? "\(c.name) games need a BIOS" : "\(c.name) games play best with a BIOS").font(.title2.weight(.semibold))
            Text("A BIOS is a system file copied from your own \(c.name)\(b.onlyFor.isEmpty ? "" : ", for its CD games"). Docked can't download one for you. Choose it once and Docked keeps a copy inside its RetroArch.").fixedSize(horizontal: false, vertical: true)
            Text("It takes \(b.names).").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !b.required { Text("Without one, \(c.name) games start with a free stand-in. Most run, but some don't.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if let note { Text(note).font(.callout).foregroundStyle(style.danger).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button(b.required || ask.then == nil ? "Not Now" : "Play Without") { model.biosDone(play: !b.required) }
                Button("Choose BIOS…") { note = model.addBios(c); if RetroArch.hasBios(c) { model.biosDone(play: true) } }.keyboardShortcut(.defaultAction).tint(style.button)
            }
        }.padding(24).frame(width: 480).background(AllowQuit()).background(Backdrop())
    }
}

extension View { @ViewBuilder func fromBottom() -> some View { if #available(macOS 14, *) { defaultScrollAnchor(.bottom) } else { self } } }

struct SetupView: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss
    @State private var copied: String?
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    private var first: URL? { model.waitingSwitch.first }   // the Switch game that brought this up, if one did
    private var keysFound: Bool { findKeys(model.keys) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let first {
                HStack(spacing: 14) {
                    DPad().fill(style.accent).frame(width: 40, height: 40).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Let's get Switch games ready").font(.title2.weight(.semibold))
                        Text("\(cleanName(first))\(model.waitingSwitch.count > 1 ? " and \(model.waitingSwitch.count - 1) more" : "") will become real Mac apps. This Mac needs a few things first, only once.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("Setup").font(.title2.weight(.semibold))
                Text("These are needed once. Where there's a command, copy it, paste it into Terminal and press Return.").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.checks) { c in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: c.ok ? "checkmark.circle.fill" : "circle").foregroundStyle(c.ok ? style.ok : Color.secondary)
                            .accessibilityLabel(c.ok ? "Done" : "Not done")
                        VStack(alignment: .leading) { Text(c.title); Text(c.detail).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if !c.ok, c.installs {
                            if model.installing { ProgressView().controlSize(.small) }
                            Button(model.installing ? "Installing…" : "Install") { model.install() }.disabled(model.installing)
                        }
                        if !c.ok, !c.fix.isEmpty {
                            Button(copied == c.id ? "Copied" : "Copy Command") {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c.fix, forType: .string); copied = c.id
                            }
                        }
                    }
                }
                if first != nil {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: keysFound ? "checkmark.circle.fill" : "circle").foregroundStyle(keysFound ? style.ok : Color.secondary).accessibilityLabel(keysFound ? "Done" : "Not done")
                        VStack(alignment: .leading) { Text("Your prod.keys file"); Text(keysFound ? "Found. Docked only remembers where it is." : "Copied from your own Switch. Not needed for .nup files or dump folders.").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button(keysFound ? "Change…" : "Choose…") { _ = model.pickKeys() }
                    }
                }
            }.padding(first == nil ? 0 : 12).background(first == nil ? Color.clear : style.tile, in: RoundedRectangle(cornerRadius: 10))
            if let p = model.installProblem { Label(p, systemImage: "exclamationmark.circle").foregroundStyle(style.danger).font(.callout) }
            if first != nil { Label("Your game is kept here. Once everything is ready, Docked picks up where you left off, so you can close this and keep playing.", systemImage: "clock").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if model.checking { ProgressView().controlSize(.small) }
                if first != nil { Button("What's Needed and Why") { model.leaveSetup { model.showHelp = true } }.buttonStyle(.plain).foregroundStyle(style.accent) }
                Spacer()
                Button("Check Again") { model.recheck() }.disabled(model.checking)
                if first != nil && !model.ready { Button("Not Now") { dismiss() }.keyboardShortcut(.cancelAction) }
                else { Button(first != nil ? "Continue" : "Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(style.button) }
            }
        }.padding(24).frame(width: 540).background(AllowQuit()).background(Backdrop())
        .onReceive(tick) { _ in if first != nil, !model.ready, !model.checking, !model.installing, !model.fetching { model.recheck() } }
        .onDisappear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.pickUpSwitch() } }
    }
}

// macOS refuses to quit while a sheet is open unless the sheet's window allows it.
struct AllowQuit: NSViewRepresentable {
    final class V: NSView { override func viewDidMoveToWindow() { window?.preventsApplicationTerminationWhenModal = false } }
    func makeNSView(context: Context) -> V { V() }
    func updateNSView(_ v: V, context: Context) {}
}
