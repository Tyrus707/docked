import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var builder: Builder?
    static var moving: () -> Bool = { false }
    static var leaving: () -> Void = {}
    func applicationWillTerminate(_ n: Notification) { Self.leaving() }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { !(Self.builder?.running ?? false) && !Self.moving() }
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        if Self.moving() { let a = NSAlert(); a.messageText = "A game is being moved."; a.informativeText = "Quit Docked when it has finished."; a.runModal(); return .terminateCancel }
        guard let b = Self.builder, b.running else { return .terminateNow }
        let a = NSAlert()
        a.messageText = "Stop converting \(b.title)?"
        a.informativeText = "Finished steps are kept, so adding the game again continues from there."
        a.addButton(withTitle: "Keep Converting"); a.addButton(withTitle: "Stop and Quit")
        if a.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        b.onFinish = { s.reply(toApplicationShouldTerminate: true) }
        b.cancel()
        return .terminateLater
    }
}

@main struct DocksideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = Model()
    var body: some Scene {
        Window("Docked", id: "main") {
            ContentView().environmentObject(model).environmentObject(model.builder).frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1000, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Game…") { model.pickGame() }.keyboardShortcut("o")
                Menu("Add Update or DLC") { ForEach(model.games.filter { $0.rom == nil }) { g in Button(g.name) { model.addTo(g) } } }.disabled(model.games.isEmpty)
                Menu("Move Original Files to Trash") { ForEach(model.games.filter { $0.rom == nil }) { g in Button(g.name) { model.offerTrash(g) } } }.disabled(model.games.isEmpty)
                Menu("Move Game to Folder") { ForEach(model.games.filter { $0.rom == nil }) { g in Button(g.name) { model.moveGame(g) } } }.disabled(model.games.isEmpty)
            }
            CommandGroup(replacing: .help) { Button("How to Use Docked") { model.showHelp = true }.keyboardShortcut("?") }
        }
    }
}

final class Model: ObservableObject {
    @Published var games: [Game] = []
    @Published var checks: [Check] = []
    @Published var checking = false
    @Published var message: String?
    @Published var showSetup = false
    @Published var showHelp = false
    @Published var showReview = false
    @Published var review = Review(parts: [])
    @Published var reviewNote: String?   // shown on the review sheet, where the window's own alert can't appear
    @Published var keys: String? = UserDefaults.standard.string(forKey: "keysPath") {
        didSet { UserDefaults.standard.set(keys, forKey: "keysPath") }   // only the location; the keys are never copied
    }
    // ---- library ----
    @Published var library = LibraryData.load() { didSet { if library != oldValue { library.save() } } }
    @Published var section = Section.home
    @Published var search = ""
    @Published var sort = SortBy(rawValue: UserDefaults.standard.string(forKey: "sort") ?? "") ?? .recent { didSet { UserDefaults.standard.set(sort.rawValue, forKey: "sort") } }
    @Published var collecting: Game?
    @Published var renaming: String?
    @Published var runningIDs = Set<String>()
    private let tracker = PlayTracker()
    private var washes: [String: NSImage] = [:]

    var consolesShown: [Console] { let have = Set(games.map { consoleOf($0.titleID) }); return consoles.filter { $0.id == "switch" || have.contains($0.id) } }
    @Published var asking: (files: [URL], choices: [Console])?   // a file several consoles use
    @Published var retitling: Game?
    @Published var showConsoles = false

    // Games for other consoles are kept where they are; only their place is remembered.
    func addRoms(_ urls: [URL]) {
        var ask: [URL] = [], choices: [Console] = [], added = 0, last: Console?
        for u in pickRoms(urls) {
            let c = consolesFor(u)
            if c.count == 1 { library.addRom(Rom(id: romID(u, c[0].id), name: cleanName(u), console: c[0].id, path: u.path)); added += 1; last = c[0] }
            else if c.count > 1 { ask.append(u); for x in c where !choices.contains(x) { choices.append(x) } }
        }
        if added > 0 { reload(); if let l = last { section = .console(l.id) } }
        if !ask.isEmpty { asking = (ask, choices) }
        else if added == 0 { message = "Docked doesn't recognise that file. It reads Switch games, and game files for the consoles listed under Consoles in the Options menu." }
    }
    func answer(_ c: Console) {
        for u in asking?.files ?? [] where consolesFor(u).contains(c) { library.addRom(Rom(id: romID(u, c.id), name: cleanName(u), console: c.id, path: u.path)) }
        asking = nil; reload(); section = .console(c.id)
    }
    func removeRom(_ g: Game) { library.removeRom(g.titleID); reload() }   // its file and its play time stay
    func retitle(_ g: Game, _ n: String) {
        let t = String(n.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)); guard !t.isEmpty, let i = library.roms.firstIndex(where: { $0.id == g.titleID }) else { return }
        library.roms[i].name = t; reload()
    }
    func pickArt(_ g: Game) {
        guard let r = g.rom else { return }
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg]; p.message = "Choose a picture for \(g.name)."
        guard p.runModal() == .OK, let u = p.url, let i = NSImage(contentsOf: u), i.size.width > 0 else { return }
        let side: CGFloat = 512, o = NSImage(size: NSSize(width: side, height: side)), k = max(side / i.size.width, side / i.size.height), w = i.size.width * k, h = i.size.height * k
        o.lockFocus(); i.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h)); o.unlockFocus()
        let to = Paths.root.appendingPathComponent("Artwork/" + r.id.replacingOccurrences(of: ":", with: "-") + ".png")
        try? FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = o.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) })?.representation(using: .png, properties: [:]) { try? d.write(to: to, options: .atomic) }
        icons[g.id] = nil; washes[g.id] = nil; reload()
    }
    private func playRom(_ g: Game, _ r: Rom) {
        guard let c = console(r.console) else { return }
        if let p = RetroArch.problem(c, rom: r.path) { message = p; return }
        let ra = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == RetroArch.app.path }
        if let ra { if isRunning(g) { ra.activate() } else { message = "RetroArch is already open. Quit it first, then play \(g.name)." }; return }
        let o = NSWorkspace.OpenConfiguration(); o.arguments = RetroArch.arguments(core: RetroArch.core(c)!, rom: r.path)
        NSWorkspace.shared.openApplication(at: RetroArch.app, configuration: o) { a, e in
            DispatchQueue.main.async { if let e { self.message = e.localizedDescription } else if let a { self.tracker.adopt(a, as: g.titleID.uppercased()) } }
        }
    }

    func shown(_ s: Section, by: SortBy = .name) -> [Game] { library.show(games, in: s, search: search, by: by) }
    func count(_ s: Section) -> Int { games.reduce(0) { $0 + (library.has($1, s) ? 1 : 0) } }
    func edit(_ g: Game, _ c: (inout Entry) -> Void) { library.edit(g.titleID, c) }
    func isRunning(_ g: Game) -> Bool { runningIDs.contains(g.titleID.uppercased()) }
    func newCollection(_ name: String, adding g: Game?) { if let n = library.addCollection(name), let g { edit(g) { if !$0.collections.contains(n) { $0.collections.append(n) } } } }
    func removeCollection(_ c: String) { if section == .collection(c) { section = .home }; library.removeCollection(c) }
    func renameCollection(_ o: String, _ n: String) { let was = section; library.renameCollection(o, n); if was == .collection(o) { section = library.collections.contains(o) ? was : .home } }
    func wash(_ g: Game) -> NSImage {
        if let w = washes[g.id] { return w }
        // Shrunk to a few spots of colour, then grown in steps, which smooths it without a blur filter.
        let src = icon(g)
        func draw(_ from: NSImage, _ size: NSSize, _ part: NSRect = .zero) -> NSImage {
            let o = NSImage(size: size); o.lockFocus(); NSGraphicsContext.current?.imageInterpolation = .high
            from.draw(in: NSRect(origin: .zero, size: size), from: part, operation: .copy, fraction: 1); o.unlockFocus(); return o
        }
        var w = draw(src, NSSize(width: 6, height: 3), NSRect(x: src.size.width * 0.18, y: src.size.height * 0.3, width: src.size.width * 0.64, height: src.size.height * 0.4))
        for k in [18, 54, 160, 480] as [CGFloat] { w = draw(w, NSSize(width: k, height: k / 2)) }
        washes[g.id] = w; return w
    }
    private func trackPlay() {
        tracker.identify = { [weak self] u in self?.games.first { u.path == $0.url.path || u.path.hasPrefix($0.url.path + "/") }?.titleID.uppercased() }
        tracker.countedUntil = { [weak self] id in self?.library.entry(id).lastPlayed }
        AppDelegate.leaving = { [weak self] in self?.tracker.flush() }
        tracker.finished = { [weak self] id, a, b in self?.library.played(id, from: a, to: b) }
        tracker.changed = { [weak self] in guard let s = self else { return }; s.runningIDs = s.tracker.running }
        tracker.start()
    }

    let builder = Builder()
    var ready: Bool { !checks.isEmpty && checks.allSatisfy(\.ok) }

    init() {
        AppDelegate.builder = builder
        AppDelegate.moving = { [weak self] in self?.moving != nil }
        builder.onFinish = { [weak self] in self?.finished() }
        reload(); trackPlay(); recheck(first: true)
    }

    // Folders games have been saved to, besides Dockside's own, so the library still shows them.
    private var folders: [String] {
        get { UserDefaults.standard.stringArray(forKey: "gameFolders") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "gameFolders") }
    }
    @Published var destination = UserDefaults.standard.string(forKey: "destination").map { URL(fileURLWithPath: $0) } ?? Paths.games {
        didSet { UserDefaults.standard.set(destination.path, forKey: "destination") }
    }
    @Published var reviewPlace = Paths.games   // where the game on the review screen will go
    private var buildPlace = Paths.games
    @Published var moving: String?
    @Published var quick = UserDefaults.standard.bool(forKey: "skipPipeline") { didSet { UserDefaults.standard.set(quick, forKey: "skipPipeline") } }
    @Published var converting = false   // kept apart from the builder, whose every progress report would redraw the library
    var arrivingIcon: NSImage? { builder.titleID.flatMap { id in games.first { $0.titleID.uppercased() == id } }.map { icon($0) } }
    @Published var offer: Game?   // just finished: its original files can go
    private var icons: [String: NSImage] = [:]

    func icon(_ g: Game) -> NSImage {
        if let i = icons[g.id] { return i }
        if let r = g.rom { let i = romIcon(r); icons[g.id] = i; return i }
        let has = FileManager.default.fileExists(atPath: g.url.appendingPathComponent("Contents/Resources/AppIcon.icns").path)
        let i = has ? NSWorkspace.shared.icon(forFile: g.url.path) : plainIcon(); icons[g.id] = i; return i
    }

    // A game's box art, cropped to a tile, or its console's colour and name
    private func romIcon(_ r: Rom) -> NSImage {
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
    private func plainIcon() -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.addPath(CGPath(roundedRect: CGRect(x: 25, y: 25, width: 206, height: 206), cornerWidth: 47, cornerHeight: 47, transform: nil)); c.setFillColor(CGColor(srgbRed: 0.12, green: 0.37, blue: 0.42, alpha: 1)); c.fillPath()
            c.addPath(DPad().path(in: CGRect(x: 80, y: 80, width: 96, height: 96)).cgPath); c.setFillColor(CGColor(srgbRed: 0.88, green: 0.95, blue: 0.96, alpha: 1)); c.fillPath(); return true
        }
    }

    // Where each game's files came from: title ID -> files.
    private var sources: [String: [SourceFile]] {
        get { UserDefaults.standard.data(forKey: "sources").flatMap { try? JSONDecoder().decode([String: [SourceFile]].self, from: $0) } ?? [:] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "sources") }
    }
    private var buildSources: [SourceFile] = []

    func originals(_ g: Game) -> Originals { findOriginals(links: keptFiles(g.titleID), sources: sources[g.titleID.uppercased()] ?? []) }

    func offerTrash(_ g: Game) {
        guard !builder.running, moving == nil else { message = "Wait until Docked has finished its current job."; return }
        let o = originals(g)
        guard !o.isEmpty else { message = "Docked has no original files for \(g.name)."; return }
        let a = NSAlert(), size = ByteCountFormatter.string(fromByteCount: o.bytes, countStyle: .file)
        a.messageText = "Move \(g.name)'s original files to the Trash?"
        let names = (o.files.isEmpty ? o.links : o.files).map { "• " + $0.lastPathComponent }.joined(separator: "\n")
        a.informativeText = names + "\n\n\(size). Open the game first and check that it works. To convert it again, or add an update, you'd need these files back."
            + (o.files.isEmpty ? "\n\nDocked only knows its own links to these files. If you have them somewhere else too, space is freed once you remove those." : "\n\nThe space is freed when you empty the Trash.")
        a.addButton(withTitle: "Keep Files"); a.addButton(withTitle: "Move to Trash")
        guard a.runModal() == .alertSecondButtonReturn else { return }
        let failed = trashOriginals(o)
        if failed.isEmpty { var s = sources; s[g.titleID.uppercased()] = nil; sources = s }
        else { message = "These couldn't be moved to the Trash and were left alone: " + failed.map(\.lastPathComponent).joined(separator: ", ") }
        if offer?.id == g.id { offer = nil }
    }

    func reload() {
        var seen = Set<String>()
        games = ([Paths.games] + folders.map { URL(fileURLWithPath: $0) }).flatMap { scanLibrary($0) }.filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        games += library.roms.map { Game(url: URL(fileURLWithPath: $0.path), name: $0.name, titleID: $0.id, rom: $0) }
        library.meet(games)
    }

    private func finished() {
        icons = [:]; converting = false
        defer { if builder.stage == "Done", let id = builder.titleID { offerLater(id) } }
        if builder.stage == "Done", let app = builder.output, buildPlace.path != Paths.games.path { move(app, to: buildPlace) } else { reload() }
    }

    private func offerLater(_ id: String) {
        if !buildSources.isEmpty { var s = sources; s[id] = buildSources; sources = s }
        offer = games.first { $0.titleID.uppercased() == id }
    }

    // Off the main thread: another disk means a long copy.
    private func move(_ app: URL, to dir: URL) {
        moving = app.deletingPathExtension().lastPathComponent
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try placeGame(app, in: dir) }
            DispatchQueue.main.async {
                self.moving = nil; self.icons = [:]
                switch result {
                case .success: if dir.path != Paths.games.path, !self.folders.contains(dir.path) { self.folders.append(dir.path) }
                case .failure(let e): self.message = "\(app.deletingPathExtension().lastPathComponent) stayed in \(app.deletingLastPathComponent().lastPathComponent). \(e.localizedDescription)"
                }
                self.reload()
                if let o = self.offer { self.offer = self.games.first { $0.titleID == o.titleID } }
                else if let id = self.builder.titleID, self.builder.stage == "Done" { self.offer = self.games.first { $0.titleID.uppercased() == id } }
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
        guard !builder.running, moving == nil else { message = "Wait until Docked has finished its current job."; return }
        if let u = pickFolder(g.url.deletingLastPathComponent()) { move(g.url, to: u) }
    }

    // A game already converted is replaced where it is; a new one goes where the last one was saved.
    private func setReviewPlace() {
        let own = existing.map { $0.url.deletingLastPathComponent() } ?? destination
        reviewPlace = placeProblem(own) == nil ? own : Paths.games
    }

    func recheck(first: Bool = false) {
        checking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let c = runChecks()
            DispatchQueue.main.async { self.checks = c; self.checking = false; if first, !self.ready, cannotConvert() == nil { self.showSetup = true } }
        }
    }

    @Published var installing = false
    @Published var installProblem: String?

    func install() {
        guard let p = bundledPayload, !installing, !builder.running else { return }
        installing = true; installProblem = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try installTools(p, sha: bundledPayloadSHA) }
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
        guard ready else { showSetup = true; return }
        let good = urls.filter { u in
            var d: ObjCBool = false
            return fm.fileExists(atPath: u.path, isDirectory: &d) && (d.boolValue || packageTypes.contains(u.pathExtension.lowercased()) || u.pathExtension.lowercased() == "nup")
        }
        review.add(good)
        if good.count < urls.count { showReview ? (reviewNote = InputError.unsupported.errorDescription) : (message = InputError.unsupported.errorDescription) }
        if !good.isEmpty { if !showReview { setReviewPlace() }; showReview = true }
    }

    // A game that is already converted: start from the files it was made from, then add to them.
    func addTo(_ g: Game) {
        guard ready else { showSetup = true; return }
        review = Review(parts: []); review.add(keptFiles(g.titleID))
        reviewNote = review.parts.isEmpty ? "Docked doesn't have \(g.name)'s original files. Add them again, together with the update or DLC." : nil
        setReviewPlace(); showReview = true
    }

    var existing: Game? { review.family.flatMap { f in games.first { $0.titleID.uppercased() == f } } }

    func convert() -> Bool {
        guard !builder.running, moving == nil, review.blocker == nil else { return false }
        if let e = placeProblem(reviewPlace), reviewPlace.path != Paths.games.path { reviewNote = e.localizedDescription; return false }
        if let g = existing, isOpen(g) {
            reviewNote = "Save and quit \(g.name) first."; return false
        }
        do {
            let input = try resolveInput(review.parts.map(\.url), family: review.family)
            let free = freeSpace(), need = spaceNeeded(input.bytes)
            guard free >= need else {
                let f = ByteCountFormatter()
                reviewNote = "Not enough disk space. This game needs about \(f.string(fromByteCount: need)) while converting and you have \(f.string(fromByteCount: free))."; return false
            }
            if input.needsKeys, findKeys(keys) == nil, !pickKeys() { return false }
            buildPlace = reviewPlace; if existing == nil { destination = reviewPlace }
            let kept = Set(review.family.map { keptFiles($0).map(\.path) } ?? [])
            let before = review.family.flatMap { sources[$0] } ?? []
            let now = review.parts.filter { !kept.contains($0.url.path) && packageTypes.union(["nup"]).contains($0.url.pathExtension.lowercased()) }.map { SourceFile(path: $0.url.path, size: $0.bytes) }
            buildSources = before.filter { b in !now.contains { $0.path == b.path } } + now
            offer = nil
            builder.start(input, keys: findKeys(keys), quick: quick); converting = builder.running; review.parts = []; return true
        } catch { reviewNote = error.localizedDescription; return false }
    }

    func play(_ g: Game, settings: Bool = false) {
        if let r = g.rom { playRom(g, r); return }
        if isRunning(g), let a = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == g.url.path }) { a.activate(); return }
        if let why = g.cannot { message = "\(g.name) cannot run here. \(why)."; return }
        let c = NSWorkspace.OpenConfiguration()
        if !settings { c.environment = ["DM_LAUNCHER": "0"] }   // straight into the game
        NSWorkspace.shared.openApplication(at: g.url, configuration: c) { _, e in
            if let e { DispatchQueue.main.async { self.message = e.localizedDescription } }
        }
    }

    func trash(_ u: URL) {
        do { try FileManager.default.trashItem(at: u, resultingItemURL: nil) } catch { message = error.localizedDescription }
        reload()
    }

    func cleanLeftovers() {
        let fm = FileManager.default
        let dirs = ((try? fm.contentsOfDirectory(at: Paths.games, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasSuffix("_build") }
        guard moving == nil else { message = "Wait until Docked has finished its current job."; return }
        guard !dirs.isEmpty else { message = "There is nothing to clean up."; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let size = ByteCountFormatter().string(fromByteCount: dirs.reduce(0) { $0 + folderSize($1) })
            DispatchQueue.main.async { if !self.builder.running { self.askCleanUp(dirs, size) } }
        }
    }

    private func askCleanUp(_ dirs: [URL], _ size: String) {
        let a = NSAlert()
        a.messageText = "Move conversion leftovers to the Trash?"
        a.informativeText = "Up to \(size). Your games and saves stay. Converting one of these games again would take the full time."
        a.addButton(withTitle: "Move to Trash"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { dirs.forEach(trash) }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var builder: Builder
    @State private var dropping = false
    @State private var deleting: Game?
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            if model.games.isEmpty && !model.converting { empty } else { Shell(deleting: $deleting) }
            if let m = model.moving { Divider(); HStack { ProgressView().controlSize(.small); Text("Moving \(m)…"); Spacer() }.padding(16) }
            if let g = model.offer, !builder.running {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(g.name) is ready").font(.headline)
                        Text("Once you've checked it works, you can remove its original files to save space.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove Originals…") { model.offerTrash(g) }
                    Button("Keep Them") { model.offer = nil }
                }.padding(16)
            }
            if builder.running || builder.error != nil { Divider(); BuildBar() }
        }
        .background(Backdrop())
        .preferredColorScheme(style.alwaysDark ? .dark : nil)
        .overlay { if dropping && !model.games.isEmpty { RoundedRectangle(cornerRadius: 12).strokeBorder(style.accent, lineWidth: 3).padding(6).allowsHitTesting(false) } }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { loadDropped($0) { model.add($0) }; return true }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search games")
        .alert("New Collection", isPresented: .init(get: { model.collecting != nil }, set: { if !$0 { model.collecting = nil } })) { TextField("Name", text: $newName); Button("Create") { model.newCollection(newName, adding: model.collecting); newName = "" }; Button("Cancel", role: .cancel) { newName = "" } }
        .alert("Rename Collection", isPresented: .init(get: { model.renaming != nil }, set: { if !$0 { model.renaming = nil } })) { TextField("Name", text: $newName); Button("Rename") { if let o = model.renaming { model.renameCollection(o, newName) }; newName = "" }; Button("Cancel", role: .cancel) { newName = "" } }
        .toolbar {
            Button { model.pickGame() } label: { Label("Add Game", systemImage: "plus") }
            Menu {
                Button("How to Use…") { model.showHelp = true }
                Button("Consoles…") { model.showConsoles = true }
                Button("Setup…") { model.recheck(); model.showSetup = true }
                Button(model.keys == nil ? "Choose prod.keys…" : "Change prod.keys…") { _ = model.pickKeys() }
                Button("Show Games in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.games]) }
                Divider()
                Button("Clean Up Leftovers…") { model.cleanLeftovers() }.disabled(builder.running)
            } label: { Label("Options", systemImage: "ellipsis.circle") }
        }
        .sheet(isPresented: $model.showSetup) { SetupView() }
        .sheet(isPresented: $model.showConsoles) { ConsolesView() }
        .confirmationDialog("Which console is \(model.asking?.files.first.map { cleanName($0) } ?? "this")\((model.asking?.files.count ?? 1) > 1 ? " and the others" : "") for?", isPresented: .init(get: { model.asking != nil }, set: { if !$0 { model.asking = nil } })) { ForEach(model.asking?.choices ?? []) { c in Button(c.name) { model.answer(c) } } }
        .alert("Rename Game", isPresented: .init(get: { model.retitling != nil }, set: { if !$0 { model.retitling = nil } })) { TextField("Name", text: $newName); Button("Rename") { if let g = model.retitling { model.retitle(g, newName) }; newName = "" }; Button("Cancel", role: .cancel) { newName = "" } }
        .sheet(isPresented: $model.showHelp) { HelpView() }
        .sheet(isPresented: $model.showReview) { ReviewView() }
        .alert("Docked", isPresented: .init(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("OK") {} } message: { Text(model.message ?? "") }
        .confirmationDialog("Move \(deleting?.name ?? "") to the Trash?", isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { g in
            Button("Move to Trash", role: .destructive) { model.trash(g.url) }
        } message: { _ in Text("Your saved progress is kept.") }
    }

    var empty: some View {
        VStack(spacing: 14) {
            DPad().fill(style.accent).frame(width: 46, height: 46).accessibilityHidden(true)
            Text("Drop a game here").font(.title.weight(.semibold)).foregroundStyle(style.text)
            Text(cannotConvert() ?? "Switch games are converted to run natively, which takes 10 to 60 minutes.\nGames for other consoles are ready to play right away.")
                .multilineTextAlignment(.center).lineSpacing(3).foregroundStyle(style.soft)
            Button("Add Game…") { model.pickGame() }.controlSize(.large).buttonStyle(.borderedProminent).tint(style.button).padding(.top, 4)
            Button("How to Use Docked") { model.showHelp = true }.buttonStyle(.plain).foregroundStyle(style.accent)
            if !model.checks.isEmpty && !model.ready && cannotConvert() == nil { Button("Finish setup first") { model.showSetup = true }.buttonStyle(.plain).foregroundStyle(style.accent) }
        }
        .padding(36).frame(maxWidth: 520)
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(dropping ? style.accent : style.line, style: StrokeStyle(lineWidth: dropping ? 2.5 : 1.5, dash: [7, 6])) }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BuildBar: View {
    @EnvironmentObject var builder: Builder
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(builder.title).font(.headline).foregroundStyle(style.text)
                    Text(status).font(.callout).foregroundStyle(builder.error == nil ? style.soft : Color(light: 0xB3261E, dark: 0xFF8A80)).lineLimit(4).textSelection(.enabled)
                    if builder.tested == false { Text("Nobody has tested this game yet, so it may not start.").font(.caption).foregroundStyle(Color(light: 0x8A4B00, dark: 0xF2B45C)) }
                }
                Spacer()
                Button(showLog ? "Hide Details" : "Details") { showLog.toggle() }
                if builder.running { Button("Stop") { builder.cancel() } } else { Button("Dismiss") { builder.error = nil } }
            }
            if builder.running {
                TimelineView(.periodic(from: .now, by: 15)) { t in
                    HStack {
                        if let left = timeLeftText(builder.remaining(t.date), step: builder.stage, pipelineToCome: builder.pipelineToCome) { Text(left) }
                        Spacer()
                        Text(elapsedText(t.date.timeIntervalSince(builder.started))).foregroundStyle(.secondary)
                    }.font(.callout)
                }
                Group { if let f = builder.frac { ProgressView(value: min(max(f, 0), 1)) } else { ProgressView().progressViewStyle(.linear) } }.tint(style.accent)
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
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Consoles").font(.title2.weight(.semibold))
            Text(RetroArch.installed ? "Switch games run natively. The others play in RetroArch, with its own settings and saves." : "Switch games run natively. The others need RetroArch in your Applications folder.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(consoles) { c in
                        let ok = c.native || RetroArch.core(c) != nil
                        HStack {
                            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? Color(light: 0x1E7A3C, dark: 0x6FCF8A) : Color.secondary).accessibilityLabel(ok ? "Ready" : "Not ready")
                            VStack(alignment: .leading, spacing: 1) { Text(c.name); Text(detail(c, ok)).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text((c.types + c.shared).prefix(5).map { "." + $0 }.joined(separator: " ")).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                        Divider()
                    }
                }
            }.frame(height: 330)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).tint(style.button) }
        }.padding(24).frame(width: 520).background(AllowQuit()).background(Backdrop())
    }
    func detail(_ c: Console, _ ok: Bool) -> String {
        if c.native { return "Native" }
        return (ok ? "Ready" : "In RetroArch, download the \(c.cores[0].label) core") + (c.needs.isEmpty ? "" : ". Needs \(c.needs)")
    }
}

extension View { @ViewBuilder func fromBottom() -> some View { if #available(macOS 14, *) { defaultScrollAnchor(.bottom) } else { self } } }

struct SetupView: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Setup").font(.title2.weight(.semibold))
            Text("These are needed once. Where there's a command, copy it, paste it into Terminal and press Return.").foregroundStyle(.secondary)
            ForEach(model.checks) { c in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: c.ok ? "checkmark.circle.fill" : "circle").foregroundStyle(c.ok ? Color(light: 0x1E7A3C, dark: 0x6FCF8A) : Color.secondary)
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
            if let p = model.installProblem { Label(p, systemImage: "exclamationmark.circle").foregroundStyle(Color(light: 0xB3261E, dark: 0xFF8A80)).font(.callout) }
            HStack {
                if model.checking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Check Again") { model.recheck() }.disabled(model.checking)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).tint(style.button)
            }
        }.padding(24).frame(width: 520).background(AllowQuit()).background(Backdrop())
    }
}

// macOS refuses to quit while a sheet is open unless the sheet's window allows it.
struct AllowQuit: NSViewRepresentable {
    final class V: NSView { override func viewDidMoveToWindow() { window?.preventsApplicationTerminationWhenModal = false } }
    func makeNSView(context: Context) -> V { V() }
    func updateNSView(_ v: V, context: Context) {}
}
