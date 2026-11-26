import Foundation

// ---- Scores, popularity and details from Wikidata and Wikipedia ----
// Only when the player has said yes. Wikidata (public domain, CC0) is searched by the game's name for a video game of that
// name; its critic scores (Metacritic, OpenCritic and other aggregators), release year, genre, developer and publisher are kept.
// How many people read the game's English Wikipedia article each month (Wikimedia's open page-view counts) stands for how
// popular it is. Both see only the name. No account, no key.
struct Meta: Codable, Equatable {
    var critic: Int?        // 0 to 100
    var views: Int?         // Wikipedia readers a month, averaged over a year
    var year: Int?
    var genre: String?
    var developer: String?
    var publisher: String?
    var item: String?       // the Wikidata item, "Q1196943"; nil when nothing was found
    var checked = Date()
    var manual = false      // the player chose this item; later refreshes keep it

    enum CodingKeys: String, CodingKey { case critic, views, year, genre, developer, publisher, item, checked, manual }

    init(critic: Int? = nil, views: Int? = nil, year: Int? = nil, genre: String? = nil, developer: String? = nil, publisher: String? = nil, item: String? = nil, checked: Date = Date(), manual: Bool = false) {
        self.critic = critic; self.views = views; self.year = year; self.genre = genre
        self.developer = developer; self.publisher = publisher; self.item = item
        self.checked = checked; self.manual = manual
    }

    // Details saved by an earlier version have no "manual" field, and must still open.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        critic = try c.decodeIfPresent(Int.self, forKey: .critic)
        views = try c.decodeIfPresent(Int.self, forKey: .views)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        developer = try c.decodeIfPresent(String.self, forKey: .developer)
        publisher = try c.decodeIfPresent(String.self, forKey: .publisher)
        item = try c.decodeIfPresent(String.self, forKey: .item)
        checked = (try? c.decode(Date.self, forKey: .checked)) ?? Date()
        manual = try c.decodeIfPresent(Bool.self, forKey: .manual) ?? false
    }
}

enum MetaLookup {
    static var wikidata = "https://www.wikidata.org/w/api.php"
    static var pageviews = "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user"
    static let queue = DispatchQueue(label: "meta", qos: .utility)   // one game at a time, to be kind to Wikimedia
    static let interactive = DispatchQueue(label: "meta.picker", qos: .userInitiated)   // a player waiting on a sheet doesn't sit behind a sleeping background job
    static var failed: Date?                                         // touched only on the background queue
    static var pause: TimeInterval = 2                               // between games: Wikidata turns quick askers away for half a minute
    static let videoGame = "Q7889"
    static let aggregators = ["Q150248", "Q21039459", "Q131917281", "Q117190337"]   // Metacritic, OpenCritic, CriticDB, Kritikanstvo, in that order
    static let fresh: TimeInterval = 30 * 86400                      // looked up again after a month, for new scores and readers

    enum Refresh: Equatable { case none, automatic, manual(String) }
    // What a refresh should do, kept apart from the network so the rules can be tested.
    static func refresh(_ m: Meta?, force: Bool, now: Date = Date()) -> Refresh {
        guard let m else { return .automatic }
        if !force, now.timeIntervalSince(m.checked) < fresh { return .none }
        if m.manual, let item = m.item { return .manual(item) }
        return .automatic
    }

    static func q(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: Lookup.safe.subtracting(CharacterSet(charactersIn: "+"))) ?? "" }
    static func json(_ u: String) -> [String: Any]? { URL(string: u).flatMap { try? Lookup.get($0, limit: 4 << 20) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }

    // One line in the player's "Edit Metadata" search: the item ID, its name and what Wikidata says it is.
    struct Choice: Identifiable, Equatable { var id: String { item }; var item: String, name: String, detail: String? }

    // nil is "couldn't reach Wikidata"; an empty list is "nothing by that name".
    static func search(_ text: String) -> [Choice]? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let s = json("\(wikidata)?action=wbsearchentities&search=\(q(name))&language=en&type=item&limit=12&format=json") else { return nil }
        return choices(s)
    }

    static func choices(_ j: [String: Any]) -> [Choice] {
        (j["search"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = r["id"] as? String, id.hasPrefix("Q") else { return nil }
            let name = (r["label"] as? String) ?? (r["title"] as? String) ?? id
            let detail = (r["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Choice(item: id, name: name, detail: detail?.isEmpty == true ? nil : detail)
        }
    }

    // Everything for one game. nil only when Wikidata couldn't be reached; a game it doesn't know gets an empty Meta, so it isn't asked again for a month.
    static func find(_ name: String, now: Date = Date()) -> Meta? {
        let title = cleanTitle(name)
        guard let s = json("\(wikidata)?action=wbsearchentities&search=\(q(title))&language=en&type=item&limit=7&format=json") else { return nil }
        let ids = searchIDs(s); guard !ids.isEmpty else { return Meta(checked: now) }
        guard let e = json("\(wikidata)?action=wbgetentities&ids=\(ids.joined(separator: "|"))&props=claims|sitelinks|labels|aliases&languages=en|mul&sitefilter=enwiki&format=json") else { return nil }
        guard let pick = choose(e, ids: ids, name: title) else { return Meta(checked: now) }
        return fill(pick, now: now)
    }

    // The item the player picked: no name guessing, just its own scores and details.
    static func details(_ id: String, now: Date = Date()) -> Meta? {
        guard let e = json("\(wikidata)?action=wbgetentities&ids=\(q(id))&props=claims|sitelinks|labels|aliases&languages=en|mul&sitefilter=enwiki&format=json"), let pick = pick(e, id: id) else { return nil }
        return fill(pick, now: now)
    }

    // ---- reading the answers (kept apart from the network, for the tests) ----
    static func searchIDs(_ j: [String: Any]) -> [String] { (j["search"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.filter { $0.hasPrefix("Q") } }

    struct Pick { var meta: Meta; var article: String?; var genre: [String], developer: [String], publisher: [String] }

    // The first video game in Wikidata's own order whose name, or one of its other names, is the game's name.
    static func choose(_ j: [String: Any], ids: [String], name: String) -> Pick? {
        let all = j["entities"] as? [String: Any] ?? [:], want = Lookup.titleKey(name)
        for id in ids {
            guard let e = all[id] as? [String: Any], let claims = e["claims"] as? [String: Any], items(claims, "P31").contains(videoGame) else { continue }
            let (names, _) = names(in: e)
            guard names.contains(where: { Lookup.titleKey($0) == want }) else { continue }
            return pick(j, id: id)
        }
        return nil
    }

    // Reading a chosen item doesn't insist on the type or the name: the player has already decided.
    static func pick(_ j: [String: Any], id: String) -> Pick? {
        guard let e = (j["entities"] as? [String: Any])?[id] as? [String: Any], let claims = e["claims"] as? [String: Any] else { return nil }
        let (_, article) = names(in: e)
        let years = statements(claims, "P577").compactMap { (($0["datavalue"] as? [String: Any])?["value"] as? [String: Any])?["time"] as? String }.compactMap { Int($0.dropFirst().prefix(4)) }
        let m = Meta(critic: critic(claims), year: years.min(), item: id)
        return Pick(meta: m, article: article, genre: items(claims, "P136"), developer: items(claims, "P178"), publisher: items(claims, "P123"))
    }

    static func names(in e: [String: Any]) -> ([String], String?) {
        var names = ["en", "mul"].compactMap { ((e["labels"] as? [String: Any])?[$0] as? [String: Any])?["value"] as? String }
        for l in ["en", "mul"] { names += ((e["aliases"] as? [String: Any])?[l] as? [[String: Any]] ?? []).compactMap { $0["value"] as? String } }
        let article = ((e["sitelinks"] as? [String: Any])?["enwiki"] as? [String: Any])?["title"] as? String
        if let a = article { names.append(a.replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression)) }
        return (names, article)
    }

    // Labels, readers and the finished details, shared by automatic lookup and a manual choice.
    static func fill(_ p: Pick, now: Date = Date()) -> Meta {
        var m = p.meta; m.checked = now
        let need = p.genre + p.developer + p.publisher
        if !need.isEmpty, let l = json("\(wikidata)?action=wbgetentities&ids=\(Array(Set(need)).prefix(50).joined(separator: "|"))&props=labels&languages=en|mul&format=json") {
            let n = labels(l)
            m.genre = p.genre.compactMap { n[$0] }.first.map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            m.developer = p.developer.compactMap { n[$0] }.first; m.publisher = p.publisher.compactMap { n[$0] }.first
        }
        if let t = p.article {
            let c = Calendar(identifier: .gregorian), end = c.date(byAdding: .month, value: -1, to: now)!, start = c.date(byAdding: .month, value: -12, to: now)!
            let f = DateFormatter(); f.dateFormat = "yyyyMM01"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
            if let v = json("\(pageviews)/\(q(t.replacingOccurrences(of: " ", with: "_")))/monthly/\(f.string(from: start))/\(f.string(from: end))") { m.views = monthly(v) }
        }
        return m
    }

    static func statements(_ claims: [String: Any], _ p: String) -> [[String: Any]] { (claims[p] as? [[String: Any]] ?? []).compactMap { $0["mainsnak"] as? [String: Any] } }
    static func items(_ claims: [String: Any], _ p: String) -> [String] { statements(claims, p).compactMap { (($0["datavalue"] as? [String: Any])?["value"] as? [String: Any])?["id"] as? String } }

    // An aggregator's score when there is one (the best of its platforms' scores), else the middle of three or more reviews.
    static func critic(_ claims: [String: Any]) -> Int? {
        var by: [String: [Int]] = [:], rest: [Int] = []
        for c in claims["P444"] as? [[String: Any]] ?? [] {
            guard let s = ((c["mainsnak"] as? [String: Any])?["datavalue"] as? [String: Any])?["value"] as? String, let n = score(s) else { continue }
            let who = ((c["qualifiers"] as? [String: Any])?["P447"] as? [[String: Any]] ?? []).compactMap { (($0["datavalue"] as? [String: Any])?["value"] as? [String: Any])?["id"] as? String }
            if let a = who.first(where: aggregators.contains) { by[a, default: []].append(n) } else { rest.append(n) }
        }
        for a in aggregators { if let l = by[a], let best = l.max() { return best } }
        guard rest.count >= 3 else { return nil }
        return rest.sorted()[rest.count / 2]
    }

    // "97/100", "9.5/10", "4/5", "87%", "87 %" → out of 100. Letter grades and anything odd are left out.
    static func score(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if t.hasSuffix("%"), let v = Double(t.dropLast().trimmingCharacters(in: .whitespaces)), (0...100).contains(v) { return Int(v.rounded()) }
        let p = t.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard p.count == 2, let a = Double(p[0]), let b = Double(p[1]), b > 0, a >= 0, a <= b else { return nil }
        return Int((a / b * 100).rounded())
    }

    static func labels(_ j: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (id, e) in j["entities"] as? [String: Any] ?? [:] { let l = (e as? [String: Any])?["labels"] as? [String: Any]; if let v = ((l?["en"] ?? l?["mul"]) as? [String: Any])?["value"] as? String { out[id] = v } }
        return out
    }

    static func monthly(_ j: [String: Any]) -> Int? {
        let v = (j["items"] as? [[String: Any]] ?? []).compactMap { ($0["views"] as? NSNumber)?.intValue }
        return v.isEmpty ? nil : v.reduce(0, +) / v.count
    }
}

func readersText(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.1fM readers a month", Double(n) / 1e6) : n >= 10_000 ? "\(n / 1000)K readers a month" : n >= 1000 ? String(format: "%.1fK readers a month", Double(n) / 1e3) : "\(n) readers a month"
}
