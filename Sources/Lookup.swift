import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

// ---- Finding a game's cover and details ----
// Only when the player has said yes. Docked matches a game against libretro's public game list (libretro-database,
// CC BY-SA 4.0), downloaded once per console from a fixed commit on GitHub and checked against the SHA-256 below, so the
// file's checksum, its disc serial and its name are compared on this Mac and never sent. Its cover comes from
// libretro-thumbnails, also at fixed commits, which sees only the game's name. A description the list doesn't have may
// come from Wikipedia (CC BY-SA 4.0), which also sees only the name. No account, no key.
struct GameInfo: Codable, Equatable {
    var title: String              // the list's own name, "Super Metroid (Japan, USA) (En,Ja)"
    var year: Int?
    var developer: String?
    var publisher: String?
    var genre: String?
    var about: String?
    var aboutFrom: String?         // a link to where the description came from, when it isn't the game list
    var how: String                // "checksum", "serial", "name" or "chosen"
    var name: String { cleanTitle(title) }
    var line: String { [year.map(String.init), publisher ?? developer].compactMap { $0 }.joined(separator: " · ") }
}

// One title in the list, with all its versions: the best of their details, and their names best first, for the cover.
struct Candidate: Identifiable, Equatable {
    var id: String { key }
    let key: String
    var info: GameInfo
    var names: [String]
    var score = 0.0
}

enum Match: Equatable { case found(Candidate), choose([Candidate]), none }

struct ListEntry { var name = "", crc: UInt32?, serial: String?, year: Int?, developer: String?, publisher: String?, genre: String?, about: String? }

// A console's game list, read once and kept while Docked is open
final class GameList {
    let entries: [ListEntry]
    private(set) var byCRC: [UInt32: [Int]] = [:], bySerial: [String: [Int]] = [:], byTitle: [String: [Int]] = [:]
    private var words: [String: Set<String>] = [:]
    init(_ e: [ListEntry]) {
        entries = e
        for (i, x) in e.enumerated() {
            if let c = x.crc { byCRC[c, default: []].append(i) }
            if let s = x.serial { for k in Lookup.serialKeys(s) { bySerial[k, default: []].append(i) } }
            if !x.name.isEmpty { let k = Lookup.titleKey(x.name); if !k.isEmpty { byTitle[k, default: []].append(i) } }
        }
        // Searched by name: titles with a known-good dump. A title's main part, before " - " or ":", counts nearly as much as all of it.
        for x in e where !x.name.isEmpty && !x.name.contains("[") {
            let k = Lookup.titleKey(x.name); guard !k.isEmpty, words[k] == nil else { continue }
            words[k] = Set(k.split(separator: " ").map(String.init))
            if let r = cleanTitle(x.name).range(of: #" - |: "#, options: .regularExpression) { let m = Lookup.titleKey(String(cleanTitle(x.name)[..<r.lowerBound])); if m != k, m.contains(" ") { mains[k] = m } }
        }
    }
    private var mains: [String: String] = [:]
    func candidate(_ key: String, how: String, region: [String] = [], score: Double = 1) -> Candidate? {
        guard let ids = byTitle[key], !ids.isEmpty else { return nil }
        // Versions with a known-good dump first (TOSEC's hacks and bad dumps carry [tags] and have no covers)
        let all = ids.map { entries[$0] }, clean = all.filter { !$0.name.contains("[") }, pool = clean.isEmpty ? all : clean
        func rank(_ n: String) -> Int {
            let tags = n.lowercased()
            for (i, r) in (region + ["usa", "world", "europe", "japan"]).enumerated() where tags.contains("(" + r) || tags.contains(", " + r) || tags.contains(r + ",") { return i }
            return 99
        }
        let sorted = pool.sorted { a, b in
            let x = rank(a.name), y = rank(b.name)
            if x != y { return x < y }
            let fa = [a.year != nil, a.developer != nil, a.publisher != nil, a.genre != nil].filter { $0 }.count, fb = [b.year != nil, b.developer != nil, b.publisher != nil, b.genre != nil].filter { $0 }.count
            return fa != fb ? fa > fb : a.name.count < b.name.count
        }
        let best = sorted[0]
        func first<T>(_ f: (ListEntry) -> T?) -> T? { f(best) ?? sorted.lazy.compactMap(f).first }
        let about = first { e in e.about.flatMap { $0.count > 40 && $0 != e.name ? $0 : nil } }
        var seen = Set<String>(), names: [String] = []
        for e in sorted where seen.insert(e.name).inserted { names.append(e.name) }
        return Candidate(key: key, info: GameInfo(title: best.name, year: first(\.year), developer: first(\.developer), publisher: first(\.publisher), genre: first(\.genre), about: about, how: how), names: Array(names.prefix(5)), score: score)
    }
    func titles(of ids: [Int]) -> [String] { var seen = Set<String>(); return ids.compactMap { i in let k = Lookup.titleKey(entries[i].name); return !k.isEmpty && seen.insert(k).inserted ? k : nil } }
    // Titles that sound like `q`, best first
    func similar(_ q: String, limit: Int = 8, floor: Double = 0.35) -> [(key: String, score: Double)] {
        let k = Lookup.titleKey(q), w = Set(k.split(separator: " ").map(String.init))
        guard !w.isEmpty else { return [] }
        var out: [(key: String, score: Double)] = []
        let numbers = w.filter { $0.allSatisfy(\.isNumber) }
        for (t, tw) in words {
            var s = t == k ? 1 : 2 * Double(w.intersection(tw).count) / Double(w.count + tw.count)
            if s < 1, numbers != tw.filter({ $0.allSatisfy(\.isNumber) }) { s *= 0.6 }   // Final Fantasy 3 isn't Final Fantasy 2
            // "Donkey Kong Country 2" is "... 2 - Diddy's Kong Quest"; "Final Fantasy" alone could be "... - Mystic Quest" or any other, so it is only offered
            if s < 1, mains[t] == k { s = max(s, k.split(separator: " ").last?.allSatisfy(\.isNumber) == true ? 0.9 : 0.75) }
            if s < 1, t.hasPrefix(k + " ") { s = max(s, 0.6) }   // the start of a longer name, as typed in a search
            if s >= floor { out.append((t, s)) }
        }
        return Array(out.sorted { $0.score != $1.score ? $0.score > $1.score : $0.key < $1.key }.prefix(limit))
    }
}

enum Lookup {
    // ---- the reviewed lists: a fixed commit, and each file's SHA-256. A different file is refused. ----
    static var source = "https://raw.githubusercontent.com"
    static let database = "f89f09cbe13f9f7863ecf20d0ebf2c5ce53be029"   // libretro/libretro-database, 2026-11-25
    static var lists: [String: String] = [
        "Nintendo - Nintendo Entertainment System": "dd7899b0e65ef00edad4b140af3a73f4ba2fc67050d6f934828dec5c24586144",
        "Nintendo - Super Nintendo Entertainment System": "d7f3078390975752df038620eebd70a9ab1c11b38aea1d2264e8cbe7ba074fe6",
        "Nintendo - Nintendo 64": "e070d28e4c3fa1651890fdbb769faa3555cc6f3a42c449b163513b46ecd2e556",
        "Nintendo - Game Boy": "d4fa788a579212003aef585896343f9c59d71772c34c70bd7b6126c643768766",
        "Nintendo - Game Boy Color": "ca3c802c7a20a2eb5bd830884da3d7701578292c9504e43eaa495ce50dc30b2a",
        "Nintendo - Game Boy Advance": "4326c0f8704e1632f816157ea474281710327f429a1beaa174efcf470efbecf2",
        "Nintendo - Nintendo DS": "af7eec49116e249bdc193f27a1349d0b0fe8325819653178c659747e1b39c786",
        "Nintendo - Nintendo 3DS": "4b502b88b7d6ee77c23bbf0edb0cd608e48f00436e9eb10476c16ea2299f326e",
        "Nintendo - GameCube": "8a596a54b4cda91eaaaffa8891a3a331554e9275475c6b2f3c8a4acf637b6bf9",
        "Nintendo - Wii": "75a3dd2e7c8328d40ec1e50809224deb880a8527f4a13a3d145cbdc397d8db4f",
        "Sega - Mega Drive - Genesis": "f05249f75c65b7738f42498dd2129e821389227940935421e6bd6081e46560eb",
        "Sega - Master System - Mark III": "eb0fde1bc3a5d89503d01b17d2eb5c84597c781ee67266d69ddc1551d62a5bfd",
        "Sega - Game Gear": "71220ce84c89e7ce6f7bdbc04b2deaa8005925b092fa46a5d3bf313fb8bca6a8",
        "Sega - Saturn": "d7acfd2c5d58677d569d71de6c72ccfdb3983ef02282eca2ee7d80ba5955c827",
        "Sega - Dreamcast": "6a3ef06bb9fea8c222642f2af272ba30a704cdb0437228aa8f128afb40575380",
        "Sony - PlayStation": "4b1025ff4cc9b3f924292a9052e0ecace5a3c8ce1a98d4d0106b029919b146d6",
        "Sony - PlayStation 2": "6b2ca894bcd8ec7a9abdebac05d5dd9371ba0d001ec73e5921e95d38a959dcae",
        "Sony - PlayStation Portable": "8e1b88004192bc2b59e23b3fcb13bc1ed2895696aac74480c2a15051d932b816",
        "NEC - PC Engine - TurboGrafx 16": "b09c576b5deec45aa08d927b9d380d8971cf00d0eb82ade72a70428dfb566939",
        "Atari - 2600": "ef8516327e4ba76926b640aa0d669af1c8f409d09f8b006f71e7bac7b3cb6117",
    ]
    // libretro-thumbnails keeps each console in its own repository; a commit names exactly one set of pictures.
    static var covers: [String: String] = [
        "Nintendo - Nintendo Entertainment System": "29607117d7dd3a0d42273dc5599ad5982cf5eb91",
        "Nintendo - Super Nintendo Entertainment System": "3298e21ecddfba90a589180f81ea242d2a90d7bb",
        "Nintendo - Nintendo 64": "ff0badea277f2d2d15e9008b04f1a0fd6abc40a3",
        "Nintendo - Game Boy": "f033af49af2d9761d6821aff479bb0ba5feea5e3",
        "Nintendo - Game Boy Color": "0931985ba8a3a9f38fb87f006611a13dc094260f",
        "Nintendo - Game Boy Advance": "23b8665408e767fd3220bfb83fd5ad8dfe1a9aa1",
        "Nintendo - Nintendo DS": "a119dcab8fa04c9974b9c229eda824318d923322",
        "Nintendo - Nintendo 3DS": "a1e242aca9d194ba7c168e38e14c637ff206189f",
        "Nintendo - GameCube": "c0e778f3242811f31f4815ff2807022c1c5ac7bd",
        "Nintendo - Wii": "1a44c6f4251dc9ef051043f22f8d9df4237c1ee8",
        "Sega - Mega Drive - Genesis": "cdae3026b7499b36c0162b394a1ec2ef28b82705",
        "Sega - Master System - Mark III": "3bb5e044786a3bc456c3f58c5d473748899b3dca",
        "Sega - Game Gear": "ac963d8297e70c4f06fb9a1cf378c321f8769a64",
        "Sega - Saturn": "c512bd123db1307f77b50383fb478b4ddb14fd20",
        "Sega - Dreamcast": "28b140d16f188301ad697e5935c6dbb412a4ceda",
        "Sony - PlayStation": "d3b75560b3313e3bbe4702bea0944151969f0cb4",
        "Sony - PlayStation 2": "9425fc0bb53dc2db2ccde4eb4a5172e9ee43f01f",
        "Sony - PlayStation Portable": "caa8a7f67f63ebaa470135edaa19366fd05731e8",
        "NEC - PC Engine - TurboGrafx 16": "33cbdb64bd99347ea47a5390584214f18d772b1f",
        "Atari - 2600": "8c91fd5d4cdadb6e66e146ab5b5334aebd3c82e9",
    ]
    static var wikipedia: String? = "https://en.wikipedia.org"   // nil: no descriptions from it
    static let consent = "Docked can fill in each game's cover, year, publisher and description. It downloads libretro's public game list for that console once and compares your files with it on this Mac, so your files never leave it. Covers come from libretro's picture collection on GitHub, and some descriptions from Wikipedia. Both see only the game's name. You can change this in Settings."
    static var home: URL { Paths.root.appendingPathComponent("Metadata") }
    static func artFile(_ id: String) -> URL { home.appendingPathComponent("Covers/" + id.replacingOccurrences(of: ":", with: "-") + ".png") }
    static let queue = DispatchQueue(label: "lookup", qos: .utility)
    static let biggest = 512 << 20   // larger files are matched by name: reading them all would take too long

    // ---- the game list ----
    private static var loaded: [String: GameList] = [:]
    private static let lock = NSLock()
    static func list(_ c: Console) throws -> GameList {
        lock.lock(); if let l = loaded[c.folder] { lock.unlock(); return l }; lock.unlock()
        guard let sha = lists[c.folder] else { throw RetroError("Docked has no game list for \(c.name).") }
        let file = home.appendingPathComponent("Lists/\(c.folder).rdb")
        if RetroArch.sha256(file) != sha {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp = file.appendingPathExtension("part"); try? FileManager.default.removeItem(at: tmp)
            try RetroArch.download(url("libretro/libretro-database/\(database)/rdb/\(c.folder).rdb"), to: tmp, limit: 40 << 20) { _ in }
            guard RetroArch.sha256(tmp) == sha else { try? FileManager.default.removeItem(at: tmp); throw RetroError("The \(c.name) game list didn't match the reviewed one, so it wasn't used.") }
            try? FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: tmp, to: file)
        }
        guard let d = try? Data(contentsOf: file), let e = RDB.parse(d) else { throw RetroError("The \(c.name) game list couldn't be read.") }
        let l = GameList(e); lock.lock(); loaded[c.folder] = l; lock.unlock(); return l
    }
    static func forget() { lock.lock(); loaded = [:]; lock.unlock() }
    static let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~()!,'+")
    static func url(_ path: String) -> URL {
        let p = path.split(separator: "/", omittingEmptySubsequences: false).map { $0.addingPercentEncoding(withAllowedCharacters: safe) ?? String($0) }.joined(separator: "/")
        return URL(string: source + "/" + p)!
    }

    // ---- matching: the file's checksum, then a disc's serial, then its name ----
    static func match(_ r: Rom) throws -> Match {
        guard let c = console(r.console), !c.native else { return .none }
        let l = try list(c), u = URL(fileURLWithPath: r.path), region = regions(u.lastPathComponent)
        func decide(_ keys: [String], _ how: String) -> Match? {
            let cs = keys.compactMap { l.candidate($0, how: how, region: region) }
            return cs.count == 1 ? .found(cs[0]) : cs.count > 1 ? .choose(cs) : nil
        }
        let hits = crcs(u, c.id).flatMap { l.byCRC[$0] ?? [] }
        if !hits.isEmpty, let m = decide(l.titles(of: hits), "checksum") { return m }
        if let s = Disc.serial(u) {
            let ids = serialKeys(s).flatMap { l.bySerial[$0] ?? [] }
            if !ids.isEmpty, let m = decide(l.titles(of: ids), "serial") { return m }
        }
        return byName(cleanName(u), in: l, region: region)
    }
    static func byName(_ n: String, in l: GameList, region: [String] = []) -> Match {
        let s = l.similar(n)
        guard let top = s.first, top.score >= 0.5 else { return .none }
        let next = s.dropFirst().first?.score ?? 0
        if top.score >= 0.999 ? next < 0.999 : top.score >= 0.85 && next <= top.score - 0.15, let c = l.candidate(top.key, how: "name", region: region, score: top.score) { return .found(c) }
        return .choose(s.prefix(6).compactMap { l.candidate($0.key, how: "chosen", region: region, score: $0.score) })
    }
    static func search(_ q: String, _ c: Console) throws -> [Candidate] {
        let l = try list(c); return l.similar(q, limit: 12, floor: 0.2).compactMap { l.candidate($0.key, how: "chosen", score: $0.score) }
    }
    // "Final Fantasy III, The (USA) (Rev 1)" and "the final fantasy 3" are one key: "final fantasy 3"
    static func titleKey(_ s: String) -> String {
        var t = cleanTitle(s).folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil).lowercased()
        t = t.replacingOccurrences(of: "&", with: " and ").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        let roman = ["ii": "2", "iii": "3", "iv": "4", "v": "5", "vi": "6", "vii": "7", "viii": "8", "ix": "9", "x": "10", "xi": "11", "xii": "12", "xiii": "13"]
        var w = t.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !["the", "a", "an"].contains($0) }
        if w.count > 2, w[w.count - 2] == "rev" { w.removeLast(2) }   // "Super Mario Bros. 3 Rev PRG1", outside the brackets
        return w.enumerated().map { i, x in i > 0 ? roman[x] ?? x : x }.joined(separator: " ")
    }
    static func regions(_ file: String) -> [String] {
        let tags = file.lowercased()
        return [("usa", ["(usa", "(u)", "(us)"]), ("europe", ["(europe", "(e)", "(eur"]), ("japan", ["(japan", "(j)", "(jp"]), ("world", ["(world"])].filter { $0.1.contains { tags.contains($0) } }.map(\.0)
    }
    // A list's serial and a disc's, compared the same way: SLUS-00909, SLUS_009.09 and SLUS-00909GH-2 meet at SLUS00909.
    // GameCube and Wii lists write RVL-RYWP-EUR where the disc says RYWP01: they meet at the game's four letters.
    static func serialKeys(_ s: String) -> [String] {
        let u = s.uppercased(), parts = u.split(separator: "-").map(String.init)
        func norm(_ x: String) -> String { x.filter { $0.isASCII && ($0.isLetter || $0.isNumber) } }
        var k = [norm(u.split(separator: "/").first.map(String.init) ?? u)]
        if parts.count >= 2, ["RVL", "DOL"].contains(parts[0]), parts[1].count == 4 { k.append("ID" + parts[1]) }
        else if parts.count == 1, k[0].count == 6, k[0].prefix(4).allSatisfy(\.isLetter) || k[0].first.map({ "GRSDPWU".contains($0) }) == true { k.append("ID" + k[0].prefix(4)) }
        if let r = u.range(of: #"^[A-Z]+-?[0-9]{3,}"#, options: .regularExpression) { k.append(norm(String(u[r]))) }
        return Array(Set(k.filter { !$0.isEmpty }))
    }

    // ---- the file's checksum, the way the list keeps it ----
    static func crcs(_ u: URL, _ console: String) -> [UInt32] {
        if u.pathExtension.lowercased() == "zip" { return zipCRCs(u, console) }
        let size = folderSize(u)
        guard size > 0, size <= biggest, !["cue", "m3u", "chd", "iso", "cso", "rvz", "wia", "ciso", "gdi", "cdi", "ccd", "pbp", "wbfs", "gcz", "gcm"].contains(u.pathExtension.lowercased()) else { return [] }
        let head = Disc.read(u, 0, 4)
        var skip: [Int] = [0], order = 0
        switch console {
        case "nes": if head == Array("NES\u{1A}".utf8) || head == Array("FDS\u{1A}".utf8) { skip.append(16) }
        case "snes", "pce": if size % 1024 == 512 { skip.append(512) }
        case "n64": order = head == [0x37, 0x80, 0x40, 0x12] ? 2 : head == [0x40, 0x12, 0x37, 0x80] ? 4 : 0
        default: break
        }
        var out = skip.compactMap { crc32(u, skip: $0) }
        if order > 0, let z = crc32(u, swap: order) { out.append(z) }   // the list keeps N64 games in their big-endian order
        return out
    }
    // A zip already holds each file's CRC-32 in its central directory, so nothing needs unpacking.
    static func zipCRCs(_ u: URL, _ console: String) -> [UInt32] {
        guard let c = Lookup.console(console), let f = try? FileHandle(forReadingFrom: u), let end = try? f.seekToEnd(), end >= 22 else { return [] }
        defer { try? f.close() }
        let tail = Int(min(end, 66_000)); try? f.seek(toOffset: end - UInt64(tail))
        let t = [UInt8]((try? f.read(upToCount: tail)) ?? Data())
        func le(_ b: [UInt8], _ i: Int, _ w: Int) -> Int { i + w <= b.count ? (0..<w).reduce(0) { $0 | Int(b[i + $1]) << (8 * $1) } : -1 }
        guard let e = stride(from: t.count - 22, through: 0, by: -1).first(where: { le(t, $0, 4) == 0x06054B50 }) else { return [] }
        let size = le(t, e + 12, 4), at = le(t, e + 16, 4)
        guard size > 0, size < 16 << 20, at >= 0, UInt64(at + size) <= end else { return [] }
        try? f.seek(toOffset: UInt64(at)); let d = [UInt8]((try? f.read(upToCount: size)) ?? Data())
        var i = 0, out: [UInt32] = []
        while i + 46 <= d.count, le(d, i, 4) == 0x02014B50, out.count < 200 {
            let n = le(d, i + 28, 2), x = le(d, i + 30, 2), m = le(d, i + 32, 2)
            guard i + 46 + n <= d.count else { break }
            let name = String(decoding: d[(i + 46)..<(i + 46 + n)], as: UTF8.self)
            if c.types.contains((name as NSString).pathExtension.lowercased()), !name.hasPrefix("__MACOSX") { out.append(UInt32(le(d, i + 16, 4))) }
            i += 46 + n + x + m
        }
        return out
    }
    static func console(_ id: String) -> Console? { consoles.first { $0.id == id } }

    private static let table: [UInt32] = (0..<256).map { i in (0..<8).reduce(UInt32(i)) { c, _ in c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 } }
    static func crc32(_ u: URL, skip: Int = 0, swap: Int = 0) -> UInt32? {
        guard let f = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? f.close() }
        if skip > 0 { try? f.seek(toOffset: UInt64(skip)) }
        var c: UInt32 = 0xFFFFFFFF; let table = table
        while let d = try? f.read(upToCount: 4 << 20), !d.isEmpty {
            var b = [UInt8](d)
            if swap == 2 { var i = 0; while i + 1 < b.count { b.swapAt(i, i + 1); i += 2 } }
            if swap == 4 { var i = 0; while i + 3 < b.count { b.swapAt(i, i + 3); b.swapAt(i + 1, i + 2); i += 4 } }
            b.withUnsafeBufferPointer { p in for x in p { c = table[Int((c ^ UInt32(x)) & 0xFF)] ^ (c >> 8) } }
        }
        return c ^ 0xFFFFFFFF
    }

    // ---- the cover: libretro-thumbnails at its fixed commit, made small and kept ----
    static func thumbnail(_ name: String) -> String { name.replacingOccurrences(of: "[&*/:`<>?\\\\|\"]", with: "_", options: .regularExpression) }
    @discardableResult static func fetchCover(_ r: Rom, names: [String]) -> URL? {
        guard let c = console(r.console), let commit = covers[c.folder] else { return nil }
        let repo = c.folder.replacingOccurrences(of: " ", with: "_"), out = artFile(r.id)
        for kind in ["Named_Boxarts", "Named_Titles"] {
            for n in names.prefix(kind == "Named_Boxarts" ? 4 : 1) {
                guard let d = try? get(url("libretro-thumbnails/\(repo)/\(commit)/\(kind)/\(thumbnail(n)).png"), limit: 8 << 20), keep(d, at: out) else { continue }
                return out
            }
        }
        return nil
    }
    // Only a real PNG or JPEG of a sensible size, drawn again at the size covers use; the downloaded file is never kept as it came.
    static let small: CFDictionary = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 720, kCGImageSourceCreateThumbnailWithTransform: true] as [CFString: Any] as CFDictionary
    static func keep(_ d: Data, at u: URL) -> Bool {
        guard d.starts(with: [0x89, 0x50, 0x4E, 0x47]) || d.starts(with: [0xFF, 0xD8, 0xFF]),
              let src = CGImageSourceCreateWithData(d as CFData, nil), CGImageSourceGetCount(src) == 1,
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int, w > 8, h > 8, w <= 8192, h <= 8192,
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, small) else { return false }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = u.appendingPathExtension("part")
        guard let dst = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dst, img, nil)
        guard CGImageDestinationFinalize(dst) else { try? FileManager.default.removeItem(at: tmp); return false }
        try? FileManager.default.removeItem(at: u); return (try? FileManager.default.moveItem(at: tmp, to: u)) != nil
    }

    // ---- a description from Wikipedia, for games the list has none for ----
    static func about(_ title: String, _ c: Console) -> (text: String, link: String)? {
        guard let w = wikipedia, let q = cleanTitle(title).addingPercentEncoding(withAllowedCharacters: safe.subtracting(CharacterSet(charactersIn: "+"))),
              let s = URL(string: "\(w)/w/rest.php/v1/search/title?q=\(q)&limit=6"), let d = try? get(s, limit: 1 << 20),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let pages = j["pages"] as? [[String: Any]] else { return nil }
        let want = titleKey(title)
        // A video game's article, named like the game: "Contra III: The Alien Wars", or "Metroid (video game)"
        guard let page = pages.first(where: { p in
            let t = (p["title"] as? String ?? "").replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression)
            let k = titleKey(t), a = Set(want.split(separator: " ")), b = Set(k.split(separator: " "))
            return (p["description"] as? String ?? "").lowercased().contains("video game") && !a.isEmpty && (k == want || 2 * Double(a.intersection(b).count) / Double(a.count + b.count) >= 0.75)
        }), let key = page["key"] as? String, let ek = key.addingPercentEncoding(withAllowedCharacters: safe),
              let su = URL(string: "\(w)/api/rest_v1/page/summary/\(ek)"), let sd = try? get(su, limit: 1 << 20),
              let sj = try? JSONSerialization.jsonObject(with: sd) as? [String: Any], let text = sj["extract"] as? String, text.count > 40 else { return nil }
        return (short(text), "\(w)/wiki/\(ek)")
    }
    static func short(_ t: String, _ most: Int = 700) -> String {
        guard t.count > most else { return t }
        let cut = String(t.prefix(most)); if let r = cut.range(of: ". ", options: .backwards), r.lowerBound > cut.index(cut.startIndex, offsetBy: most / 3) { return String(cut[..<r.lowerBound]) + "." }
        return cut + "…"
    }

    // Everything for one game, off the main thread: the match, then its description and cover.
    static func fill(_ r: Rom, _ m: Candidate, wantAbout: Bool = true) -> (info: GameInfo, cover: URL?) {
        var i = m.info
        if wantAbout, i.about == nil || i.about?.hasSuffix("...") == true, let c = console(r.console), let a = about(i.title, c) { i.about = a.text; i.aboutFrom = a.link }
        return (i, fetchCover(r, names: m.names))
    }

    // ---- fetching small files ----
    static func get(_ u: URL, limit: Int) throws -> Data? {
        if u.isFileURL { return FileManager.default.fileExists(atPath: u.path) ? try Data(contentsOf: u) : nil }   // a local copy, used by the tests
        guard u.scheme == "https" else { throw RetroError("Docked only downloads over a secure connection.") }
        let c = URLSessionConfiguration.ephemeral; c.httpCookieStorage = nil; c.urlCache = nil; c.timeoutIntervalForRequest = 20; c.timeoutIntervalForResource = 60
        c.httpAdditionalHeaders = ["User-Agent": "Docked/\(appVersion) (https://github.com/Tyrus707/docked)"]
        let s = URLSession(configuration: c); defer { s.invalidateAndCancel() }
        let done = DispatchSemaphore(value: 0); var out: Data?, status = 0, failed: Error?
        s.dataTask(with: u) { d, r, e in out = d; status = (r as? HTTPURLResponse)?.statusCode ?? 0; failed = e; done.signal() }.resume(); done.wait()
        if status == 404 { return nil }
        if let failed { throw failed }
        guard status == 200, let d = out, d.count <= limit else { throw RetroError("The download didn't finish. Check your connection and try again.") }
        return d
    }
}

// ---- RetroArch's database files: "RARCHDB", where its index starts, then one MessagePack map per game ----
enum RDB {
    static func parse(_ d: Data) -> [ListEntry]? {
        let b = [UInt8](d)
        guard b.count >= 16, Array(b[0..<7]) == Array("RARCHDB".utf8) else { return nil }
        var i = 16, out: [ListEntry] = []
        while i < b.count {
            guard b[i] & 0xF0 == 0x80 || b[i] == 0xDE || b[i] == 0xDF else { break }   // the list ends with nil, then its index
            guard let n = mapCount(b, &i) else { return nil }
            var e = ListEntry()
            for _ in 0..<n {
                guard case .text(let k)? = value(b, &i), let v = value(b, &i) else { return nil }
                switch (k, v) {
                case ("name", .text(let s)): e.name = s
                case ("crc", .bytes(let x)) where x.count == 4: e.crc = x.reduce(0) { $0 << 8 | UInt32($1) }
                case ("serial", .bytes(let x)): e.serial = String(decoding: x, as: UTF8.self)
                case ("serial", .text(let s)): e.serial = s
                case ("releaseyear", .int(let y)) where y > 1950 && y < 2100: e.year = y
                case ("developer", .text(let s)): e.developer = s
                case ("publisher", .text(let s)): e.publisher = s
                case ("genre", .text(let s)): e.genre = s
                case ("description", .text(let s)): e.about = s
                default: break
                }
            }
            out.append(e)
        }
        return out
    }
    enum Value { case text(String), bytes([UInt8]), int(Int), other }
    static func mapCount(_ b: [UInt8], _ i: inout Int) -> Int? {
        let t = b[i]
        if t & 0xF0 == 0x80 { i += 1; return Int(t & 0x0F) }
        if t == 0xDE, let n = uint(b, i + 1, 2) { i += 3; return n }
        if t == 0xDF, let n = uint(b, i + 1, 4) { i += 5; return n }
        return nil
    }
    static func uint(_ b: [UInt8], _ at: Int, _ w: Int) -> Int? { at + w <= b.count ? b[at..<at + w].reduce(0) { $0 << 8 | Int($1) } : nil }
    static func value(_ b: [UInt8], _ i: inout Int, depth: Int = 0) -> Value? {
        guard i < b.count, depth < 8 else { return nil }
        let t = b[i]
        func take(_ w: Int) -> [UInt8]? { guard i + w <= b.count else { return nil }; defer { i += w }; return Array(b[i..<i + w]) }
        func sized(_ head: Int, _ w: Int) -> [UInt8]? { guard let n = uint(b, i + head, w) else { return nil }; i += head + w; return take(n) }
        switch t {
        case 0x00...0x7F: i += 1; return .int(Int(t))
        case 0xE0...0xFF: i += 1; return .int(Int(t) - 256)
        case 0xA0...0xBF: i += 1; return take(Int(t & 0x1F)).map { .text(String(decoding: $0, as: UTF8.self)) }
        case 0xD9, 0xDA, 0xDB: return sized(1, t == 0xD9 ? 1 : t == 0xDA ? 2 : 4).map { .text(String(decoding: $0, as: UTF8.self)) }
        case 0xC4, 0xC5, 0xC6: return sized(1, t == 0xC4 ? 1 : t == 0xC5 ? 2 : 4).map { .bytes($0) }
        case 0xCC, 0xCD, 0xCE, 0xCF: let w = 1 << Int(t - 0xCC); guard let n = uint(b, i + 1, w) else { return nil }; i += 1 + w; return .int(n)
        case 0xD0, 0xD1, 0xD2, 0xD3: let w = 1 << Int(t - 0xD0); guard i + 1 + w <= b.count else { return nil }; i += 1 + w; return .other
        case 0xC0, 0xC2, 0xC3: i += 1; return .other
        case 0xCA, 0xCB: let w = t == 0xCA ? 4 : 8; guard i + 1 + w <= b.count else { return nil }; i += 1 + w; return .other
        case 0x90...0x9F, 0xDC, 0xDD:
            let n: Int; if t <= 0x9F { n = Int(t & 0x0F); i += 1 } else { guard let c = uint(b, i + 1, t == 0xDC ? 2 : 4) else { return nil }; n = c; i += t == 0xDC ? 3 : 5 }
            for _ in 0..<n { guard value(b, &i, depth: depth + 1) != nil else { return nil } }
            return .other
        case 0x80...0x8F, 0xDE, 0xDF:
            guard let n = mapCount(b, &i) else { return nil }
            for _ in 0..<(n * 2) { guard value(b, &i, depth: depth + 1) != nil else { return nil } }
            return .other
        default: return nil
        }
    }
}
