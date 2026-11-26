import Foundation

// How well each Switch game runs, from the community Game Compatibility List (heyflorin.github.io/nx-game-list), which gathers
// nxnative's game notes, NX2Apple's list and players' reports. Fetched at most once a day, only when looking things up online is allowed;
// nothing is sent but the request. Kept in Metadata/compat.json so it shows offline.
struct Compat: Equatable {
    let tier: String          // "Verified", "Plays on Mac", "Playable", "Partial", "Reported working", "Profile only", "Doesn't run yet"
    let fps: String
    let platforms: [String]
    let issues: Int           // open reports of problems
    let engine: String        // the sentence in the engine's notes the rating comes from

    enum Kind { case good, okay, poor, unknown }
    var kind: Kind {
        switch tier { case "Verified", "Plays on Mac", "Playable", "Reported working": return .good; case "Partial": return .okay; case "Doesn't run yet": return .poor; default: return .unknown }
    }
    // In the player's words
    var label: String {
        switch tier {
        case "Verified": return "Verified by players"
        case "Plays on Mac": return "Plays on Mac"
        case "Playable": return platforms.contains("Mac") ? "Playable" : "Playable on iPhone"
        case "Reported working": return "Reported working"
        case "Partial": return "Partly works"
        case "Doesn't run yet": return "Doesn't run yet"
        default: return "Not tested yet"
        }
    }

    static let source = URL(string: "https://raw.githubusercontent.com/heyflorin/nx-game-list/main/data/data.json")!
    static let page = URL(string: "https://heyflorin.github.io/nx-game-list/")!
    static var cache: URL { Paths.root.appendingPathComponent("Metadata/compat.json") }

    static func parse(_ d: Data) -> [String: Compat] {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let games = o["games"] as? [[String: Any]] else { return [:] }
        var r: [String: Compat] = [:]
        for g in games {
            guard let id = g["id"] as? String, id.count == 16 else { continue }
            let open = (g["issues"] as? [[String: Any]])?.filter { ($0["open"] as? Bool) == true }.count ?? 0
            r[id.uppercased()] = Compat(tier: g["tier"] as? String ?? "", fps: g["fps"] as? String ?? "", platforms: g["platforms"] as? [String] ?? [], issues: open, engine: g["engine"] as? String ?? "")
        }
        return r
    }

    static func load() -> [String: Compat] { (try? Data(contentsOf: cache)).map(parse) ?? [:] }
    static var stale: Bool { ((try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < Date().addingTimeInterval(-86400) }

    // Calls back on the main queue with the fresh list, or nothing when it couldn't be fetched.
    static func refresh(_ done: @escaping ([String: Compat]) -> Void) {
        var q = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20); q.setValue("Docked", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: q) { d, r, _ in
            guard let d, (r as? HTTPURLResponse)?.statusCode == 200, d.count < 20_000_000 else { return }
            let list = parse(d); guard !list.isEmpty else { return }
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: cache, options: .atomic)
            DispatchQueue.main.async { done(list) }
        }.resume()
    }
}
