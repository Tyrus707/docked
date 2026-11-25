import Foundation

// Several consoles share the disc file types (.iso, .cue, .chd and the rest). Instead of asking straight away,
// Docked looks inside: a GameCube or Wii disc says so in its header, a PlayStation disc has SYSTEM.CNF,
// a Saturn or Dreamcast disc starts with SEGA's own text, a PSP disc names itself. Only the first few
// kilobytes are read. Anything unreadable or unknown leaves the choice to the player, as before.
enum Disc {
    static func narrow(_ u: URL, _ choices: [Console]) -> [Console] {
        guard choices.count > 1, let ids = identify(u), !ids.isEmpty else { return choices }
        let k = choices.filter { ids.contains($0.id) }
        return k.isEmpty ? choices : k
    }

    // The consoles this file can be, or nil when nothing inside it tells.
    static func identify(_ u: URL, depth: Int = 0) -> Set<String>? {
        switch u.pathExtension.lowercased() {
        case "iso", "gcm": return nintendo(u, at: 0) ?? track(u, 0)
        case "rvz", "wia": return wia(u)
        case "ciso": return nintendo(u, at: 0x8000)
        case "cue": return cue(u)
        case "ccd": return track(u.deletingPathExtension().appendingPathExtension("img"), 0)
        case "chd": return chd(u)
        case "m3u":
            guard depth < 2, let first = lines(u).first(where: { !$0.hasPrefix("#") }) else { return nil }
            return identify(u.deletingLastPathComponent().appendingPathComponent(first), depth: depth + 1)
        default: return nil
        }
    }

    // ---- reading ----
    static func read(_ u: URL, _ offset: Int, _ count: Int) -> [UInt8] {
        guard offset >= 0, count > 0, let f = try? FileHandle(forReadingFrom: u) else { return [] }
        defer { try? f.close() }
        do { try f.seek(toOffset: UInt64(offset)); return [UInt8]((try f.read(upToCount: count)) ?? Data()) } catch { return [] }
    }
    static func be32(_ b: [UInt8], _ i: Int) -> UInt32 { i + 4 <= b.count ? b[i..<i + 4].reduce(0) { $0 << 8 | UInt32($1) } : 0 }
    static func le32(_ b: [UInt8], _ i: Int) -> Int { i + 4 <= b.count ? Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 : 0 }
    static func be64(_ b: [UInt8], _ i: Int) -> Int { i + 8 <= b.count ? Int(truncatingIfNeeded: b[i..<i + 8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }) : 0 }
    static func text(_ b: [UInt8], _ i: Int, _ n: Int) -> String {
        guard i >= 0, i < b.count else { return "" }
        return String(decoding: b[i..<min(b.count, i + n)], as: UTF8.self).trimmingCharacters(in: .whitespaces.union(.controlCharacters))
    }
    static func lines(_ u: URL) -> [String] {
        let b = read(u, 0, 64 << 10)
        return String(decoding: b, as: UTF8.self).split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // ---- Nintendo ----
    // A GameCube or Wii disc header has its magic word at 0x1C or 0x18.
    static func nintendo(_ u: URL, at base: Int) -> Set<String>? {
        let h = read(u, base, 0x20)
        if be32(h, 0x1C) == 0xC2339F3D { return ["gc"] }
        if be32(h, 0x18) == 0x5D1C9EA3 { return ["wii"] }
        return nil
    }
    // WIA and RVZ say which in their second header: 1 is GameCube, 2 is Wii.
    static func wia(_ u: URL) -> Set<String>? {
        let h = read(u, 0, 0x4C), m = text(h, 0, 3)
        guard m == "WIA" || m == "RVZ" else { return nil }
        switch be32(h, 0x48) { case 1: return ["gc"]; case 2: return ["wii"]; default: return nil }
    }

    // ---- CD and DVD images ----
    // One track's data, raw (2352-byte sectors with a sync pattern) or cooked (2048). `start` is in bytes.
    struct Track { let url: URL, start: Int, size: Int, data: Int
        func sector(_ n: Int) -> [UInt8] { Disc.read(url, start + n * size + data, 2048) }
    }
    static func open(_ u: URL, _ start: Int) -> Track {
        let h = read(u, start, 16)
        let sync: [UInt8] = [0] + Array(repeating: 0xFF, count: 10) + [0]
        guard h.count == 16, Array(h[0..<12]) == sync else { return Track(url: u, start: start, size: 2048, data: 0) }
        return Track(url: u, start: start, size: 2352, data: h[15] == 2 ? 24 : 16)
    }
    static func track(_ u: URL, _ start: Int) -> Set<String>? {
        let t = open(u, start), first = t.sector(0)
        let sega = text(first, 0, 16)
        if sega == "SEGA SEGASATURN" { return ["saturn"] }
        if sega == "SEGA SEGAKATANA" { return ["dreamcast"] }
        if (0..<16).contains(where: { String(decoding: t.sector($0), as: UTF8.self).contains("PC Engine CD-ROM SYSTEM") }) { return ["pce"] }
        let pvd = t.sector(16)
        guard text(pvd, 1, 5) == "CD001" else { return nil }
        let system = text(pvd, 8, 32)
        if system.hasPrefix("PSP GAME") || file(t, pvd, "PSP_GAME") != nil { return ["psp"] }
        if system.hasPrefix("PLAYSTATION") || file(t, pvd, "SYSTEM.CNF") != nil {
            guard let cnf = file(t, pvd, "SYSTEM.CNF") else { return ["ps1", "ps2"] }
            let s = String(decoding: cnf, as: UTF8.self).uppercased()
            return s.contains("BOOT2") ? ["ps2"] : s.contains("BOOT") ? ["ps1"] : ["ps1", "ps2"]
        }
        return nil
    }
    // A name in the root folder of an ISO 9660 disc: its first 4 KB, or nil.
    static func file(_ t: Track, _ pvd: [UInt8], _ name: String) -> [UInt8]? {
        let rootAt = le32(pvd, 156 + 2), rootSize = min(le32(pvd, 156 + 10), 32 << 10)
        guard rootAt > 0, rootSize > 0 else { return nil }
        for s in 0..<(rootSize + 2047) / 2048 {
            let d = t.sector(rootAt + s); var i = 0
            while i + 33 < d.count {
                let len = Int(d[i]); if len == 0 { break }
                let n = text(d, i + 33, Int(d[i + 32])).split(separator: ";").first.map(String.init) ?? ""
                if n.uppercased() == name {
                    let at = le32(d, i + 2), size = le32(d, i + 10)
                    if d[i + 25] & 2 != 0 { return [] }   // a folder: it is there
                    return Array(t.sector(at).prefix(min(size, 4096)))
                }
                i += len
            }
        }
        return nil
    }

    // A cue sheet names the tracks and their kind. PlayStation data is MODE2; a disc that starts with music is a PC Engine CD.
    static func cue(_ u: URL) -> Set<String>? {
        var file: URL?, firstFile: URL?, data: (url: URL, mode: String, index: Int)?, firstTrack = ""
        var current: (url: URL?, mode: String)?
        for l in lines(u) {
            let w = l.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let k = w.first?.uppercased() else { continue }
            if k == "FILE" {
                let name = l.range(of: #""[^"]+""#, options: .regularExpression).map { String(l[$0].dropFirst().dropLast()) } ?? (w.count > 1 ? w[1] : "")
                file = u.deletingLastPathComponent().appendingPathComponent(name); if firstFile == nil { firstFile = file }
            } else if k == "TRACK", w.count > 2 {
                current = (file, w[2].uppercased()); if firstTrack.isEmpty { firstTrack = w[2].uppercased() }
            } else if k == "INDEX", w.count > 2, w[1] == "01", let c = current, data == nil, c.mode != "AUDIO", let f = c.url {
                let m = w[2].split(separator: ":").compactMap { Int($0) }
                data = (f, c.mode, m.count == 3 ? (m[0] * 60 + m[1]) * 75 + m[2] : 0)
            }
        }
        if firstTrack == "AUDIO" && data != nil { return ["pce"] }
        guard let d = data else { return nil }
        let start = d.index * (d.mode.contains("2352") ? 2352 : 2048)
        if let seen = track(d.url, start) { return seen }
        return d.mode.hasPrefix("MODE2") ? ["ps1", "ps2"] : ["saturn", "pce", "dreamcast"]
    }

    // A CHD keeps its tracks in metadata: GD-ROM is Dreamcast, DVD is PS2 or PSP, and a CD's first track tells as a cue sheet does.
    static func chd(_ u: URL) -> Set<String>? {
        let h = read(u, 0, 124)
        guard text(h, 0, 8) == "MComprHD" else { return nil }
        let version = be32(h, 12)
        var at = version >= 5 ? be64(h, 48) : version >= 3 ? be64(h, 36) : 0, seen = 0
        var tracks: [String] = []
        while at > 0, seen < 64 {
            seen += 1
            let m = read(u, at, 16); guard m.count == 16 else { break }
            let tag = text(m, 0, 4), length = Int(m[5]) << 16 | Int(m[6]) << 8 | Int(m[7])
            if tag == "CHGD" { return ["dreamcast"] }
            if tag == "DVD" { return ["ps2", "psp"] }
            if ["CHT2", "CHTR", "CHCD"].contains(tag) { tracks.append(text(read(u, at + 16, min(length, 512)), 0, 512)) }
            at = be64(m, 8)
        }
        guard let first = tracks.first(where: { $0.contains("TRACK:1 ") }) ?? tracks.first else { return nil }
        if first.contains("TYPE:AUDIO") { return tracks.count > 1 ? ["pce"] : nil }
        return first.contains("TYPE:MODE2") ? ["ps1", "ps2"] : ["saturn", "pce", "dreamcast"]
    }
}
