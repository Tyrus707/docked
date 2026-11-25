import Foundation

// A console Docked can keep games for. Switch and Switch 2 are native; the rest play in RetroArch, which Docked sets up inside its own folder.
struct Console: Identifiable, Equatable {
    let id: String, name: String, maker: String
    let types: [String]          // file types that can only be this console
    let shared: [String]         // file types other consoles use too, so the player says which
    let cores: [(file: String, label: String)]   // best first
    let folder: String           // RetroArch's name for it, for art it has already downloaded
    var needs = ""               // system files the player has to supply
    var hue: Double
    static func == (a: Console, b: Console) -> Bool { a.id == b.id }
    var native: Bool { cores.isEmpty }
}

let consoles: [Console] = [
    Console(id: "switch", name: "Switch", maker: "Nintendo", types: [], shared: [], cores: [], folder: "", hue: 0.99),
    Console(id: "switch2", name: "Switch 2", maker: "Nintendo", types: [], shared: [], cores: [], folder: "", hue: 0.0),
    Console(id: "nes", name: "NES", maker: "Nintendo", types: ["nes", "fds", "unf"], shared: [], cores: [("mesen", "Mesen"), ("nestopia", "Nestopia"), ("fceumm", "FCEUmm")], folder: "Nintendo - Nintendo Entertainment System", hue: 0.02),
    Console(id: "snes", name: "SNES", maker: "Nintendo", types: ["sfc", "smc", "swc", "fig"], shared: [], cores: [("bsnes", "bsnes"), ("snes9x", "Snes9x")], folder: "Nintendo - Super Nintendo Entertainment System", hue: 0.74),
    Console(id: "n64", name: "Nintendo 64", maker: "Nintendo", types: ["n64", "z64", "v64"], shared: [], cores: [("mupen64plus_next", "Mupen64Plus-Next"), ("parallel_n64", "ParaLLEl N64")], folder: "Nintendo - Nintendo 64", hue: 0.36),
    Console(id: "gb", name: "Game Boy", maker: "Nintendo", types: ["gb"], shared: [], cores: [("sameboy", "SameBoy"), ("gambatte", "Gambatte"), ("mgba", "mGBA")], folder: "Nintendo - Game Boy", hue: 0.22),
    Console(id: "gbc", name: "Game Boy Color", maker: "Nintendo", types: ["gbc"], shared: [], cores: [("sameboy", "SameBoy"), ("gambatte", "Gambatte"), ("mgba", "mGBA")], folder: "Nintendo - Game Boy Color", hue: 0.82),
    Console(id: "gba", name: "Game Boy Advance", maker: "Nintendo", types: ["gba"], shared: [], cores: [("mgba", "mGBA"), ("gpsp", "gpSP")], folder: "Nintendo - Game Boy Advance", hue: 0.69),
    Console(id: "ds", name: "Nintendo DS", maker: "Nintendo", types: ["nds"], shared: [], cores: [("melondsds", "melonDS DS"), ("melonds", "melonDS"), ("desmume", "DeSmuME")], folder: "Nintendo - Nintendo DS", hue: 0.56),
    Console(id: "3ds", name: "Nintendo 3DS", maker: "Nintendo", types: ["3ds", "cci", "cxi"], shared: [], cores: [("azahar", "Azahar"), ("citra", "Citra")], folder: "Nintendo - Nintendo 3DS", hue: 0.0),
    Console(id: "gc", name: "GameCube", maker: "Nintendo", types: ["gcm", "gcz"], shared: ["iso", "rvz", "ciso"], cores: [("dolphin", "Dolphin")], folder: "Nintendo - GameCube", hue: 0.75),
    Console(id: "wii", name: "Wii", maker: "Nintendo", types: ["wbfs", "wia", "wad"], shared: ["iso", "rvz", "ciso"], cores: [("dolphin", "Dolphin")], folder: "Nintendo - Wii", hue: 0.53),
    Console(id: "genesis", name: "Genesis", maker: "Sega", types: ["md", "gen", "smd"], shared: [], cores: [("genesis_plus_gx", "Genesis Plus GX"), ("picodrive", "PicoDrive")], folder: "Sega - Mega Drive - Genesis", hue: 0.6),
    Console(id: "sms", name: "Master System", maker: "Sega", types: ["sms"], shared: [], cores: [("genesis_plus_gx", "Genesis Plus GX")], folder: "Sega - Master System - Mark III", hue: 0.01),
    Console(id: "gg", name: "Game Gear", maker: "Sega", types: ["gg"], shared: [], cores: [("genesis_plus_gx", "Genesis Plus GX")], folder: "Sega - Game Gear", hue: 0.5),
    Console(id: "saturn", name: "Saturn", maker: "Sega", types: [], shared: ["cue", "chd", "m3u"], cores: [("mednafen_saturn", "Beetle Saturn")], folder: "Sega - Saturn", needs: "a Saturn BIOS from your own console", hue: 0.64),
    Console(id: "dreamcast", name: "Dreamcast", maker: "Sega", types: ["gdi", "cdi"], shared: ["cue", "chd", "m3u"], cores: [("flycast", "Flycast")], folder: "Sega - Dreamcast", hue: 0.07),
    Console(id: "ps1", name: "PlayStation", maker: "Sony", types: ["pbp"], shared: ["cue", "chd", "m3u", "ccd"], cores: [("mednafen_psx_hw", "Beetle PSX HW"), ("swanstation", "SwanStation"), ("pcsx_rearmed", "PCSX ReARMed")], folder: "Sony - PlayStation", needs: "a PlayStation BIOS for best results", hue: 0.58),
    Console(id: "ps2", name: "PlayStation 2", maker: "Sony", types: [], shared: ["iso", "chd", "cue"], cores: [("armsx2", "ARMSX2"), ("pcsx2", "LRPS2")], folder: "Sony - PlayStation 2", needs: "a PlayStation 2 BIOS from your own console", hue: 0.66),
    Console(id: "psp", name: "PSP", maker: "Sony", types: ["cso"], shared: ["iso", "chd"], cores: [("ppsspp", "PPSSPP")], folder: "Sony - PlayStation Portable", hue: 0.54),
    Console(id: "pce", name: "TurboGrafx-16", maker: "NEC", types: ["pce"], shared: ["cue", "chd", "m3u"], cores: [("mednafen_pce", "Beetle PCE"), ("mednafen_pce_fast", "Beetle PCE Fast")], folder: "NEC - PC Engine - TurboGrafx 16", needs: "a System Card file for CD games", hue: 0.08),
    Console(id: "a26", name: "Atari 2600", maker: "Atari", types: ["a26"], shared: [], cores: [("stella", "Stella"), ("stella2014", "Stella 2014")], folder: "Atari - 2600", hue: 0.1),
]
func console(_ id: String) -> Console? { consoles.first { $0.id == id } }
func consoleOf(_ titleID: String) -> String {
    if titleID.uppercased().hasPrefix("ROM:") { return titleID.split(separator: ":").dropFirst().first.map { $0.lowercased() } ?? "" }
    return titleID.hasPrefix("04") ? "switch2" : "switch"
}

struct Rom: Codable, Equatable { var id: String, name: String, console: String, path: String }

// What a chosen file could be: one console (known), several (ask), or none.
func consolesFor(_ url: URL, inside: (URL) -> [String] = zipNames) -> [Console] {
    func by(_ e: String) -> [Console] { let k = consoles.filter { $0.types.contains(e) }; return k.isEmpty ? consoles.filter { $0.shared.contains(e) } : k }
    let e = url.pathExtension.lowercased()
    guard e == "zip" else { return Disc.narrow(url, by(e)) }
    let names = inside(url).filter { !$0.hasSuffix("/") && !$0.hasPrefix("__MACOSX") }
    let kinds = Set(names.map { ($0 as NSString).pathExtension.lowercased() }).filter { !by($0).isEmpty }
    return kinds.count == 1 ? by(kinds.first!).filter { $0.types.contains(kinds.first!) } : []
}

func zipNames(_ u: URL) -> [String] { let r = run("/usr/bin/zipinfo", ["-1", u.path], timeout: 10); return r.code == 0 ? r.out.split(separator: "\n").prefix(200).map(String.init) : [] }

// "Legend of Game, The (USA) (Rev 1) [!].sfc" -> "The Legend of Game"
func cleanName(_ url: URL) -> String {
    var n = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
    n = n.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    for a in ["The", "A", "An"] {
        if let r = n.range(of: ", \(a)( - |: |$)", options: .regularExpression) { let tail = n[r].dropFirst(a.count + 2); n = a + " " + n[n.startIndex..<r.lowerBound] + tail + n[r.upperBound...]; break }
    }
    return n.isEmpty ? url.deletingPathExtension().lastPathComponent : n
}

// The same for a file wherever it is moved to: its size and its first part.
func romID(_ url: URL, _ console: String) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    func mix(_ d: Data) { for b in d { h = (h ^ UInt64(b)) &* 0x100000001b3 } }
    if let f = try? FileHandle(forReadingFrom: url) { mix((try? f.read(upToCount: 1 << 18)) ?? Data()); try? f.close() }
    mix(Data("\(folderSize(url))".utf8))
    return "ROM:\(console):\(String(h, radix: 16))".uppercased()
}

// A disc's .bin files come with its .cue (and several .cue with an .m3u): only the one that stands for the game is kept.
func pickRoms(_ urls: [URL]) -> [URL] {
    let files = urls.flatMap { u -> [URL] in
        var d: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &d) else { return [] }
        guard d.boolValue else { return [u] }
        return ((try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []).sorted { $0.path < $1.path }
    }
    let listed = Set(files.filter { $0.pathExtension.lowercased() == "m3u" }.flatMap { m in
        ((try? String(contentsOf: m, encoding: .utf8)) ?? "").split(whereSeparator: \.isNewline).map { m.deletingLastPathComponent().appendingPathComponent(String($0)).standardizedFileURL.path }
    })
    return files.filter { !listed.contains($0.standardizedFileURL.path) && !["bin", "img", "sub", "sav", "srm", "state", "txt", "png", "jpg"].contains($0.pathExtension.lowercased()) }
}
