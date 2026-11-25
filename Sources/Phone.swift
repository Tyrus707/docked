import Foundation

// Apps for an iPhone or iPad: a project for Xcode (Xcode.swift), or an .ipa file the player signs and installs with a sideloading tool of their own.
enum Target: String, Codable { case mac, phone }
let phoneNeeds = "iPhone 15 Pro or later, or an iPad with an M1 chip or later, with iOS or iPadOS 26. Older ones can't run these games."
var phoneFolder: URL { Paths.root.appendingPathComponent("iPhone") }
func toolPath(_ n: String) -> Bool { ((Paths.unpacked ? [Paths.tools.path + "/bin"] : []) + ["/opt/homebrew/bin"]).contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + n) } }
func runPhoneChecks() -> [Check] {
    let sdk = run("/usr/bin/xcrun", ["--sdk", "iphoneos", "--show-sdk-version"]), v = sdk.out.trimmingCharacters(in: .whitespacesAndNewlines), ok = sdk.code == 0, gen = toolPath("xcodegen"), brew = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew")
    return [Check(title: "Apple's iOS tools", ok: ok, detail: ok ? "iOS \(v)" : "A free Apple download of several GB", fix: ok ? "" : "DEVELOPER_DIR=\(Paths.xcode) xcodebuild -downloadPlatform iOS"),
            Check(title: "XcodeGen", ok: gen, detail: gen ? "Installed" : brew ? "A free tool, from Homebrew" : "A free tool, from Homebrew. Install Homebrew from brew.sh first", fix: gen || !brew ? "" : "brew install xcodegen")]
}
// A file name of its own, from what the game calls itself
func phoneFile(_ name: String, in dir: URL = phoneFolder) -> URL {
    let safe = String(name.unicodeScalars.filter { !CharacterSet(charactersIn: "/:\\").contains($0) && !CharacterSet.controlCharacters.contains($0) }.map(Character.init)).trimmingCharacters(in: CharacterSet(charactersIn: ". ")), base = safe.isEmpty ? "Game" : String(safe.prefix(80))
    var u = dir.appendingPathComponent(base + ".ipa"), n = 1; while FileManager.default.fileExists(atPath: u.path) { n += 1; u = dir.appendingPathComponent("\(base) \(n).ipa") }; return u
}
func looksLikeIPA(_ u: URL) -> Bool { guard let h = try? FileHandle(forReadingFrom: u), let m = try? h.read(upToCount: 4) else { return false }; try? h.close(); return m == Data([0x50, 0x4B, 0x03, 0x04]) && folderSize(u) > 1000 }

// ---- the keys file: is it one, and how new? Only names and how many are looked at; values are never kept, shown or written anywhere. ----
enum KeysVerdict: Equatable { case good(newest: Int), incomplete, notKeys
    var text: String { switch self { case let .good(n): return "This looks right. Its newest key is number \(n). If a newer game can't be unlocked, dump your keys again after updating your Switch."; case .incomplete: return "Some keys are missing from this file. Dump it again from your Switch."; case .notKeys: return "That isn't a keys file." } }
    var usable: Bool { if case .good = self { return true }; return false } }
func readKeys(_ path: String) -> KeysVerdict {
    guard let n = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])), n.isRegularFile == true, (n.fileSize ?? 0) < 1_000_000, let s = try? String(contentsOfFile: path, encoding: .utf8) else { return .notKeys }
    var header = false, newest = -1, any = 0
    for l in s.split(whereSeparator: \.isNewline) {
        let p = l.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }; guard p.count == 2, p[1].count >= 32, p[1].allSatisfy(\.isHexDigit) else { continue }
        any += 1; if p[0] == "header_key" { header = true }
        if p[0].hasPrefix("master_key_"), let k = Int(p[0].dropFirst(11), radix: 16) { newest = max(newest, k) }
    }
    return any == 0 ? .notKeys : header && newest >= 0 ? .good(newest: newest) : .incomplete
}

// ---- the first-run guide: which step comes next ----
enum GuideStep: Int, CaseIterable { case welcome, tools, keys, games
    var title: String { switch self { case .welcome: return "Welcome to Docked"; case .tools: return "Get your Mac ready"; case .keys: return "Choose your keys"; case .games: return "Add your first game" } } }
// The first thing still to do, so only one is ever asked for at a time
func nextCheck(_ c: [Check]) -> Check? { c.first { !$0.ok } }
