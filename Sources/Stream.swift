import AppKit
import Foundation

// Play on any screen: a TV, iPad, Apple TV or another Mac shows the game through Moonlight, which the player already knows.
// Docked runs Sunshine (GPL, LizardByte) in the background with its own settings, in Application Support/Docked/Streaming, never as an app of its own.
// Moonlight lists Couch Mode and every game; picking one opens it here through a docked:// link, so the game starts the way it does on the Mac.
enum Stream {
    static var folder: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOCKED_STREAM"] ?? NSHomeDirectory() + "/Library/Application Support/Docked/Streaming") }
    static var config: URL { folder.appendingPathComponent("sunshine.conf") }
    static var apps: URL { folder.appendingPathComponent("apps.json") }
    static var covers: URL { folder.appendingPathComponent("Covers") }
    static var ownCopy: URL { folder.appendingPathComponent("Sunshine.app") }
    static let webPort = 47990   // Sunshine's base port 47989, plus one

    // The picture the player prefers. Moonlight picks the resolution, frame rate and bitrate on the TV; this is the Mac's half.
    enum Picture: String, CaseIterable { case smooth, sharp
        var name: String { self == .smooth ? "Smoothest" : "Sharpest" }
        var realtime: Bool { self == .smooth }   // VideoToolbox's real-time mode: frames never wait for a better encode
    }
    static var picture: Picture {
        get { Picture(rawValue: UserDefaults.standard.string(forKey: "stream.picture") ?? "") ?? .smooth }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "stream.picture") }
    }
    static var wanted: Bool { get { UserDefaults.standard.bool(forKey: "stream.on") } set { UserDefaults.standard.set(newValue, forKey: "stream.on") } }
    static var screenName: String { Host.current().localizedName ?? "Docked" }

    // Sunshine: Docked's own copy first, then one the player installed (the app, or Homebrew)
    static func sunshine(fm: FileManager = .default, places: [String]? = nil) -> URL? {
        let l = places ?? [ownCopy.appendingPathComponent("Contents/MacOS/sunshine").path, "/Applications/Sunshine.app/Contents/MacOS/sunshine",
                           NSHomeDirectory() + "/Applications/Sunshine.app/Contents/MacOS/sunshine", "/opt/homebrew/bin/sunshine", "/usr/local/bin/sunshine"]
        return l.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    // Sunshine's settings, all inside Docked's folder so the player's own Sunshine setup is never touched
    static func configText(name: String, folder f: URL, picture p: Picture) -> String {
        let clean = name.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }.prefix(40)
        return [
            "sunshine_name = \(clean.isEmpty ? "Docked" : String(clean))",
            "file_apps = \(f.appendingPathComponent("apps.json").path)",
            "credentials_file = \(f.appendingPathComponent("credentials.json").path)",
            "file_state = \(f.appendingPathComponent("state.json").path)",
            "log_path = \(f.appendingPathComponent("sunshine.log").path)",
            "pkey = \(f.appendingPathComponent("key.pem").path)",
            "cert = \(f.appendingPathComponent("cert.pem").path)",
            "origin_web_ui_allowed = pc",   // its own settings page answers this Mac only; Docked is the settings page
            "upnp = disabled",              // in the house only: nothing opens on the router
            "encoder = videotoolbox",
            "vt_software = disabled",       // the Mac's media engine or nothing: software encoding can't keep up
            "vt_realtime = \(p.realtime ? "enabled" : "disabled")",
            "min_log_level = info",
        ].joined(separator: "\n") + "\n"
    }

    // What Moonlight lists: Couch Mode first, for choosing on the TV with a controller, then each game that can play now
    static func appList(_ games: [Game], cover: (Game) -> URL?) -> Data {
        func open(_ link: String) -> [String] { ["/usr/bin/open", link] }
        var list: [[String: Any]] = [["name": "Couch Mode", "detached": [open("docked://couch").joined(separator: " ")]]]
        for g in games where g.cannot == nil {
            var a: [String: Any] = ["name": String(g.name.prefix(80)), "detached": [open(DockedLink.play(g.titleID)).joined(separator: " ")]]
            if let c = cover(g) { a["image-path"] = c.path }
            list.append(a)
        }
        return (try? JSONSerialization.data(withJSONObject: ["env": [String: String](), "apps": list], options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // A PIN Moonlight shows when pairing: four digits
    static func validPIN(_ s: String) -> Bool { s.count == 4 && s.allSatisfy(\.isASCIIDigit) }

    // The sign-in Docked uses to talk to its Sunshine, made once and readable by this player only
    static func login(fm: FileManager = .default) -> (user: String, pass: String) {
        let u = folder.appendingPathComponent("login")
        if let t = try? String(contentsOf: u, encoding: .utf8), let i = t.firstIndex(of: ":") { return (String(t[..<i]), String(t[t.index(after: i)...]).trimmingCharacters(in: .whitespacesAndNewlines)) }
        let pass = (0..<24).map { _ in String("abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()!) }.joined()
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        fm.createFile(atPath: u.path, contents: Data("docked:\(pass)".utf8), attributes: [.posixPermissions: 0o600])
        return ("docked", pass)
    }

    // Is something already answering on Sunshine's port: usually the player's own Sunshine, which would take the TV first
    static func portBusy(_ port: UInt16 = 47989) -> Bool {
        let s = socket(AF_INET, SOCK_STREAM, 0); guard s >= 0 else { return false }; defer { close(s) }
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_port = port.bigEndian; a.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 } }
    }
}

extension Character { var isASCIIDigit: Bool { isASCII && isNumber } }

// The running Sunshine: started when the player turns TV streaming on (and with Docked after that), stopped when Docked quits.
final class Streamer {
    static let shared = Streamer()
    private var p: Process?
    var running: Bool { p?.isRunning == true }

    // Writes the settings and the game list, then starts Sunshine. Throws with words the player can act on.
    func start(games: [Game], tile: @escaping (Game) -> NSImage) throws {
        guard !running else { refresh(games: games, tile: tile); return }
        guard let exe = Stream.sunshine() else { throw RetroError("Docked needs Sunshine to stream. Choose Get Sunshine, or install it from lizardbyte.dev.") }
        guard !Stream.portBusy() else { throw RetroError("Another Sunshine is already running on this Mac. Quit it (its menu bar icon, or Activity Monitor), then turn TV streaming on again.") }
        let fm = FileManager.default
        try fm.createDirectory(at: Stream.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Stream.configText(name: Stream.screenName, folder: Stream.folder, picture: Stream.picture).write(to: Stream.config, atomically: true, encoding: .utf8)
        refresh(games: games, tile: tile)
        let l = Stream.login()
        // The sign-in is set before the first start, and again if the file went missing
        if !fm.fileExists(atPath: Stream.folder.appendingPathComponent("credentials.json").path) {
            let c = Process(); c.executableURL = exe; c.arguments = [Stream.config.path, "--creds", l.user, l.pass]
            c.standardOutput = FileHandle.nullDevice; c.standardError = FileHandle.nullDevice
            try c.run(); c.waitUntilExit()
        }
        let s = Process(); s.executableURL = exe; s.arguments = [Stream.config.path]; s.currentDirectoryURL = Stream.folder
        s.standardOutput = FileHandle.nullDevice; s.standardError = FileHandle.nullDevice
        s.qualityOfService = .userInteractive   // encoding sits between the game and the TV: it must never wait
        try s.run(); p = s
    }
    func stop() { p?.terminate(); p = nil }

    // The list Moonlight shows follows the library; Sunshine reads it each time Moonlight asks
    func refresh(games: [Game], tile: (Game) -> NSImage) {
        let fm = FileManager.default
        try? fm.createDirectory(at: Stream.covers, withIntermediateDirectories: true)
        let d = Stream.appList(games) { g in
            let u = Stream.covers.appendingPathComponent(artStem(g.titleID) + ".png")
            if fm.fileExists(atPath: u.path) { return u }
            let i = tile(g)
            guard let t = i.tiffRepresentation, let b = NSBitmapImageRep(data: t), let png = b.representation(using: .png, properties: [:]), (try? png.write(to: u)) != nil else { return nil }
            return u
        }
        try? d.write(to: Stream.apps, options: .atomic)
    }

    // Moonlight shows a PIN on the TV; typed here, it pairs that screen with this Mac
    func pair(pin: String, screen: String, done: @escaping (String?) -> Void) {
        guard Stream.validPIN(pin) else { done("The PIN is the four digits Moonlight shows."); return }
        guard running, let u = URL(string: "https://localhost:\(Stream.webPort)/api/pin") else { done("Turn TV streaming on first."); return }
        let l = Stream.login()
        var r = URLRequest(url: u, timeoutInterval: 10); r.httpMethod = "POST"
        r.setValue("Basic " + Data("\(l.user):\(l.pass)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["pin": pin, "name": String(screen.prefix(40))])
        Local.session.dataTask(with: r) { d, resp, e in
            let body = d.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200 && body.replacingOccurrences(of: " ", with: "").contains("\"status\":true")
            DispatchQueue.main.async { done(ok ? nil : e != nil ? "Docked couldn't reach its streaming service. Turn TV streaming off and on again." : "That PIN didn't work. Start pairing again in Moonlight and type the new PIN.") }
        }.resume()
    }

    // Sunshine's own certificate is made on this Mac, so it is trusted for localhost only
    private final class Local: NSObject, URLSessionDelegate {
        static let session = URLSession(configuration: .ephemeral, delegate: Local(), delegateQueue: nil)
        func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if c.protectionSpace.host == "localhost", c.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let t = c.protectionSpace.serverTrust { completionHandler(.useCredential, URLCredential(trust: t)) } else { completionHandler(.performDefaultHandling, nil) }
        }
    }

    // Docked's own copy of Sunshine, from LizardByte's newest release on GitHub, kept inside Docked
    func download(progress: @escaping (String) -> Void, done: @escaping (String?) -> Void) {
        let api = URL(string: "https://api.github.com/repos/LizardByte/Sunshine/releases/latest")!
        URLSession.shared.dataTask(with: api) { d, _, _ in
            let assets = (d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["assets"] as? [[String: Any]]) ?? []
            let dmgs = assets.compactMap { a -> (String, URL)? in guard let n = a["name"] as? String, n.lowercased().hasSuffix(".dmg"), let s = a["browser_download_url"] as? String, let u = URL(string: s) else { return nil }; return (n.lowercased(), u) }
            #if arch(arm64)
            let mine = dmgs.first { $0.0.contains("arm64") || $0.0.contains("aarch64") } ?? dmgs.first { !$0.0.contains("x86_64") && !$0.0.contains("intel") }
            #else
            let mine = dmgs.first { $0.0.contains("x86_64") || $0.0.contains("intel") } ?? dmgs.first { !$0.0.contains("arm64") }
            #endif
            guard let url = mine?.1 else { DispatchQueue.main.async { done("Sunshine's newest release has no Mac download. Install it with Homebrew (brew install lizardbyte/homebrew/sunshine), then turn TV streaming on.") }; return }
            DispatchQueue.main.async { progress("Downloading Sunshine…") }
            URLSession.shared.downloadTask(with: url) { file, _, e in
                let r = Result { () throws -> Void in
                    guard let file else { throw RetroError("Sunshine didn't download. Check the internet connection and try again.") }
                    try Self.install(dmg: file)
                }
                DispatchQueue.main.async { if case let .failure(x) = r { done(x.localizedDescription) } else { done(nil) } }
            }.resume()
        }.resume()
    }
    private static func install(dmg: URL) throws {
        let fm = FileManager.default, mount = fm.temporaryDirectory.appendingPathComponent("docked-sunshine-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        func run(_ a: [String]) throws { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil"); p.arguments = a; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; try p.run(); p.waitUntilExit(); if p.terminationStatus != 0 { throw RetroError("The Sunshine download couldn't be opened.") } }
        try run(["attach", "-quiet", "-nobrowse", "-readonly", "-mountpoint", mount.path, dmg.path])
        defer { try? run(["detach", "-quiet", "-force", mount.path]); try? fm.removeItem(at: mount) }
        guard let app = (try? fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil))?.first(where: { $0.pathExtension == "app" }) else { throw RetroError("The Sunshine download had no app in it.") }
        try fm.createDirectory(at: Stream.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tmp = Stream.folder.appendingPathComponent("Sunshine.app.new"); try? fm.removeItem(at: tmp)
        try fm.copyItem(at: app, to: tmp)
        // Its own executable may carry another name: Docked looks for Contents/MacOS/sunshine
        let macos = tmp.appendingPathComponent("Contents/MacOS")
        if !fm.isExecutableFile(atPath: macos.appendingPathComponent("sunshine").path), let exe = (try? fm.contentsOfDirectory(atPath: macos.path))?.first(where: { $0.lowercased().hasPrefix("sunshine") }) {
            try fm.createSymbolicLink(atPath: macos.appendingPathComponent("sunshine").path, withDestinationPath: exe)
        }
        try? fm.removeItem(at: Stream.ownCopy); try fm.moveItem(at: tmp, to: Stream.ownCopy)
        let x = Process(); x.executableURL = URL(fileURLWithPath: "/usr/bin/xattr"); x.arguments = ["-dr", "com.apple.quarantine", Stream.ownCopy.path]; try? x.run(); x.waitUntilExit()
    }
}
