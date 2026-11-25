import Foundation

// What the engine's makers wrote about a game: its open problems, in the lines a player can use. Read from the engine already on this Mac.
enum GameNotes {
    static func file(_ id: String) -> URL { Paths.engine.appendingPathComponent("dm/games/\(id.uppercased())/README.md") }
    static func page(_ id: String) -> URL { URL(string: "https://github.com/seedds/nxnative/blob/\(pinnedEngine)/dm/games/\(id.uppercased())/README.md")! }
    // Notes to developers rather than to players
    private static let inside = #"\.(py|tsv|md|c|h|m|swift|bfsha|arc|json|log|patch)\b|\bDM_[A-Z]|0x[0-9a-fA-F]+|\bTODO\b|[a-z]+_[a-z_]+|\b(SDK|HLE|NRO|ExeFS|NVN|MSL|SPIR|PSO|IPA|iPhone|iPad|iOS|archive|profile|rewriter|translate[sd]?|recompiler|decompil|register|build ID|commit|regress|survey|cross-?check|validated?|validation|measured?|unmeasured|driven|bring-?up|headless|subsdk|symbol|hook|opcode|heap|thread|allocator|residency|alpha test|shaders?|textures?|descriptors?|upload|swizzle|deswizzle|stalls?|route|prewarm|memory pools?|fragment|chain|extracted|packed|merged|2D|3D|decoders?|decoding|logs?|logged|pipelines?|runs?|current main|builds?|NV12|VP\d|copy|label|registered|matched|matches|dead-code|no longer|fixed|provisional|uniform|multisample|module|binary|host|guest|port|probe[ds]?|capture[ds]?|compared|v\d{3,})\b|::|->|#\d+"#
    static func read(_ md: String, limit: Int = 4) -> [String] {
        var on = false, items: [String] = [], cur: String?
        func end() { if let c = cur { items.append(c) }; cur = nil }
        for raw in md.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = String(raw)
            if l.hasPrefix("#") { end(); let h = l.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased(); on = h == "open" || h.hasPrefix("known ") || h.hasPrefix("open ") ; continue }
            guard on else { continue }
            if l.hasPrefix("- ") || l.hasPrefix("* ") { end(); cur = String(l.dropFirst(2)) } else if l.trimmingCharacters(in: .whitespaces).isEmpty { end() } else if cur != nil { cur! += " " + l.trimmingCharacters(in: .whitespaces) }
        }
        end(); return Array(items.compactMap(plain).prefix(limit))
    }
    // One line as a player would read it, or nothing
    static func plain(_ s: String) -> String? {
        func sub(_ t: String, _ p: String, _ w: String) -> String { t.replacingOccurrences(of: p, with: w, options: .regularExpression) }
        var t = sub(s, #"\[([^\]]*)\]\([^)]*\)"#, "$1"); t = sub(t, #"\s*\([^()]*[`/#][^()]*\)"#, ""); t = t.replacingOccurrences(of: "**", with: "")
        if t.contains("`") || t.range(of: inside, options: .regularExpression) != nil {   // keep the first sentence when that much is plain
            let first = t.components(separatedBy: ". ").first ?? ""; guard first.count < t.count, !first.contains("`"), first.range(of: inside, options: .regularExpression) == nil else { return nil }; t = first
        }
        t = sub(t, #"\s+"#, " ").trimmingCharacters(in: .whitespaces); guard t.count >= 24, t.split(separator: " ").count >= 5, t.range(of: #"^(Current|Validate|Verify|Check|Diagnose|Find|Test|Record|Measure|Known:|Optional|The empty)\b"#, options: .regularExpression) == nil else { return nil }
        if t.count > 200 { t = String(t.prefix(200)); if let k = t.lastIndex(of: " ") { t = String(t[..<k]) }; t += "…" } else if !".!?…".contains(t.last!) { t += "." }
        return t.firstCapital
    }
    static func of(_ id: String) -> [String] { guard id.count == 16, id.allSatisfy(\.isHexDigit), let s = try? String(contentsOf: file(id), encoding: .utf8) else { return [] }; return read(s) }
}
extension String { var firstCapital: String { prefix(1).uppercased() + dropFirst() } }
