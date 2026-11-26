import Foundation

// What the player does with a game: kept by title ID, so it survives converting again and moving.
struct Entry: Codable, Equatable {
    var favorite = false
    var status = Status.none
    var collections: [String] = []
    var added = Date()
    var lastPlayed: Date?
    var seconds: Double = 0
    var rating = 0     // the player's own stars, 1 to 5; 0 is not rated
    var plays = 0      // how many times it has been played
    var kept = false   // Keep This Build: converting the game again won't replace the app that plays well
    var meta: Meta?    // critic score, popularity and details from Wikidata, once looked up
    var engine: String?   // the engine its build was made with (Library Health); unknown for games made before 1.11
    enum Status: String, Codable, CaseIterable { case none = "Not started", playing = "Playing", finished = "Finished", aside = "Set aside" }
    init(favorite: Bool = false, status: Status = .none, collections: [String] = [], added: Date = Date(), lastPlayed: Date? = nil, seconds: Double = 0, rating: Int = 0, plays: Int = 0, meta: Meta? = nil) {
        self.favorite = favorite; self.status = status; self.collections = collections; self.added = added; self.lastPlayed = lastPlayed; self.seconds = seconds; self.rating = rating; self.plays = plays; self.meta = meta
    }
    // A library saved by an earlier version lacks the newer fields, and must still open.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        status = (try? c.decodeIfPresent(Status.self, forKey: .status)) ?? Status.none
        collections = try c.decodeIfPresent([String].self, forKey: .collections) ?? []
        added = try c.decodeIfPresent(Date.self, forKey: .added) ?? .distantPast
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        rating = min(max(try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0, 0), 5)
        plays = try c.decodeIfPresent(Int.self, forKey: .plays) ?? 0
        meta = try? c.decodeIfPresent(Meta.self, forKey: .meta)
        kept = try c.decodeIfPresent(Bool.self, forKey: .kept) ?? false
        engine = try? c.decodeIfPresent(String.self, forKey: .engine)
    }
}

// The raw values are what is saved, so the older ones stay as they were.
enum SortBy: String, CaseIterable {
    case recent = "Recently Played", name = "Name", added = "Recently Added", played = "Most Played", rating = "Rating", critic = "Critic Score", popular = "Popularity", plays = "Times Played", year = "Release Year"
    var title: String { self == .played ? "Hours Played" : rawValue }
}

// Breaking a long list into labelled runs, so a big console reads like shelves, not one wall of games.
enum GroupBy: String, CaseIterable {
    case auto = "Automatic", none = "None", letter = "Letter", console = "Console", year = "Year", genre = "Genre", progress = "Progress"
    static let enough = 24   // shorter lists stay as one, as headers would only clutter them
}

enum Section: Hashable {
    case home, all, favorites, console(String), status(Entry.Status), collection(String), smart(SmartCollection)
    var title: String {
        switch self {
        case .home: return "Home"
        case .all: return "All Games"
        case .favorites: return "Favorites"
        case .console(let c): return consoleName(c)
        case .status(let s): return s.rawValue
        case .collection(let c): return c
        case .smart(let s): return s.name
        }
    }
    var machine: Console? { if case .console(let c) = self { return consoleFor(id: c) }; return nil }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .all: return "square.grid.2x2"
        case .favorites: return "heart"
        case .console: return "gamecontroller"
        case .status(.playing): return "play.circle"
        case .status(.finished): return "checkmark.circle"
        case .status(.aside): return "pause.circle"
        case .status: return "circle.dashed"
        case .collection: return "folder"
        case .smart: return "sparkle.magnifyingglass"
        }
    }
}

func consoleName(_ id: String) -> String { console(id)?.name ?? id }

struct LibraryData: Codable, Equatable {
    var entries: [String: Entry] = [:]
    var collections: [String] = []
    var roms: [Rom] = []
    var smart: [SmartCollection] = []
    var apps: [String: String] = [:]   // every converted game's place, to its title ID, so one that goes missing stays in the library
    var removed: [String] = []         // games taken out of the library by hand, which a watched folder must not bring back
    var offloaded: [String: String] = [:]   // a game's place on this Mac, to where it was offloaded (a cloud folder or a drive), while it is away

    init() {}
    // A library saved by an earlier version has no emulated games yet.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        entries = try c.decode([String: Entry].self, forKey: .entries)
        collections = try c.decodeIfPresent([String].self, forKey: .collections) ?? []
        roms = try c.decodeIfPresent([Rom].self, forKey: .roms) ?? []
        smart = (try? c.decodeIfPresent([SmartCollection].self, forKey: .smart)) ?? []
        apps = (try? c.decodeIfPresent([String: String].self, forKey: .apps)) ?? [:]
        removed = (try? c.decodeIfPresent([String].self, forKey: .removed)) ?? []
        offloaded = (try? c.decodeIfPresent([String: String].self, forKey: .offloaded)) ?? [:]
    }

    // The same game again, or moved, updates where it is.
    mutating func addRom(_ r: Rom) {
        removed.removeAll { $0 == r.path }
        if let i = roms.firstIndex(where: { $0.id == r.id }) { roms[i].path = r.path } else { roms.append(r) }
    }
    mutating func removeRom(_ id: String) { for r in roms where r.id == id { forget(r.path) }; roms.removeAll { $0.id == id } }
    mutating func addApp(_ path: String, _ titleID: String) { removed.removeAll { $0 == path }; apps[path] = titleID.uppercased() }
    mutating func removeApp(_ path: String) { if apps.removeValue(forKey: path) != nil { forget(path) } }
    private mutating func forget(_ path: String) { offloaded[path] = nil; if !removed.contains(path) { removed.append(path); if removed.count > 5000 { removed.removeFirst(removed.count - 5000) } } }

    // The converted games found now, and the ones known before that can't be found. One found somewhere else has moved, and its old place is dropped.
    mutating func settle(found: [Game], exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Game] {
        for g in found { apps[g.url.path] = g.titleID.uppercased() }
        let here = Set(found.map { $0.titleID.uppercased() }), paths = Set(found.map(\.url.path))
        var gone: [Game] = []
        for (p, id) in apps where !paths.contains(p) {
            if exists(p) { continue }   // read again next time
            if here.contains(id) { apps[p] = nil; continue }
            gone.append(Game(url: URL(fileURLWithPath: p), name: URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent, titleID: id, needs: gameMinimum, missing: true))
        }
        return gone.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func entry(_ id: String) -> Entry { entries[id.uppercased()] ?? Entry(added: .distantPast) }

    mutating func edit(_ id: String, _ change: (inout Entry) -> Void) { var e = entries[id.uppercased()] ?? Entry(); change(&e); entries[id.uppercased()] = e }

    // New games get a date; games that are gone keep their history, in case they come back.
    mutating func meet(_ games: [Game], now: Date = Date()) { for g in games where entries[g.titleID.uppercased()] == nil { entries[g.titleID.uppercased()] = Entry(added: now) } }

    mutating func played(_ id: String, from: Date, to: Date) {
        edit(id) { e in
            e.lastPlayed = max(e.lastPlayed ?? .distantPast, to)
            let t = to.timeIntervalSince(from)
            if t > 0, t < 7 * 24 * 3600 { e.seconds += t; e.plays += 1 }
            if t > 300, e.status == .none { e.status = .playing }   // five minutes in, it has been started
        }
    }

    mutating func addCollection(_ name: String) -> String? {
        let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !n.isEmpty else { return nil }
        if let same = collections.first(where: { $0.localizedCaseInsensitiveCompare(n) == .orderedSame }) { return same }
        collections.append(n); collections.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }; return n
    }

    mutating func removeCollection(_ name: String) { collections.removeAll { $0 == name }; for k in entries.keys { entries[k]?.collections.removeAll { $0 == name } } }

    mutating func renameCollection(_ old: String, _ new: String) {
        guard let i = collections.firstIndex(of: old) else { return }
        let n = String(new.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !n.isEmpty, !collections.contains(where: { $0 != old && $0.localizedCaseInsensitiveCompare(n) == .orderedSame }) else { return }
        collections[i] = n; collections.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        for k in entries.keys { if let j = entries[k]?.collections.firstIndex(of: old) { entries[k]?.collections[j] = n } }
    }

    // A name already taken is refused; saving an existing one replaces it
    mutating func keepSmart(_ s: SmartCollection) -> Bool {
        var s = s; s.name = String(s.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)); guard !s.name.isEmpty, !s.empty, smart.count < 50, !smart.contains(where: { $0.id != s.id && $0.name.localizedCaseInsensitiveCompare(s.name) == .orderedSame }) else { return false }
        if let i = smart.firstIndex(where: { $0.id == s.id }) { smart[i] = s } else { smart.append(s) }; smart.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }; return true
    }

    func has(_ g: Game, _ s: Section) -> Bool {
        let e = entry(g.titleID)
        switch s {
        case .home, .all: return true
        case .favorites: return e.favorite
        case .console(let c): return consoleOf(g.titleID) == c
        case .status(let x): return e.status == x
        case .collection(let c): return e.collections.contains(c)
        case .smart(let s): return s.holds(g, e)
        }
    }

    func show(_ games: [Game], in s: Section, search: String = "", by: SortBy = .name) -> [Game] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let byName: (Game, Game) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return games.filter { has($0, s) && (q.isEmpty || $0.name.localizedCaseInsensitiveContains(q)) }.sorted { a, b in
            let x = entry(a.titleID), y = entry(b.titleID)
            switch by {
            case .name: return byName(a, b)
            case .recent: let p = x.lastPlayed ?? .distantPast, r = y.lastPlayed ?? .distantPast; return p == r ? byName(a, b) : p > r
            case .added: return x.added == y.added ? byName(a, b) : x.added > y.added
            case .played: return x.seconds == y.seconds ? byName(a, b) : x.seconds > y.seconds
            case .rating: return x.rating == y.rating ? byName(a, b) : x.rating > y.rating
            case .plays: return x.plays == y.plays ? (x.seconds == y.seconds ? byName(a, b) : x.seconds > y.seconds) : x.plays > y.plays
            case .critic: let p = x.meta?.critic ?? -1, r = y.meta?.critic ?? -1; return p == r ? byName(a, b) : p > r
            case .popular: let p = x.meta?.views ?? -1, r = y.meta?.views ?? -1; return p == r ? byName(a, b) : p > r
            case .year: let p = year(a) ?? 0, r = year(b) ?? 0; return p == r ? byName(a, b) : (p == 0 || r == 0) ? p != 0 : p > r   // newest first, unknown last
            }
        }
    }

    // A game's year: its game list's, else Wikidata's
    func year(_ g: Game) -> Int? { g.rom?.info?.year ?? entry(g.titleID).meta?.year }

    // What "Automatic" groups by: whatever the list is sorted by, when that makes clear runs.
    func grouping(_ g: GroupBy, sort: SortBy, count: Int) -> GroupBy {
        guard g == .auto else { return g }
        guard count >= GroupBy.enough else { return .none }
        switch sort { case .name: return .letter; case .year: return .year; case .recent, .added, .rating, .critic: return .auto; case .played, .plays, .popular: return .none }
    }

    // An already sorted list, cut into runs in the order they come; each run keeps the sort. Runs of a kind that has no order of its own (console, genre) are put in name order.
    func groups(_ list: [Game], by g: GroupBy, sort: SortBy, now: Date = Date(), calendar cal: Calendar = .current) -> [(title: String, games: [Game])] {
        let g = grouping(g, sort: sort, count: list.count)
        if g == .none { return [("", list)] }
        func when(_ d: Date?, never: String) -> String {
            guard let d, d > .distantPast else { return never }
            if cal.isDate(d, inSameDayAs: now) { return "Today" }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day ?? 0
            return days < 7 ? "This Week" : days < 31 ? "This Month" : days < 365 ? "This Year" : "Earlier"
        }
        func key(_ x: Game) -> String {
            let e = entry(x.titleID)
            switch g {
            case .letter: let f = x.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first.map { String($0).uppercased() } ?? "#"; return f.first?.isLetter == true ? f : "#"
            case .console: return consoleName(consoleOf(x.titleID))
            case .year: return year(x).map(String.init) ?? "Year Unknown"
            case .genre: return (x.rom?.info?.genre ?? e.meta?.genre).map { $0.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? $0 } ?? "Genre Unknown"
            case .progress: return e.status.rawValue
            case .auto:   // by the sort itself
                switch sort {
                case .recent: return when(e.lastPlayed, never: "Not Played Yet")
                case .added: return when(e.added, never: "Earlier")
                case .rating: return e.rating == 0 ? "Not Rated" : String(repeating: "★", count: e.rating)
                case .critic: guard let c = e.meta?.critic else { return "No Score" }; return c >= 90 ? "90 and Up" : c >= 80 ? "80 to 89" : c >= 70 ? "70 to 79" : "Under 70"
                default: return ""
                }
            case .none: return ""
            }
        }
        var order: [String] = [], runs: [String: [Game]] = [:]
        for x in list { let k = key(x); if runs[k] == nil { order.append(k) }; runs[k, default: []].append(x) }
        // Runs come in their own order, whatever the list is sorted by; the unknown ones last.
        let unknown: Set<String> = ["Genre Unknown", "Year Unknown"], steps: [Entry.Status] = [.playing, .none, .aside, .finished]
        switch g {
        case .letter: order.sort { ($0 == "#" ? 0 : 1, $0) < ($1 == "#" ? 0 : 1, $1) }
        case .year: order.sort { unknown.contains($0) != unknown.contains($1) ? unknown.contains($1) : $0 > $1 }
        case .console, .genre: order.sort { unknown.contains($0) != unknown.contains($1) ? unknown.contains($1) : $0.localizedStandardCompare($1) == .orderedAscending }
        case .progress: order.sort { a, b in (steps.firstIndex { $0.rawValue == a } ?? 9) < (steps.firstIndex { $0.rawValue == b } ?? 9) }
        default: break
        }
        return order.map { ($0, runs[$0]!) }
    }

    // ---- on disk: written whole beside the old one, then swapped; a damaged file is set aside, never overwritten ----
    static var file: URL { Paths.root.appendingPathComponent("library.json") }
    static func load(_ url: URL = file) -> LibraryData {
        guard let d = try? Data(contentsOf: url) else { return LibraryData() }
        let j = JSONDecoder(); j.dateDecodingStrategy = .iso8601
        if let l = try? j.decode(LibraryData.self, from: d) { return l }
        try? FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("library-damaged-\(Int(Date().timeIntervalSince1970)).json"))
        return LibraryData()
    }
    func save(_ url: URL = file) {
        let j = JSONEncoder(); j.dateEncodingStrategy = .iso8601; j.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? j.encode(self) { try? d.write(to: url, options: .atomic) }
    }
}

// What the library reads from disk: the folders' games, and whether each known file is there. Gathered off the main thread when it can be,
// as a drive that is asleep can take seconds to answer. A path not looked at is asked about directly.
struct DiskLook {
    var apps: [Game] = []
    var known = Set<String>(), there = Set<String>()
    func exists(_ p: String) -> Bool { known.contains(p) ? there.contains(p) : FileManager.default.fileExists(atPath: p) }
    static func take(dirs: [URL], apps: [String], removed: Set<String>, roms: [String], offloaded: [String], ids: DriveIDs = .shared) -> DiskLook {
        let fm = FileManager.default
        var d = DiskLook(), seen = Set<String>()
        func look(_ p: String) -> Bool { if d.known.insert(p).inserted, fm.fileExists(atPath: p) { d.there.insert(p) }; return d.there.contains(p) }
        for g in dirs.flatMap(libraryFolders).flatMap({ scanLibrary($0) }) where seen.insert(g.id).inserted && !removed.contains(g.url.path) { d.apps.append(g) }
        for p in apps where !seen.contains(p) {   // known games outside the folders, read once each
            if let g = gameAt(URL(fileURLWithPath: p)) { seen.insert(g.id); if !removed.contains(p) { d.apps.append(g) } }
        }
        for g in d.apps { d.known.insert(g.url.path); d.there.insert(g.url.path) }
        for p in apps + roms + offloaded where !look(p) { _ = look((p as NSString).deletingLastPathComponent) }   // a missing file's folder says whether it was deleted
        ids.remember(d.apps.map(\.url.path) + roms.filter { d.there.contains($0) })
        return d
    }
}

func playTimeText(_ s: Double) -> String { s < 60 ? "Not played yet" : s < 3600 ? "\(Int(s / 60)) min played" : String(format: "%.1f hours played", s / 3600) }
func lastPlayedText(_ d: Date?, now: Date = Date(), calendar c: Calendar = .current) -> String {
    guard let d else { return "Never played" }
    let days = c.dateComponents([.day], from: c.startOfDay(for: d), to: c.startOfDay(for: now)).day ?? 0
    switch days { case ..<1: return "Played today"; case 1: return "Played yesterday"; case 2..<7: return "Played \(days) days ago"; case 7..<14: return "Played last week"; default: return "Played " + d.formatted(.dateTime.day().month(.abbreviated).year()) }
}
