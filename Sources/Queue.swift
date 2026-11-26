import Foundation

// Games waiting to be converted, one after another. Kept in a file, so a restart or a crash loses nothing: the game that was converting goes back to the front and waits for the player.
enum After: String, Codable, CaseIterable {
    case ask, leftovers, everything
    var label: String { switch self { case .ask: return "Ask me"; case .leftovers: return "Remove conversion leftovers"; case .everything: return "Remove leftovers and original files" } }
}
struct Job: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String, family: String?, parts: [String], place: String, quick: Bool, after: After, bytes: Int64, needsKeys: Bool, sources: [SourceFile]
    var effort: Int = 100   // how much of the Mac this job may use; older queues keep full speed
    var target: Target? = nil
    var viaXcode: Bool? = nil   // for iPhone: a project for Xcode, not an .ipa file
    var again: Bool? = nil   // converted a second time, because the first did not pass Docked's check
    var phone: Bool { target == .phone }
    var xcode: Bool { phone && viaXcode == true }
    var urls: [URL] { parts.map { URL(fileURLWithPath: $0) } }

    enum CodingKeys: String, CodingKey { case id, title, family, parts, place, quick, after, bytes, needsKeys, sources, target, viaXcode, again, effort }
    init(id: UUID = UUID(), title: String, family: String? = nil, parts: [String], place: String, quick: Bool = false, after: After = .ask, bytes: Int64 = 0, needsKeys: Bool = false, sources: [SourceFile] = [], target: Target? = nil, viaXcode: Bool? = nil, again: Bool? = nil, effort: Int = 100) {
        self.id = id; self.title = title; self.family = family; self.parts = parts; self.place = place; self.quick = quick; self.after = after
        self.bytes = bytes; self.needsKeys = needsKeys; self.sources = sources; self.target = target; self.viaXcode = viaXcode; self.again = again; self.effort = effort
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        family = try c.decodeIfPresent(String.self, forKey: .family)
        parts = try c.decode([String].self, forKey: .parts)
        place = try c.decode(String.self, forKey: .place)
        quick = try c.decode(Bool.self, forKey: .quick)
        after = try c.decode(After.self, forKey: .after)
        bytes = try c.decode(Int64.self, forKey: .bytes)
        needsKeys = try c.decode(Bool.self, forKey: .needsKeys)
        sources = try c.decode([SourceFile].self, forKey: .sources)
        target = try c.decodeIfPresent(Target.self, forKey: .target)
        viaXcode = try c.decodeIfPresent(Bool.self, forKey: .viaXcode)
        again = try c.decodeIfPresent(Bool.self, forKey: .again)
        effort = try c.decodeIfPresent(Int.self, forKey: .effort) ?? 100   // queues saved before this setting keep full speed
    }
    var placeURL: URL { URL(fileURLWithPath: place) }
}
struct Problem: Codable, Equatable, Identifiable { var id = UUID(); var title: String, reason: String, report: String? = nil }

struct Queue: Codable, Equatable {
    var current: Job?, waiting: [Job] = [], problems: [Problem] = [], paused = false
    var all: [Job] { (current.map { [$0] } ?? []) + waiting }
    var isEmpty: Bool { current == nil && waiting.isEmpty && problems.isEmpty }

    // The same game twice would build in the same folder
    func holds(_ j: Job) -> Bool { all.contains { $0.phone == j.phone && $0.xcode == j.xcode && ($0.family != nil && $0.family == j.family || Set($0.parts) == Set(j.parts)) } }
    mutating func add(_ j: Job) -> Bool { if holds(j) { return false }; waiting.append(j); return true }
    mutating func remove(_ id: UUID) { waiting.removeAll { $0.id == id } }
    mutating func up(_ id: UUID) { if let i = waiting.firstIndex(where: { $0.id == id }), i > 0 { waiting.swapAt(i, i - 1) } }

    enum Verdict: Equatable { case go, wait, no(String) }
    // The first that can start now. One that can never start is set aside with its reason; one that has to wait lets others go first.
    mutating func next(_ check: (Job) -> Verdict) -> Job? {
        guard current == nil, !paused else { return nil }
        var i = 0
        while i < waiting.count {
            switch check(waiting[i]) {
            case .go: let j = waiting.remove(at: i); current = j; return j
            case .wait: i += 1
            case let .no(why): problems.append(Problem(title: waiting[i].title, reason: why)); waiting.remove(at: i)
            }
        }
        return nil
    }
    mutating func done() { current = nil }
    // A failure never stops the rest. With nothing waiting the window already shows it.
    mutating func failed(_ why: String, report: String? = nil) { if let c = current, !waiting.isEmpty { problems.append(Problem(title: c.title, reason: why, report: report)) }; current = nil }
    mutating func stopped() { current = nil; if !waiting.isEmpty { paused = true } }   // the player wants the Mac back

    static var file: URL { Paths.root.appendingPathComponent("queue.json") }
    static func load(_ u: URL = file) -> Queue {
        guard let d = try? Data(contentsOf: u), var q = try? JSONDecoder().decode(Queue.self, from: d) else { return Queue() }
        if let c = q.current { q.current = nil; q.waiting.insert(c, at: 0) }
        for i in q.waiting.indices { q.waiting[i].parts = q.waiting[i].parts.map { Paths.now($0) }; q.waiting[i].place = Paths.now(q.waiting[i].place); q.waiting[i].sources = q.waiting[i].sources.map { SourceFile(path: Paths.now($0.path), size: $0.size) } }
        if !q.waiting.isEmpty { q.paused = true } else { q.paused = false }   // never starts heavy work just because the app was opened
        return q
    }
    func save(_ u: URL = file) {
        if isEmpty { try? FileManager.default.removeItem(at: u); return }
        if let d = try? JSONEncoder().encode(self) { try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try? d.write(to: u, options: .atomic) }
    }
}
