import Foundation

// docked:// links, for Shortcuts, Raycast, Alfred, a Stream Deck or a Dock folder:
//   docked://play?id=<title ID>   docked://play?name=<words in the game's name>   docked://resume   docked://couch   docked://health
enum DockedLink: Equatable {
    case play(id: String?, name: String?), resume, couch, health
    static func parse(_ u: URL) -> DockedLink? {
        guard u.scheme?.lowercased() == "docked", let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
        let what = (c.host ?? c.path.split(separator: "/").first.map(String.init) ?? "").lowercased()
        func q(_ k: String) -> String? { c.queryItems?.first { $0.name.lowercased() == k }?.value?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        switch what {
        case "play": let id = q("id"), name = q("name"); return id == nil && name == nil ? nil : .play(id: id, name: name)
        case "resume": return .resume
        case "couch": return .couch
        case "health": return .health
        default: return nil
        }
    }
    static func play(_ titleID: String) -> String { "docked://play?id=" + (titleID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? titleID) }
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
