import Foundation

// What a chosen file is, read from the title ID and version dump tools put in its name.
enum PartKind: String { case base = "Game", update = "Update", dlc = "DLC", unknown = "Not recognised from its name" }

struct Part: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var kind: PartKind
    var family: String?    // the base game's title ID
    var version: Int?
    let bytes: Int64       // measured once: a dump folder holds thousands of files

    // The name without its codes, so long DLC names stay tellable apart.
    var label: String {
        let n = packageTypes.contains(url.pathExtension.lowercased()) ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        let t = n.replacingOccurrences(of: "\\s*\\[[^\\]]*\\]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? n : t
    }

    init(_ url: URL) {
        self.url = url; bytes = folderSize(url)
        let name = url.lastPathComponent
        var tid: UInt64?
        if let r = name.range(of: "(?<![0-9A-Fa-f])0[0-9A-Fa-f]{15}(?![0-9A-Fa-f])", options: .regularExpression) { tid = UInt64(name[r], radix: 16) }
        if let r = name.range(of: "\\[v[0-9]+\\]", options: [.regularExpression, .caseInsensitive]) { version = Int(name[r].dropFirst(2).dropLast()) }
        kind = .unknown
        if let t = tid {
            let low = t & 0x1FFF
            kind = low == 0 ? .base : low == 0x800 ? .update : low >= 0x1000 ? .dlc : .unknown
            family = String(format: "%016llX", t & ~0x1FFF)
        }
    }
}

// The game versions the engine's profile was made and tested with: "v2228224" -> "3.0.3".
func testedVersions(_ titleID: String) -> [Int: String] {
    guard isTested(titleID), let s = try? String(contentsOf: Paths.engine.appendingPathComponent("dm/games/\(titleID.uppercased())/game.tsv"), encoding: .utf8) else { return [:] }
    var out: [Int: String] = [:]
    for line in s.split(separator: "\n") {
        let f = line.split(separator: "\t", omittingEmptySubsequences: false)
        if f.count >= 3, f[0] == "build", f[1].hasPrefix("v"), let v = Int(f[1].dropFirst()) { out[v] = String(f[2]) }
    }
    return out
}

struct Review: Equatable {
    var parts: [Part]
    var family: String? { let f = Set(parts.compactMap(\.family)); return f.count == 1 ? f.first : nil }

    // A reason it cannot be converted as it is, or nil.
    var blocker: String? {
        if parts.isEmpty { return "Add your game's files." }
        if Set(parts.compactMap(\.family)).count > 1 { return "These files belong to different games. Remove the ones that don't belong." }
        let single = parts.contains { !packageTypes.contains($0.url.pathExtension.lowercased()) }
        if single { return parts.count > 1 ? "A folder or .nup file is converted on its own. Remove the others." : nil }
        if !parts.contains(where: { $0.kind == .base || $0.kind == .unknown }) { return "The main game is missing. Add its file too." }
        return nil
    }

    // Worth knowing before a long conversion. (text, true = a warning)
    var notes: [(String, Bool)] {
        guard blocker == nil, let f = family else { return [] }
        var out: [(String, Bool)] = []
        let known = testedVersions(f)
        let mine = parts.filter { $0.kind == .base || $0.kind == .update }.compactMap(\.version).max()
        if !isTested(f) { out.append(("Nobody has tested this game yet, so it may not start.", true)) }
        else if let v = mine, !known.isEmpty {
            if let d = known[v] { out.append(("This is a tested version (\(d)).", false)) }
            else {
                let list = known.sorted { $0.key < $1.key }.map(\.value).joined(separator: ", ")
                let have = parts.contains { $0.kind == .update } ? "Your update is a different version" : "You've added no update"
                out.append(("Tested with version \(list). \(have), so it may not run well.", true))
            }
        }
        if !parts.contains(where: { $0.kind == .dlc }) { out.append(("No DLC added. That's fine if you don't have any.", false)) }
        return out
    }

    mutating func add(_ urls: [URL]) { for u in urls where !parts.contains(where: { $0.url.lastPathComponent == u.lastPathComponent }) { parts.append(Part(u)) }
        let order: [PartKind] = [.base, .update, .dlc, .unknown]
        parts.sort { (order.firstIndex(of: $0.kind)!, $0.url.lastPathComponent) < (order.firstIndex(of: $1.kind)!, $1.url.lastPathComponent) }
    }
}

// The files a game was converted from, which Dockside keeps links to, so an update or DLC can be added later.
func keptFiles(_ titleID: String, games: URL = Paths.games, inputs: URL = Paths.inputs) -> [URL] {
    let fm = FileManager.default, dir = inputs.appendingPathComponent(buildFolderKey(titleID, games: games))
    return ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
        .filter { packageTypes.contains($0.pathExtension.lowercased()) && fm.fileExists(atPath: $0.path) }
}

// One build folder per game, so adding the update later reuses the finished work. An older folder for the same game is used if there is one.
func buildFolderKey(_ family: String, games: URL = Paths.games) -> String {
    let fm = FileManager.default
    if fm.fileExists(atPath: games.appendingPathComponent(family + "_build").path) { return family }
    for d in ((try? fm.contentsOfDirectory(atPath: games.path)) ?? []).sorted() where d.hasSuffix("_build") {
        if fm.fileExists(atPath: games.appendingPathComponent(d + "/profile/" + family).path) { return String(d.dropLast(6)) }
    }
    return family
}
