import SwiftUI

// RetroAchievements, where people can see it: a badge on retro game tiles, the full set on each game's page,
// and a page of its own in the sidebar. Everything comes from the player's Web API key, is fetched off the
// main thread, and is kept on disk, so pages open at once and only refresh now and then.

final class CheevoStore: ObservableObject {
    static let shared = CheevoStore()
    @Published var page = false                       // the Achievements page is showing
    @Published private(set) var sets: [Int: CheevoSet] = [:]
    @Published private(set) var account: CheevoAccount?
    @Published private(set) var catalog: [String: CheevoListing] = [:]   // console id + matched title, every game with a set
    @Published private(set) var busy: Set<Int> = []
    @Published var problem: String?
    private var catalogDates: [String: Date] = [:]
    private var working = false

    static var dir: URL { RetroArch.support.appendingPathComponent("Achievements") }
    static var badges: URL { dir.appendingPathComponent("Badges") }
    private static let images = NSCache<NSString, NSImage>()

    init() {
        let d = Self.dir
        account = try? JSONDecoder.ra.decode(CheevoAccount.self, from: Data(contentsOf: d.appendingPathComponent("account.json")))
        catalog = (try? JSONDecoder().decode([String: CheevoListing].self, from: Data(contentsOf: d.appendingPathComponent("catalog.json")))) ?? [:]
        catalogDates = (try? JSONDecoder.ra.decode([String: Date].self, from: Data(contentsOf: d.appendingPathComponent("catalog-dates.json")))) ?? [:]
    }

    // Signed in with a Web API key. Asked of the Keychain at most every few seconds, not on every redraw.
    private var readyAt = Date.distantPast, readyNow = false
    var ready: Bool {
        if Date().timeIntervalSince(readyAt) > 3 { readyNow = Cheevos.signedIn && Cheevos.hasWebKey; readyAt = Date() }
        return readyNow
    }
    func recheck() { readyAt = .distantPast; objectWillChange.send() }
    // Signed out: nothing of the account stays on this Mac
    func forget() { try? FileManager.default.removeItem(at: Self.dir); sets = [:]; account = nil; problem = nil; page = false; recheck() }

    // RetroAchievements' game number for a retro game in the library, whether or not it has been played
    func gameID(_ r: Rom) -> Int? {
        if let id = Cheevos.of(r)?.id { return id }
        return listing(r)?.id
    }
    func listing(_ r: Rom) -> CheevoListing? {
        guard let cid = Cheevos.consoleIDs[r.console] else { return nil }
        for n in [r.info?.name, r.name].compactMap({ $0 }) { if let l = catalog["\(cid):\(Cheevos.key(n))"] { return l } }
        return nil
    }
    // Known to have no set: its console's list has been fetched and the game isn't on it
    func noSet(_ r: Rom) -> Bool {
        guard let cid = Cheevos.consoleIDs[r.console] else { return true }
        return catalogDates["\(cid)"] != nil && gameID(r) == nil
    }

    // Progress, the account and the lists of games with sets, each at most as often as it changes.
    // Called when the sidebar, a game page or the Achievements page appears; cheap when nothing is due.
    func warm(_ model: Model, force: Bool = false) {
        guard ready, !working else { return }
        let consoles = Set(model.library.roms.compactMap { Cheevos.consoleIDs[$0.console] })
        let progressDue = force || Date().timeIntervalSince(Cheevos.checked) > 300
        let accountDue = force || account.map { Date().timeIntervalSince($0.fetched) > 300 } ?? true
        let listsDue = consoles.filter { c in catalogDates["\(c)"].map { Date().timeIntervalSince($0) > 7 * 86400 } ?? true }
        guard progressDue || accountDue || !listsDue.isEmpty else { return }
        working = true
        let known = catalog, dates = catalogDates
        DispatchQueue.global(qos: .utility).async {
            var failure: String?
            if progressDue { do { try Cheevos.refresh() } catch { failure = error.localizedDescription } }
            let acct: CheevoAccount? = accountDue ? (try? Self.fetchAccount()) : nil
            var cat = known, when = dates
            for c in listsDue { if let l = try? Self.fetchList(console: c) { cat = cat.filter { !$0.key.hasPrefix("\(c):") }.merging(l) { a, _ in a }; when["\(c)"] = Date() } }
            if !listsDue.isEmpty { Self.write(cat, "catalog.json"); Self.write(when, "catalog-dates.json") }
            if let acct { Self.write(acct, "account.json") }
            DispatchQueue.main.async {
                self.working = false
                if let acct { self.account = acct }
                self.catalog = cat; self.catalogDates = when
                self.problem = failure
                model.objectWillChange.send()   // tiles read the progress
            }
        }
    }

    // One game's full set with the player's unlocks. Fetched again when the player's count has moved on.
    func load(_ id: Int, earned: Int?) {
        guard ready, !busy.contains(id) else { return }
        if let s = sets[id] ?? Self.read(id) {
            if sets[id] == nil { sets[id] = s }
            if (earned == nil || s.earned.count == earned) && Date().timeIntervalSince(s.fetched) < 600 { return }
        }
        busy.insert(id)
        DispatchQueue.global(qos: .utility).async {
            let r = Result { try Self.fetchSet(id) }
            DispatchQueue.main.async {
                self.busy.remove(id)
                switch r { case .success(let s): self.sets[id] = s; Self.write(s, "Games/\(id).json"); case .failure(let e): if self.sets[id] == nil { self.problem = e.localizedDescription } }
            }
        }
    }

    // ---- the Web API ----
    private static func fetchSet(_ id: Int) throws -> CheevoSet {
        guard let j = try Cheevos.api("API_GetGameInfoAndUserProgress", ["g": "\(id)"]) as? [String: Any] else { throw RetroError("RetroAchievements sent an answer Docked couldn't read.") }
        let all = (j["Achievements"] as? [String: [String: Any]]).map { Array($0.values) } ?? []
        let list = all.compactMap { a -> Cheevo? in
            guard let n = Cheevos.int(a["ID"]), let t = a["Title"] as? String else { return nil }
            let hc = (a["DateEarnedHardcore"] as? String).flatMap(raDate), sc = (a["DateEarned"] as? String).flatMap(raDate)
            return Cheevo(id: n, title: t, about: a["Description"] as? String ?? "", badge: a["BadgeName"] as? String ?? "", points: Cheevos.int(a["Points"]) ?? 0, order: Cheevos.int(a["DisplayOrder"]) ?? 0, earned: hc ?? sc, hardcore: hc != nil)
        }
        return CheevoSet(id: id, title: j["Title"] as? String ?? "", list: list, fetched: Date())
    }
    private static func fetchAccount() throws -> CheevoAccount {
        guard let p = try Cheevos.api("API_GetUserProfile", [:]) as? [String: Any] else { throw RetroError("RetroAchievements sent an answer Docked couldn't read.") }
        let recent = (try? Cheevos.api("API_GetUserRecentAchievements", ["m": "\(30 * 24 * 60)"]) as? [[String: Any]]) ?? []
        let unlocks = recent.compactMap { a -> CheevoUnlock? in
            guard let n = Cheevos.int(a["AchievementID"]), let t = a["Title"] as? String, let d = (a["Date"] as? String).flatMap(raDate) else { return nil }
            return CheevoUnlock(id: n, title: t, about: a["Description"] as? String ?? "", badge: a["BadgeName"] as? String ?? "", game: a["GameTitle"] as? String ?? "", gameID: Cheevos.int(a["GameID"]) ?? 0, points: Cheevos.int(a["Points"]) ?? 0, date: d, hardcore: Cheevos.int(a["HardcoreMode"]) == 1)
        }.sorted { $0.date > $1.date }
        return CheevoAccount(user: p["User"] as? String ?? Cheevos.user ?? "", pic: p["UserPic"] as? String, since: p["MemberSince"] as? String, presence: (p["RichPresenceMsg"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                             hardcore: Cheevos.int(p["TotalPoints"]) ?? 0, softcore: Cheevos.int(p["TotalSoftcorePoints"]) ?? 0, retro: Cheevos.int(p["TotalTruePoints"]) ?? 0, recent: Array(unlocks.prefix(50)), fetched: Date())
    }
    private static func fetchList(console c: Int) throws -> [String: CheevoListing] {
        guard let l = try Cheevos.api("API_GetGameList", ["i": "\(c)", "f": "1"]) as? [[String: Any]] else { throw RetroError("RetroAchievements sent an answer Docked couldn't read.") }
        var m: [String: CheevoListing] = [:]
        for g in l {
            guard let t = g["Title"] as? String, !t.hasPrefix("~"), let id = Cheevos.int(g["ID"]), let n = Cheevos.int(g["NumAchievements"]), n > 0 else { continue }
            let k = "\(c):\(Cheevos.key(t))"; if m[k] == nil { m[k] = CheevoListing(id: id, count: n, points: Cheevos.int(g["Points"]) ?? 0) }
        }
        return m
    }

    // ---- on disk ----
    private static func write<T: Encodable>(_ v: T, _ name: String) {
        let u = dir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder.ra.encode(v) { try? d.write(to: u, options: .atomic) }
    }
    private static func read(_ id: Int) -> CheevoSet? { try? JSONDecoder.ra.decode(CheevoSet.self, from: Data(contentsOf: dir.appendingPathComponent("Games/\(id).json"))) }

    // Badges: small PNGs, downloaded once and kept
    static func badge(_ name: String, _ done: @escaping (NSImage?) -> Void) {
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return done(nil) }
        if let i = images.object(forKey: name as NSString) { return done(i) }
        DispatchQueue.global(qos: .utility).async {
            let file = badges.appendingPathComponent(name + ".png")
            var data = try? Data(contentsOf: file)
            if data == nil, let d = try? Data(contentsOf: URL(string: "https://media.retroachievements.org/Badge/\(name).png")!), d.count < 2 << 20, NSImage(data: d) != nil {
                try? FileManager.default.createDirectory(at: badges, withIntermediateDirectories: true); try? d.write(to: file, options: .atomic); data = d
            }
            let i = data.flatMap(NSImage.init(data:))
            if let i { images.setObject(i, forKey: name as NSString) }
            DispatchQueue.main.async { done(i) }
        }
    }
    static func picture(_ path: String?, _ done: @escaping (NSImage?) -> Void) {
        guard let path, path.hasPrefix("/"), let u = URL(string: "https://media.retroachievements.org" + path) else { return done(nil) }
        if let i = images.object(forKey: path as NSString) { return done(i) }
        DispatchQueue.global(qos: .utility).async {
            let i = (try? Data(contentsOf: u)).flatMap(NSImage.init(data:))
            if let i { images.setObject(i, forKey: path as NSString) }
            DispatchQueue.main.async { done(i) }
        }
    }
}

// ---- small pieces ----

struct BadgeImage: View {
    let name: String
    var locked = false
    var size: CGFloat = 36
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.medium) }
            else { RoundedRectangle(cornerRadius: 6).fill(style.line.opacity(0.5)) }
        }
        .frame(width: size, height: size).saturation(locked ? 0 : 1).opacity(locked ? 0.38 : 1)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        .overlay { if locked { Image(systemName: "lock.fill").font(.system(size: size * 0.3, weight: .semibold)).foregroundStyle(style.text.opacity(0.8)) } }
        .onAppear { if image == nil { CheevoStore.badge(name) { image = $0 } } }
        .accessibilityHidden(true)
    }
}

// A ring that fills as a set is completed, gold once it is all done
struct CheevoRing: View {
    let earned: Int, total: Int
    var size: CGFloat = 54
    var body: some View {
        let f = total > 0 ? Double(earned) / Double(total) : 0, done = total > 0 && earned >= total
        ZStack {
            Circle().stroke(style.line, lineWidth: size * 0.11)
            Circle().trim(from: 0, to: f).stroke(done ? style.accent : style.accent.opacity(0.85), style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round)).rotationEffect(.degrees(-90))
            if done { Image(systemName: "crown.fill").font(.system(size: size * 0.3)).foregroundStyle(style.accent) }
            else { Text("\(Int((f * 100).rounded(.down)))%").font(.system(size: size * 0.24, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(style.text) }
        }.frame(width: size, height: size).accessibilityElement().accessibilityLabel(done ? "Mastered" : "\(Int(f * 100)) percent")
    }
}

// On a retro game's tile, once anything is unlocked: a trophy and the count, or a crown when the set is done
struct CheevoPill: View {
    let p: Cheevos.Progress
    var body: some View {
        let done = p.earned >= p.total
        HStack(spacing: 4) {
            Image(systemName: done ? "crown.fill" : "trophy.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(style.accent)
            Text(done ? "Mastered" : "\(p.earned)/\(p.total)").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
        }
        .padding(.horizontal, 7).frame(height: 20).background(.black.opacity(0.62), in: Capsule())
        .overlay(Capsule().strokeBorder(style.accent.opacity(done ? 0.9 : 0.35), lineWidth: 1))
        .help(done ? "Every achievement unlocked" : "\(p.earned) of \(p.total) achievements unlocked")
        .accessibilityElement().accessibilityLabel(done ? "All achievements unlocked" : "\(p.earned) of \(p.total) achievements")
    }
}

// One achievement in a grid; a click shows what it asks and when it was unlocked
struct CheevoBadge: View {
    let c: Cheevo
    var size: CGFloat = 36
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: { BadgeImage(name: c.badge, locked: c.earned == nil, size: size).overlay(alignment: .bottomTrailing) { if c.hardcore { Circle().fill(style.accent).frame(width: 7, height: 7).overlay(Circle().stroke(style.bottom, lineWidth: 1.5)).offset(x: 2, y: 2) } } }
            .buttonStyle(.plain).help(c.title)
            .accessibilityLabel("\(c.title), \(c.points) points, \(c.earned == nil ? "locked" : "unlocked")")
            .popover(isPresented: $open, arrowEdge: .bottom) { CheevoDetail(title: c.title, about: c.about, badge: c.badge, points: c.points, date: c.earned, hardcore: c.hardcore, game: nil) }
    }
}

struct CheevoDetail: View {
    let title, about, badge: String
    let points: Int, date: Date?, hardcore: Bool, game: String?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BadgeImage(name: badge, locked: date == nil, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(style.text).fixedSize(horizontal: false, vertical: true)
                if let game { Text(game).font(.caption).foregroundStyle(style.soft) }
                Text(about).font(.callout).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("\(points) point\(points == 1 ? "" : "s")").font(.caption.weight(.semibold)).foregroundStyle(style.accent)
                    Text("·").foregroundStyle(style.soft)
                    Text(date.map { "Unlocked \($0.formatted(date: .abbreviated, time: .shortened))" + (hardcore ? ", hardcore" : "") } ?? "Not unlocked yet").font(.caption).foregroundStyle(style.soft)
                }.padding(.top, 2)
            }
        }.padding(14).frame(width: 320, alignment: .leading).background(style.top)
    }
}

// The two steps before anything can show: an account, then the Web API key. Said plainly, where people look.
struct CheevoSetup: View {
    @EnvironmentObject var model: Model
    @ObservedObject var store = CheevoStore.shared
    var roomy = false
    @State private var key = ""
    var body: some View {
        VStack(alignment: roomy ? .center : .leading, spacing: 9) {
            if !Cheevos.signedIn {
                Text("Earn achievements as you play, with a free RetroAchievements account.").font(.callout).foregroundStyle(style.text).multilineTextAlignment(roomy ? .center : .leading).fixedSize(horizontal: false, vertical: true)
                Button("Sign In…") { SettingsSheet.start = .retro; model.openSettings(); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SettingsSheet.start = .general } }.controlSize(roomy ? .large : .small)
            } else {
                Text("One step left: add your Web API key so Docked can show what you've unlocked.").font(.callout).foregroundStyle(style.text).multilineTextAlignment(roomy ? .center : .leading).fixedSize(horizontal: false, vertical: true)
                Text("It's under Keys on your RetroAchievements settings page.").font(.caption).foregroundStyle(style.soft).multilineTextAlignment(roomy ? .center : .leading)
                HStack(spacing: 6) {
                    SecureField("Web API key", text: $key).textFieldStyle(.roundedBorder).frame(maxWidth: roomy ? 240 : .infinity).onSubmit(save)
                    Button("Save", action: save).disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }.controlSize(roomy ? .regular : .small)
                Button("Find My Key") { NSWorkspace.shared.open(URL(string: "https://retroachievements.org/settings")!) }.buttonStyle(.plain).font(.caption).foregroundStyle(style.accent)
            }
        }
    }
    func save() { Cheevos.setWebKey(key); key = ""; store.problem = nil; model.objectWillChange.send(); store.warm(model, force: true) }
}

// ---- on a game's page ----
struct CheevoCard: View {
    @EnvironmentObject var model: Model
    @ObservedObject var store = CheevoStore.shared
    let rom: Rom
    @State private var all = false
    var body: some View {
        let p = Cheevos.of(rom), id = store.gameID(rom), set = id.flatMap { store.sets[$0] }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACHIEVEMENTS").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(style.soft).accessibilityAddTraits(.isHeader)
                Spacer()
                if let id, store.ready { Button { NSWorkspace.shared.open(URL(string: "https://retroachievements.org/game/\(id)")!) } label: { Image(systemName: "arrow.up.right.square").foregroundStyle(style.soft) }.buttonStyle(.plain).help("Open on RetroAchievements").accessibilityLabel("Open on RetroAchievements") }
            }
            if !store.ready { CheevoSetup() }
            else if let set, !set.list.isEmpty {
                let earned = set.earned.count, hc = set.list.filter(\.hardcore).count
                HStack(spacing: 12) {
                    CheevoRing(earned: earned, total: set.list.count)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(earned == set.list.count ? "Mastered" : earned == 0 ? "Nothing unlocked yet" : "\(earned) of \(set.list.count) unlocked").font(.callout.weight(.semibold)).foregroundStyle(style.text)
                        Text("\(set.earnedPoints) of \(set.points) points").font(.caption).monospacedDigit().foregroundStyle(style.soft)
                        if hc > 0 { Label(hc == earned ? "All hardcore" : "\(hc) hardcore", systemImage: "flame.fill").font(.caption).foregroundStyle(style.accent) }
                    }
                }
                let shown = all ? set.ordered : Array(set.ordered.prefix(18))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) { ForEach(shown) { CheevoBadge(c: $0, size: 34) } }
                if set.list.count > 18 { Button(all ? "Show Fewer" : "Show All \(set.list.count)") { all.toggle() }.buttonStyle(.plain).font(.caption).foregroundStyle(style.accent) }
                if let last = set.earned.first, let d = last.earned { Text("Last unlocked: \(last.title), \(d.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(style.soft).lineLimit(2) }
            }
            else if let id, store.busy.contains(id) || set == nil { HStack(spacing: 6) { ProgressView().controlSize(.small); Text(p.map { "\(Cheevos.text($0)) unlocked" } ?? "Loading achievements…").font(.callout).foregroundStyle(style.soft) } }
            else if store.noSet(rom) { Text("RetroAchievements has no set for this game yet, or knows it by another name.").font(.callout).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true) }
            else { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Looking for its achievements…").font(.callout).foregroundStyle(style.soft) } }
            if let e = store.problem, store.ready, set == nil { Text(e).font(.caption).foregroundStyle(style.warn).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(style.tile, in: RoundedRectangle(cornerRadius: 10))
        .onAppear { store.warm(model) }
        .task(id: "\(rom.id) \(id ?? 0) \(p?.earned ?? -1)") { if let id { store.load(id, earned: p?.earned) } }
    }
}

// ---- the sidebar row and the page ----
struct CheevoRow: View {
    @EnvironmentObject var model: Model
    @ObservedObject var store = CheevoStore.shared
    var body: some View {
        Button { model.selected = nil; store.page = true } label: {
            HStack(spacing: 9) {
                Image(systemName: "trophy").frame(width: 18).foregroundStyle(store.page ? style.accent : style.soft)
                Text("Achievements").foregroundStyle(style.text).lineLimit(1)
                Spacer()
                if let a = store.account, store.ready { Text("\(a.hardcore + a.softcore)").font(.caption).monospacedDigit().foregroundStyle(style.soft).help("Points") }
                else if !store.ready { Circle().fill(style.accent).frame(width: 6, height: 6).help("Finish setting up") }
            }.padding(.horizontal, 10).frame(height: 30).background { if store.page { RoundedRectangle(cornerRadius: 8).fill(style.tile) } }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(store.page ? .isSelected : [])
        .onAppear { store.warm(model) }
    }
}

struct Owned: Identifiable { let game: Game, p: Cheevos.Progress; var id: String { game.id } }

struct AchievementsPage: View {
    @EnvironmentObject var model: Model
    @ObservedObject var store = CheevoStore.shared
    @State private var pic: NSImage?
    var body: some View {
        let mine = model.games.compactMap { g -> Owned? in g.rom.flatMap { Cheevos.of($0) }.map { Owned(game: g, p: $0) } }
        let going = mine.filter { $0.p.earned > 0 && $0.p.earned < $0.p.total }.sorted { Double($0.p.earned) / Double($0.p.total) > Double($1.p.earned) / Double($1.p.total) }
        let mastered = mine.filter { $0.p.earned >= $0.p.total }.sorted { $0.game.name < $1.game.name }
        let fresh = model.games.filter { g in g.rom.map { r in Cheevos.of(r) == nil && store.listing(r) != nil } ?? false }.sorted { $0.name < $1.name }
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !store.ready {
                    VStack(spacing: 14) {
                        Image(systemName: "trophy.fill").font(.system(size: 44)).foregroundStyle(style.accent)
                        Text("Achievements").font(.title.weight(.semibold)).foregroundStyle(style.text)
                        CheevoSetup(roomy: true)
                    }.frame(maxWidth: 420).frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    header
                    if let e = store.problem { Label(e, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(style.warn) }
                    if !going.isEmpty { shelf("Keep going", going) }
                    if let a = store.account, !a.recent.isEmpty { recent(a.recent) }
                    if !mastered.isEmpty { shelf("Mastered", mastered) }
                    if !fresh.isEmpty {
                        section("Ready to start") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                                ForEach(fresh.prefix(24), id: \.id) { g in gameRow(g, sub: store.listing(g.rom!).map { "\($0.count) achievements · \($0.points) points" } ?? "", earned: 0, total: 1) }
                            }
                        }
                    }
                    if mine.isEmpty && fresh.isEmpty && (store.account?.recent.isEmpty ?? true) {
                        Text("Play a retro game to start unlocking. Achievements pop up while you play and show up here.").font(.callout).foregroundStyle(style.soft).frame(maxWidth: .infinity).padding(.top, 30)
                    }
                }
            }.padding(28).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity)
        }
        .onAppear { store.warm(model) }
    }

    var header: some View {
        let a = store.account, mastered = Cheevos.progress.values.filter { $0.earned >= $0.total }.count, started = Cheevos.progress.count
        return HStack(alignment: .center, spacing: 18) {
            Group { if let pic { Image(nsImage: pic).resizable() } else { ZStack { style.tile; Image(systemName: "person.fill").font(.system(size: 30)).foregroundStyle(style.soft) } } }
                .frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style.accent.opacity(0.6), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 4) {
                Text(a?.user ?? Cheevos.user ?? "").font(.title2.weight(.semibold)).foregroundStyle(style.text)
                if let p = a?.presence { Text(p).font(.callout).foregroundStyle(style.soft).lineLimit(1) }
                else if let s = a?.since, let d = raDate(s) ?? raDate(s + " 00:00:00") { Text("Member since \(d.formatted(.dateTime.month(.wide).year()))").font(.callout).foregroundStyle(style.soft) }
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                stat("\(a?.hardcore ?? 0)", "Hardcore points", "flame.fill")
                stat("\(a?.softcore ?? 0)", "Softcore points", "star.fill")
                stat("\(mastered)", mastered == 1 ? "Game mastered" : "Games mastered", "crown.fill")
                stat("\(started)", started == 1 ? "Game started" : "Games started", "gamecontroller.fill")
            }
            Button { store.warm(model, force: true) } label: { Image(systemName: "arrow.clockwise").foregroundStyle(style.soft) }.buttonStyle(.plain).help("Refresh").accessibilityLabel("Refresh achievements")
        }
        .padding(18).background(LinearGradient(colors: [style.tile, style.tile.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
        .task(id: a?.pic) { CheevoStore.picture(a?.pic) { pic = $0 } }
    }
    func stat(_ n: String, _ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: s).font(.system(size: 11)).foregroundStyle(style.accent)
            Text(n).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(style.text)
            Text(t).font(.caption).foregroundStyle(style.soft).lineLimit(1)
        }.padding(.horizontal, 12).padding(.vertical, 9).frame(minWidth: 104, alignment: .leading).background(style.bottom.opacity(0.55), in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .combine)
    }
    func section<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(t).font(.title3.weight(.semibold)).foregroundStyle(style.text).accessibilityAddTraits(.isHeader); c() }
    }
    func shelf(_ t: String, _ l: [Owned]) -> some View {
        section(t) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                ForEach(l) { o in gameRow(o.game, sub: Cheevos.text(o.p), earned: o.p.earned, total: o.p.total) }
            }
        }
    }
    func gameRow(_ g: Game, sub: String, earned: Int, total: Int) -> some View {
        Button { store.page = false; model.section = .all; model.select(g) } label: {
            HStack(spacing: 11) {
                Group { if let c = model.cover(g) { Image(nsImage: c).resizable().aspectRatio(contentMode: .fill) } else { ZStack { style.line; Image(systemName: "gamecontroller").foregroundStyle(style.soft) } } }
                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(g.name).font(.callout.weight(.medium)).foregroundStyle(style.text).lineLimit(1)
                    if earned > 0 {
                        GeometryReader { r in ZStack(alignment: .leading) { Capsule().fill(style.line); Capsule().fill(style.accent).frame(width: r.size.width * min(1, Double(earned) / Double(max(total, 1)))) } }.frame(height: 5)
                    }
                    Text(sub).font(.caption).monospacedDigit().foregroundStyle(style.soft).lineLimit(1)
                }
                Spacer(minLength: 0)
                if earned >= total && earned > 0 { Image(systemName: "crown.fill").foregroundStyle(style.accent) }
            }.padding(10).background(style.tile, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Show \(g.name)")
    }
    func recent(_ l: [CheevoUnlock]) -> some View {
        section("Recently unlocked") {
            VStack(spacing: 0) {
                ForEach(l.prefix(12)) { u in
                    if u.id != l.first?.id { Divider().overlay(style.line) }
                    UnlockRow(u: u)
                }
            }.padding(.horizontal, 12).background(style.tile, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct UnlockRow: View {
    let u: CheevoUnlock
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 12) {
                BadgeImage(name: u.badge, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(u.title).font(.callout.weight(.semibold)).foregroundStyle(style.text).lineLimit(1)
                    Text(u.game).font(.caption).foregroundStyle(style.soft).lineLimit(1)
                }
                Spacer(minLength: 8)
                if u.hardcore { Image(systemName: "flame.fill").font(.caption).foregroundStyle(style.accent).help("Hardcore") }
                Text("\(u.points)").font(.system(.callout, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(style.accent)
                Text(u.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(style.soft).frame(width: 96, alignment: .trailing)
            }.padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) { CheevoDetail(title: u.title, about: u.about, badge: u.badge, points: u.points, date: u.date, hardcore: u.hardcore, game: u.game) }
        .accessibilityLabel("\(u.title), \(u.game), \(u.points) points")
    }
}
