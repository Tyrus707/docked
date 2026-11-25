import Foundation

// What the player does with a game: kept by title ID, so it survives converting again and moving.
struct Entry: Codable, Equatable {
    var favorite = false
    var status = Status.none
    var collections: [String] = []
    var added = Date()
    var lastPlayed: Date?
    var seconds: Double = 0
    enum Status: String, Codable, CaseIterable { case none = "Not started", playing = "Playing", finished = "Finished", aside = "Set aside" }
}

enum SortBy: String, CaseIterable { case recent = "Recently Played", name = "Name", added = "Recently Added", played = "Most Played" }

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

    init() {}
    // A library saved by an earlier version has no emulated games yet.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        entries = try c.decode([String: Entry].self, forKey: .entries)
        collections = try c.decodeIfPresent([String].self, forKey: .collections) ?? []
        roms = try c.decodeIfPresent([Rom].self, forKey: .roms) ?? []
        smart = (try? c.decodeIfPresent([SmartCollection].self, forKey: .smart)) ?? []
    }

    // The same game again, or moved, updates where it is.
    mutating func addRom(_ r: Rom) {
        if let i = roms.firstIndex(where: { $0.id == r.id }) { roms[i].path = r.path } else { roms.append(r) }
    }
    mutating func removeRom(_ id: String) { roms.removeAll { $0.id == id } }

    func entry(_ id: String) -> Entry { entries[id.uppercased()] ?? Entry(added: .distantPast) }

    mutating func edit(_ id: String, _ change: (inout Entry) -> Void) { var e = entries[id.uppercased()] ?? Entry(); change(&e); entries[id.uppercased()] = e }

    // New games get a date; games that are gone keep their history, in case they come back.
    mutating func meet(_ games: [Game], now: Date = Date()) { for g in games where entries[g.titleID.uppercased()] == nil { entries[g.titleID.uppercased()] = Entry(added: now) } }

    mutating func played(_ id: String, from: Date, to: Date) {
        edit(id) { e in
            e.lastPlayed = max(e.lastPlayed ?? .distantPast, to)
            let t = to.timeIntervalSince(from)
            if t > 0, t < 7 * 24 * 3600 { e.seconds += t }
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
            }
        }
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

func playTimeText(_ s: Double) -> String { s < 60 ? "Not played yet" : s < 3600 ? "\(Int(s / 60)) min played" : String(format: "%.1f hours played", s / 3600) }
func lastPlayedText(_ d: Date?, now: Date = Date(), calendar c: Calendar = .current) -> String {
    guard let d else { return "Never played" }
    let days = c.dateComponents([.day], from: c.startOfDay(for: d), to: c.startOfDay(for: now)).day ?? 0
    switch days { case ..<1: return "Played today"; case 1: return "Played yesterday"; case 2..<7: return "Played \(days) days ago"; case 7..<14: return "Played last week"; default: return "Played " + d.formatted(.dateTime.day().month(.abbreviated).year()) }
}
