import Foundation

// docked:// links, for Shortcuts, Raycast, Alfred, a Stream Deck or a Dock folder:
//   docked://play?id=<title ID>   docked://play?name=<words in the game's name>   docked://resume   docked://couch   docked://health   docked://tv?w=&h=&fps=&couch=1 (from TV streaming)
//   docked://join?room=<room>&key=<password>&game=<name>   a friend's invite to a retro game online (Netplay.swift)
enum DockedLink: Equatable {
    case play(id: String?, name: String?), resume, couch, health, join(Invite), tv(TVRequest)
    static func parse(_ u: URL) -> DockedLink? {
        guard u.scheme?.lowercased() == "docked", let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
        let what = (c.host ?? c.path.split(separator: "/").first.map(String.init) ?? "").lowercased()
        func q(_ k: String) -> String? { c.queryItems?.first { $0.name.lowercased() == k }?.value?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        switch what {
        case "play": let id = q("id"), name = q("name"); return id == nil && name == nil ? nil : .play(id: id, name: name)
        case "resume": return .resume
        case "couch": return .couch
        case "health": return .health
        case "tv":   // from tv.sh, as a TV stream starts or ends (TVDisplay.swift)
            if q("end") != nil { return .tv(TVRequest(start: false)) }
            let n = { (k: String) in Int(q(k) ?? "") ?? 0 }
            var r = TVRequest(start: true, width: n("w"), height: n("h"), fps: n("fps") == 0 ? 60 : n("fps"))
            if let id = q("play") { guard id.count <= 64, id.allSatisfy({ $0.isLetter || $0.isNumber || "-_.".contains($0) }) else { return nil }; r.play = id }
            r.couch = q("couch") != nil
            return .tv(r)
        case "join": guard let r = q("room"), let k = q("key"), let g = q("game"), Invite.valid(r), k.configSafe, g.configClean, k.count <= 64 else { return nil }; return .join(Invite(room: r, key: k, game: g))
        default: return nil
        }
    }
    static func play(_ titleID: String) -> String { "docked://play?id=" + (titleID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? titleID) }
}
// An invite to play a retro game online: the room the host's RetroArch announces, its password, and the game, by name
struct Invite: Equatable {
    let room: String, key: String, game: String
    static func valid(_ room: String) -> Bool { room.hasPrefix("Docked-") && room.count <= 24 && room.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
    static func make(game: String, random: () -> UInt8 = { UInt8.random(in: 0...255) }) -> Invite {
        let a = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")
        func pick(_ n: Int) -> String { String((0..<n).map { _ in a[Int(random()) % a.count] }) }
        return Invite(room: "Docked-" + pick(6), key: pick(10), game: game)
    }
    var link: String {
        var c = URLComponents(); c.scheme = "docked"; c.host = "join"
        c.queryItems = [URLQueryItem(name: "room", value: room), URLQueryItem(name: "key", value: key), URLQueryItem(name: "game", value: game)]
        return c.string ?? ""
    }
}
private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

// The game a link means: its title ID, else the name that matches best (whole name, then the start of it, then words in it)
func gameFor(id: String?, name: String?, in games: [Game]) -> Game? {
    if let id { if let g = games.first(where: { $0.titleID.caseInsensitiveCompare(id) == .orderedSame }) { return g } }
    guard let name else { return nil }
    let want = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    let named = games.map { ($0, $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
    if let g = named.first(where: { $0.1 == want }) { return g.0 }
    if let g = named.filter({ $0.1.hasPrefix(want) }).min(by: { $0.1.count < $1.1.count }) { return g.0 }
    let words = want.split(separator: " ")
    return named.filter { n in words.allSatisfy { n.1.contains($0) } }.min(by: { $0.1.count < $1.1.count })?.0
}
