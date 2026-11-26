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
}

enum MetaLookup {
    static var wikidata = "https://www.wikidata.org/w/api.php"
    static var pageviews = "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user"
    static let queue = DispatchQueue(label: "meta", qos: .utility)   // one game at a time, to be kind to Wikimedia
    static var failed: Date?                                         // touched only on the queue
    static var pause: TimeInterval = 2                               // between games: Wikidata turns quick askers away for half a minute
    static let videoGame = "Q7889"
    static let aggregators = ["Q150248", "Q21039459", "Q131917281", "Q117190337"]   // Metacritic, OpenCritic, CriticDB, Kritikanstvo, in that order
    static let fresh: TimeInterval = 30 * 86400                      // looked up again after a month, for new scores and readers

    static func q(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: Lookup.safe.subtracting(CharacterSet(charactersIn: "+"))) ?? "" }
    static func json(_ u: String) -> [String: Any]? { URL(string: u).flatMap { try? Lookup.get($0, limit: 4 << 20) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }

    // Everything for one game. nil only when Wikidata couldn't be reached; a game it doesn't know gets an empty Meta, so it isn't asked again for a month.
    static func find(_ name: String, now: Date = Date()) -> Meta? {
        let title = cleanTitle(name)
        guard let s = json("\(wikidata)?action=wbsearchentities&search=\(q(title))&language=en&type=item&limit=7&format=json") else { return nil }
        let ids = searchIDs(s); guard !ids.isEmpty else { return Meta(checked: now) }
        guard let e = json("\(wikidata)?action=wbgetentities&ids=\(ids.joined(separator: "|"))&props=claims|sitelinks|labels|aliases&languages=en|mul&sitefilter=enwiki&format=json") else { return nil }
        guard let pick = choose(e, ids: ids, name: title) else { return Meta(checked: now) }
        var m = pick.meta; m.checked = now
        let need = pick.genre + pick.developer + pick.publisher
        if !need.isEmpty, let l = json("\(wikidata)?action=wbgetentities&ids=\(Array(Set(need)).prefix(50).joined(separator: "|"))&props=labels&languages=en|mul&format=json") {
            let n = labels(l)
            m.genre = pick.genre.compactMap { n[$0] }.first.map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            m.developer = pick.developer.compactMap { n[$0] }.first; m.publisher = pick.publisher.compactMap { n[$0] }.first
        }
        if let t = pick.article {
            let c = Calendar(identifier: .gregorian), end = c.date(byAdding: .month, value: -1, to: now)!, start = c.date(byAdding: .month, value: -12, to: now)!
            let f = DateFormatter(); f.dateFormat = "yyyyMM01"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
            if let v = json("\(pageviews)/\(q(t.replacingOccurrences(of: " ", with: "_")))/monthly/\(f.string(from: start))/\(f.string(from: end))") { m.views = monthly(v) }
        }
        return m
    }

    // ---- reading the answers (kept apart from the network, for the tests) ----
    static func searchIDs(_ j: [String: Any]) -> [String] { (j["search"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.filter { $0.hasPrefix("Q") } }

    struct Pick { var meta: Meta; var article: String?; var genre: [String], developer: [String], publisher: [String] }

    // The first video game in Wikidata's own order whose name, or one of its other names, is the game's name.
    static func choose(_ j: [String: Any], ids: [String], name: String) -> Pick? {
        let all = j["entities"] as? [String: Any] ?? [:], want = Lookup.titleKey(name)
        for id in ids {
            guard let e = all[id] as? [String: Any], let claims = e["claims"] as? [String: Any], items(claims, "P31").contains(videoGame) else { continue }
            var names = ["en", "mul"].compactMap { ((e["labels"] as? [String: Any])?[$0] as? [String: Any])?["value"] as? String }
            for l in ["en", "mul"] { names += ((e["aliases"] as? [String: Any])?[l] as? [[String: Any]] ?? []).compactMap { $0["value"] as? String } }
            let article = ((e["sitelinks"] as? [String: Any])?["enwiki"] as? [String: Any])?["title"] as? String
            if let a = article { names.append(a.replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression)) }
            guard names.contains(where: { Lookup.titleKey($0) == want }) else { continue }
            let years = statements(claims, "P577").compactMap { (($0["datavalue"] as? [String: Any])?["value"] as? [String: Any])?["time"] as? String }.compactMap { Int($0.dropFirst().prefix(4)) }
            let m = Meta(critic: critic(claims), year: years.min(), item: id)
            return Pick(meta: m, article: article, genre: items(claims, "P136"), developer: items(claims, "P178"), publisher: items(claims, "P123"))
        }
        return nil
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
