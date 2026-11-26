import Foundation
import Security
import IOKit.hid
import GameController

// Three extras for games that play in RetroArch: RetroAchievements, retro looks (libretro's slang shaders)
// and controller profiles. Shaders and profiles are libretro's own downloads, fetched only when first needed.

// ---- RetroAchievements: the player's own free account ----
enum Cheevos {
    static var host = "https://retroachievements.org"
    static var service = "Docked RetroAchievements"
    static var user: String? {
        get { UserDefaults.standard.string(forKey: "raUser").flatMap { $0.isEmpty ? nil : $0 } }
        set { UserDefaults.standard.set(newValue, forKey: "raUser") }
    }
    static var signedIn: Bool { user != nil && secret("token") != nil }
    // Hardcore: no save states, rewind or cheats, and unlocks count as hardcore on the site
    static var hardcore: Bool {
        get { UserDefaults.standard.bool(forKey: "raHardcore") }
        set { UserDefaults.standard.set(newValue, forKey: "raHardcore") }
    }

    // ---- Keychain ----
    static func secret(_ kind: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: kind, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func keep(_ kind: String, _ value: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: kind]
        SecItemDelete(q as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var a = q; a[kSecValueData as String] = Data(value.utf8); a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(a as CFDictionary, nil)
    }

    // Checks the password with RetroAchievements; only the token it gives back is kept, never the password.
    static func signIn(user u: String, password p: String, webKey: String) throws {
        let name = u.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !p.isEmpty else { throw RetroError("Type your RetroAchievements user name and password.") }
        var r = URLRequest(url: URL(string: "\(host)/dorequest.php")!); r.httpMethod = "POST"; r.timeoutInterval = 30
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); r.setValue("Docked/\(dockedVersion)", forHTTPHeaderField: "User-Agent")
        r.httpBody = form(["r": "login2", "u": name, "p": p]).data(using: .utf8)
        let j = try fetchJSON(r)
        guard j["Success"] as? Bool == true, let t = j["Token"] as? String, !t.isEmpty else { throw RetroError((j["Error"] as? String) ?? "RetroAchievements didn't accept that user name and password.") }
        keep("token", t); keep("webkey", webKey.trimmingCharacters(in: .whitespacesAndNewlines)); user = (j["User"] as? String) ?? name
        try? FileManager.default.removeItem(at: cache)
    }
    static func signOut() { keep("token", nil); keep("webkey", nil); user = nil; try? FileManager.default.removeItem(at: cache); progress = [:] }
    static func setWebKey(_ k: String) { keep("webkey", k.trimmingCharacters(in: .whitespacesAndNewlines)) }
    static var hasWebKey: Bool { secret("webkey") != nil }

    // What RetroArch gets for each game: the token, never the password.
    static func lines() -> String {
        guard let u = user, let t = secret("token") else { return RetroArch.line("cheevos_enable", "false") }
        return RetroArch.line("cheevos_enable", "true") + RetroArch.line("cheevos_username", u) + RetroArch.line("cheevos_token", t) + RetroArch.line("cheevos_password", "")
            + RetroArch.line("cheevos_hardcore_mode_enable", hardcore ? "true" : "false")
    }
    // RetroArch saves everything it was given into its own settings file when it quits; the token is taken out again.
    static func scrub(_ file: URL) {
        guard let s = try? String(contentsOf: file, encoding: .utf8), s.contains("cheevos_token") || s.contains("cheevos_password") else { return }
        let out = s.split(separator: "\n", omittingEmptySubsequences: false).map { l -> String in
            let k = l.split(separator: "=").first?.trimmingCharacters(in: .whitespaces) ?? ""
            return k == "cheevos_token" || k == "cheevos_password" ? "\(k) = \"\"" : String(l)
        }.joined(separator: "\n")
        if out != s { try? out.write(to: file, atomically: true, encoding: .utf8) }
    }

    // ---- progress, shown on the game page and in Couch Mode (needs the player's Web API key) ----
    struct Progress: Codable, Equatable { var title: String, console: Int, earned: Int, hardcore: Int, total: Int; var id: Int? = nil }   // id: RetroAchievements' game number, for the full list
    static var cache: URL { RetroArch.support.appendingPathComponent("achievements.json") }
    static var progress: [String: Progress] = load()   // by console id + matched title
    static var checked = Date.distantPast
    private static func load() -> [String: Progress] { (try? JSONDecoder().decode([String: Progress].self, from: Data(contentsOf: cache))) ?? [:] }

    // RetroAchievements' console numbers, for the consoles Docked keeps
    static let consoleIDs: [String: Int] = ["genesis": 1, "n64": 2, "snes": 3, "gb": 4, "gba": 5, "gbc": 6, "nes": 7, "pce": 8, "sms": 11, "ps1": 12, "gg": 15, "gc": 16, "ds": 18, "wii": 19, "ps2": 21, "a26": 25, "saturn": 39, "dreamcast": 40, "psp": 41]

    // Every game the player has started on RetroAchievements, in one request.
    static func refresh() throws {
        guard let u = user, let k = secret("webkey") else { return }
        var c = URLComponents(string: "\(host)/API/API_GetUserCompletionProgress.php")!
        c.queryItems = [URLQueryItem(name: "u", value: u), URLQueryItem(name: "y", value: k), URLQueryItem(name: "c", value: "500")]
        var r = URLRequest(url: c.url!); r.timeoutInterval = 30; r.setValue("Docked/\(dockedVersion)", forHTTPHeaderField: "User-Agent")
        let j = try fetchJSON(r)
        guard let list = j["Results"] as? [[String: Any]] else { throw RetroError("RetroAchievements didn't send your progress. Check the Web API key in Settings.") }
        var m: [String: Progress] = [:]
        for g in list {
            guard let t = g["Title"] as? String, !t.hasPrefix("~"), let cid = int(g["ConsoleID"]), let total = int(g["MaxPossible"]), total > 0 else { continue }
            m["\(cid):\(key(t))"] = Progress(title: t, console: cid, earned: int(g["NumAwarded"]) ?? 0, hardcore: int(g["NumAwardedHardcore"]) ?? 0, total: total, id: int(g["GameID"]))
        }
        progress = m; checked = Date()
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: cache, options: .atomic) }
    }
    static func of(_ r: Rom) -> Progress? {
        guard let cid = consoleIDs[r.console] else { return nil }
        for n in [r.info?.name, r.name].compactMap({ $0 }) { if let p = progress["\(cid):\(key(n))"] { return p } }
        return nil
    }
    // "Legend of Zelda, The - A Link to the Past (USA)" and "The Legend of Zelda: A Link to the Past" are the same game
    static func key(_ name: String) -> String {
        var s = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        s = s.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&", with: " and ").replacingOccurrences(of: ", the", with: " ")
        s = s.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("the ") { s.removeFirst(4) }
        return s.replacingOccurrences(of: " ", with: "")
    }
    static func text(_ p: Progress) -> String { "\(p.earned) of \(p.total)" + (p.hardcore > 0 && p.hardcore < p.earned ? ", \(p.hardcore) hardcore" : p.hardcore > 0 ? ", hardcore" : "") }
    static func int(_ v: Any?) -> Int? { (v as? Int) ?? (v as? String).flatMap(Int.init) ?? (v as? Double).map(Int.init) }
    private static func form(_ d: [String: String]) -> String {
        var ok = CharacterSet.alphanumerics; ok.insert(charactersIn: "-._~")
        return d.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: ok) ?? "")" }.joined(separator: "&")
    }
    private static func fetchJSON(_ r: URLRequest) throws -> [String: Any] {
        guard let j = try fetchAny(r) as? [String: Any] else { throw RetroError("RetroAchievements sent an answer Docked couldn't read.") }
        return j
    }
    // The Web API, with the player's key: some answers are lists, some are records
    static func api(_ name: String, _ q: [String: String]) throws -> Any {
        guard let u = user, let k = secret("webkey") else { throw RetroError("Add your Web API key to see achievements in Docked.") }
        var c = URLComponents(string: "\(host)/API/\(name).php")!
        c.queryItems = [URLQueryItem(name: "u", value: u), URLQueryItem(name: "y", value: k)] + q.map { URLQueryItem(name: $0.key, value: $0.value) }
        var r = URLRequest(url: c.url!); r.timeoutInterval = 30; r.setValue("Docked/\(dockedVersion)", forHTTPHeaderField: "User-Agent")
        return try fetchAny(r)
    }
    static func fetchAny(_ r: URLRequest) throws -> Any {
        let c = URLSessionConfiguration.ephemeral; c.httpCookieStorage = nil
        let s = URLSession(configuration: c); defer { s.finishTasksAndInvalidate() }
        let done = DispatchSemaphore(value: 0); var data: Data?, err: Error?
        s.dataTask(with: r) { d, _, e in data = d; err = e; done.signal() }.resume(); done.wait()
        if let err { throw RetroError("RetroAchievements couldn't be reached. \(err.localizedDescription)") }
        guard let data, data.count < 8 << 20, let j = try? JSONSerialization.jsonObject(with: data) else { throw RetroError("RetroAchievements sent an answer Docked couldn't read.") }
        return j
    }
}
// ---- what the Achievements views show (Achievements.swift) ----
struct Cheevo: Codable, Identifiable, Hashable {
    let id: Int
    let title, about, badge: String
    let points, order: Int
    let earned: Date?
    let hardcore: Bool
}
struct CheevoSet: Codable {
    let id: Int
    let title: String
    var list: [Cheevo]
    var fetched: Date
    var earned: [Cheevo] { list.filter { $0.earned != nil }.sorted { $0.earned! > $1.earned! } }
    var points: Int { list.reduce(0) { $0 + $1.points } }
    var earnedPoints: Int { list.reduce(0) { $0 + ($1.earned != nil ? $1.points : 0) } }
    // Unlocked first, newest first; then the rest in the set's own order
    var ordered: [Cheevo] { earned + list.filter { $0.earned == nil }.sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order } }
}
struct CheevoUnlock: Codable, Identifiable, Hashable {
    let id: Int
    let title, about, badge, game: String
    let gameID, points: Int
    let date: Date, hardcore: Bool
}
struct CheevoAccount: Codable {
    let user: String
    let pic, since, presence: String?
    let hardcore, softcore, retro: Int
    var recent: [CheevoUnlock]
    var fetched: Date
}
struct CheevoListing: Codable { let id, count, points: Int }   // a game RetroAchievements has a set for

// RetroAchievements writes its times as UTC, "2026-11-26 21:04:11"
func raDate(_ s: String) -> Date? { raFormat.date(from: s) }
private let raFormat: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()
extension JSONDecoder { static var ra: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d } }
extension JSONEncoder { static var ra: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e } }

private var dockedVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

// ---- retro looks: libretro's slang shaders, for each console, with a choice for each game ----
enum RetroLook: String, CaseIterable, Identifiable {
    case off, crt, lcd, sharp
    var id: String { rawValue }
    var label: String { switch self { case .off: return "Off"; case .crt: return "CRT TV"; case .lcd: return "Handheld LCD"; case .sharp: return "Sharp Pixels" } }
    var note: String {
        switch self {
        case .off: return "The picture as the core draws it."
        case .crt: return "Scanlines and a soft glow, like an old TV."
        case .lcd: return "The grid of a handheld's screen."
        case .sharp: return "Crisp, even pixels at any size."
        }
    }
    // Best first; libretro sometimes renames a preset
    var presets: [String] {
        switch self {
        case .off: return []
        case .crt: return ["crt/crt-lottes.slangp", "crt/crt-geom.slangp", "crt/zfast-crt.slangp", "crt/crt-easymode.slangp"]
        case .lcd: return ["handheld/lcd-grid-v2.slangp", "handheld/lcd3x.slangp", "handheld/lcd-grid.slangp"]
        case .sharp: return ["pixel-art-scaling/sharp-bilinear-simple.slangp", "pixel-art-scaling/sharp-bilinear.slangp", "interpolation/sharp-bilinear-simple.slangp"]
        }
    }
}

enum Shaders {
    static var url: URL { URL(string: "\(RetroArch.buildbot)/assets/frontend/shaders_slang.zip")! }
    static var dir: URL { RetroArch.support.appendingPathComponent("shaders") }
    static var slang: URL { dir.appendingPathComponent("slang") }
    static var installed: Bool { FileManager.default.fileExists(atPath: slang.appendingPathComponent("crt").path) }

    static func look(console c: String) -> RetroLook { RetroLook(rawValue: UserDefaults.standard.string(forKey: "look.console.\(c)") ?? "") ?? .off }
    static func setLook(_ l: RetroLook, console c: String) { UserDefaults.standard.set(l.rawValue, forKey: "look.console.\(c)") }
    // nil: the game follows its console
    static func own(_ r: Rom) -> RetroLook? { UserDefaults.standard.string(forKey: "look.game.\(r.id)").flatMap(RetroLook.init) }
    static func setOwn(_ l: RetroLook?, for r: Rom) { UserDefaults.standard.set(l?.rawValue, forKey: "look.game.\(r.id)") }
    static func look(_ r: Rom) -> RetroLook { own(r) ?? look(console: r.console) }

    static func preset(_ l: RetroLook) -> URL? {
        l.presets.lazy.map { slang.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func install(_ progress: @escaping (String, Double?) -> Void = { _, _ in }) throws {
        try unpack(url, into: slang, limit: 200 << 20, inner: "shaders_slang") { progress("Downloading retro looks…", $0) }
    }
}

// ---- controllers: libretro's controller profiles, so pads macOS doesn't know still work without setup ----
enum Pads {
    static var url: URL { URL(string: "\(RetroArch.buildbot)/assets/frontend/autoconfig.zip")! }
    static var dir: URL { RetroArch.support.appendingPathComponent("autoconfig") }
    static var installed: Bool { (try? FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty == false) ?? false }
    static func install() throws { try unpack(url, into: dir, limit: 50 << 20, inner: "autoconfig") { _ in } }

    // A game pad is plugged in that macOS's game controller support doesn't list (many generic USB pads):
    // RetroArch then reads pads itself and matches them to the profiles.
    static func unknownPadConnected() -> Bool {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let kinds = [kHIDUsage_GD_GamePad, kHIDUsage_GD_Joystick, kHIDUsage_GD_MultiAxisController].map { [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0] as CFDictionary }
        IOHIDManagerSetDeviceMatchingMultiple(m, kinds as CFArray)
        let hid = (IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>)?.count ?? 0
        let known = GCController.controllers().filter { $0.extendedGamepad != nil || $0.microGamepad != nil }.count
        return hid > known
    }
    static func lines() -> String {
        RetroArch.line("joypad_autoconfig_dir", dir.path) + RetroArch.line("input_autodetect_enable", "true")
            + RetroArch.line("input_joypad_driver", installed && unknownPadConnected() ? "hid" : "mfi")
    }
}

// A libretro asset zip, unpacked in place of what was there. Its files may sit in a folder named `inner`.
private func unpack(_ from: URL, into to: URL, limit: Int, inner: String, progress: @escaping (Double?) -> Void) throws {
    let fm = FileManager.default, parent = to.deletingLastPathComponent()
    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
    let work = parent.appendingPathComponent(".get-\(UUID().uuidString)"); try fm.createDirectory(at: work, withIntermediateDirectories: false); defer { try? fm.removeItem(at: work) }
    let zip = work.appendingPathComponent("a.zip"), out = work.appendingPathComponent("x")
    try RetroArch.download(from, to: zip, limit: limit, progress: progress)
    guard run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path], timeout: 600).code == 0 else { throw RetroError("The download couldn't be unpacked.") }
    let top = fm.fileExists(atPath: out.appendingPathComponent(inner).path) ? out.appendingPathComponent(inner) : out
    try? fm.removeItem(at: to); try fm.moveItem(at: top, to: to)
}
