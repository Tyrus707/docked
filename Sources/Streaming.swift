import AppKit
import Combine
import Foundation

// Phase 1: Docked runs its own, private Sunshine and hands Moonlight a list of Docked links.
// Sunshine is downloaded only when TV streaming is first switched on, and is never put in Applications.

enum StreamingError: LocalizedError {
    case text(String)
    var errorDescription: String? {
        switch self { case .text(let t): return t }
    }
}

enum StreamingStatus: String {
    case stopped, installing, starting, running, error
    var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .installing: return "Getting ready"
        case .starting: return "Starting"
        case .running: return "Running"
        case .error: return "Error"
        }
    }
}

enum StreamingPaths {
    static var base: URL {
        ProcessInfo.processInfo.environment["DOCKED_STREAMING"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Docked/Streaming")
    }
    static var app: URL { base.appendingPathComponent("Sunshine.app", isDirectory: true) }
    static var executable: URL { app.appendingPathComponent("Contents/MacOS/Sunshine") }
    static var config: URL { base.appendingPathComponent("sunshine.conf") }
    static var apps: URL { base.appendingPathComponent("apps.json") }
    static var credentials: URL { base.appendingPathComponent("credentials.json") }
    static var log: URL { base.appendingPathComponent("sunshine.log") }
    static var state: URL { base.appendingPathComponent("sunshine_state.json") }
    static var art: URL { base.appendingPathComponent("Artwork") }
    static let port = 48089
    static var webUI: URL { URL(string: "https://127.0.0.1:\(port + 1)")! }
}

enum StreamingQuality: String, CaseIterable {
    case native, balanced, saver
    var label: String {
        switch self {
        case .native: return "Pixel-perfect"
        case .balanced: return "Balanced"
        case .saver: return "Data saver"
        }
    }
    var note: String {
        switch self {
        case .native: return "Let Moonlight ask for full detail. Best on Ethernet or fast 5 GHz Wi-Fi."
        case .balanced: return "A generous limit that still looks sharp on most TVs."
        case .saver: return "A smaller limit for slower Wi-Fi or a data cap."
        }
    }
    var maxBitrate: Int {
        switch self {
        case .native: return 0
        case .balanced: return 20000
        case .saver: return 8000
        }
    }
}

// Sunshine's own settings file. B-frames are not a setting here: its VideoToolbox path always sets max_b_frames to 0.
enum StreamingConfig {
    static func text(quality: StreamingQuality) -> String {
        """
        # Written by Docked. Change it in Settings › TV, not here.
        encoder = videotoolbox
        vt_realtime = enabled
        hevc_mode = 2
        av1_mode = 0
        max_bitrate = \(quality.maxBitrate)
        # Sunshine never uses B-frames with VideoToolbox, so there is nothing to turn on here.
        min_log_level = warning
        system_tray = disabled
        upnp = enabled
        origin_web_ui_allowed = lan
        port = \(StreamingPaths.port)
        file_apps = \(StreamingPaths.apps.path)
        credentials_file = \(StreamingPaths.credentials.path)
        log_path = \(StreamingPaths.log.path)
        # Its own identity, paired devices and certificate. Left out, they'd be shared with a Sunshine the player already runs.
        sunshine_name = Docked
        file_state = \(StreamingPaths.state.path)
        pkey = \(StreamingPaths.base.appendingPathComponent("credentials/cakey.pem").path)
        cert = \(StreamingPaths.base.appendingPathComponent("credentials/cacert.pem").path)
        """
    }
}

// Sunshine requires both "env" and "apps". Every app opens a docked:// link, so play time still counts.
struct StreamingAppEntry: Codable, Equatable {
    var name: String
    var cmd: String
    var imagePath: String?
    var workingDir: String?
    var autoDetach: Bool   // `open` returns at once; this tells Sunshine the game is still running
    var output: String?

    enum CodingKeys: String, CodingKey {
        case name, cmd, output
        case autoDetach = "auto-detach"
        case imagePath = "image-path"
        case workingDir = "working-dir"
    }
}

struct StreamingAppList: Codable, Equatable {
    var env: [String: String]
    var apps: [StreamingAppEntry]
}

enum StreamingApps {
    static let couchName = "Couch Mode"

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func open(_ link: String) -> String { "/usr/bin/open " + quote(link) }

    static func make(games: [Game], imageFor: (Game) -> URL?) -> StreamingAppList {
        var list = [StreamingAppEntry(name: couchName, cmd: open("docked://couch"), imagePath: nil,
                                      workingDir: nil, autoDetach: true, output: nil)]
        for g in games where !g.missing && g.away == nil {
            list.append(StreamingAppEntry(name: g.name, cmd: open(DockedLink.play(g.titleID)),
                                          imagePath: imageFor(g)?.path, workingDir: nil, autoDetach: true, output: nil))
        }
        return StreamingAppList(env: [:], apps: list)
    }

    // Cover art is copied into Sunshine's own folder as a real PNG, never linked from the library.
    // Sunshine reads this file again each time Moonlight asks for the list, so it never needs a restart.
    @discardableResult static func write(games: [Game]) throws -> StreamingAppList {
        try FileManager.default.createDirectory(at: StreamingPaths.art, withIntermediateDirectories: true)
        var pictures: [String: URL] = [:]
        for g in games where !g.missing && g.away == nil {
            if let u = StreamingArt.png(for: g) { pictures[g.id] = u }
        }
        let list = make(games: games) { pictures[$0.id] }
        let j = JSONEncoder(); j.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try j.encode(list)
        if (try? Data(contentsOf: StreamingPaths.apps)) != data { try data.write(to: StreamingPaths.apps, options: .atomic) }
        return list
    }
}

enum StreamingArt {
    // The best picture already on this Mac, not a new download. Anything Sunshine is given must be a PNG.
    static func source(_ g: Game) -> URL? {
        let fm = FileManager.default
        let chosen = Artwork.yours.appendingPathComponent(artStem(g.id) + ".png")
        var choices: [URL?] = [chosen, Lookup.artFile(g.titleID), Artwork.appIcon(g.id)]
        if let r = g.rom { choices.insert(RetroArch.art(r), at: 1) }
        choices.append(g.url.appendingPathComponent("Contents/Resources/AppIcon.icns"))
        return choices.compactMap { $0 }.first { fm.fileExists(atPath: $0.path) }
    }

    // Made again only when the picture behind it is newer: a big library would otherwise redo every cover on each change.
    static func png(for g: Game) -> URL? {
        let to = StreamingPaths.art.appendingPathComponent(artStem(g.id) + ".png")
        guard let from = source(g) else { return nil }
        if let made = modified(to), let src = modified(from), made >= src { return to }
        guard let image = NSImage(contentsOf: from),
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        guard (try? data.write(to: to, options: .atomic)) != nil else { return nil }
        return to
    }

    private static func modified(_ u: URL) -> Date? { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
}

enum StreamingFiles {
    static func prepare(quality: StreamingQuality, games: [Game]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: StreamingPaths.base.appendingPathComponent("credentials"), withIntermediateDirectories: true)
        try StreamingApps.write(games: games)
        try Data(StreamingConfig.text(quality: quality).utf8).write(to: StreamingPaths.config, options: .atomic)
    }
}

// Sunshine's own Web UI password. Only the hash it makes lives in its config folder; the pair we use is in the Keychain.
enum StreamingCredentials {
    static let service = "Docked TV Streaming"
    static func ensure() -> (user: String, password: String) {
        func kept(_ account: String, _ make: () -> String) -> String {
            if let v = Keychain.string(service: service, account: account) { return v }
            let v = make(); Keychain.set(v, service: service, account: account); return v
        }
        let hex = { UUID().uuidString.replacingOccurrences(of: "-", with: "") }
        return (kept("user") { "docked-" + hex() }, kept("password") { hex() + hex() })
    }
}

final class Streaming: ObservableObject {
    @Published var on = UserDefaults.standard.bool(forKey: "streaming.on") {
        didSet { UserDefaults.standard.set(on, forKey: "streaming.on") }
    }
    @Published var quality = StreamingQuality(rawValue: UserDefaults.standard.string(forKey: "streaming.quality") ?? "") ?? .balanced {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "streaming.quality") }
    }
    @Published private(set) var status: StreamingStatus = .stopped
    @Published private(set) var detail = "Off"
    @Published private(set) var installProgress: Double?
    @Published private(set) var pairings: [StreamingPairing] = []
    @Published private(set) var clients: [StreamingClient] = []
    @Published var notice = ""
    @Published private(set) var permissionTick = 0
    @Published private(set) var welcomeSeen = UserDefaults.standard.bool(forKey: "streaming.welcome")

    private let supervisor = SunshineSupervisor()
    private let work = DispatchQueue(label: "tv-streaming", qos: .utility)
    private var appsWork: DispatchWorkItem?
    private var games: [Game] = []
    private var starting = false
    private var generation = 0

    init() {
        supervisor.onState = { [weak self] state, detail in
            DispatchQueue.main.async { self?.status = state; self?.detail = detail }
        }
        supervisor.onGiveUp = { [weak self] reason in
            DispatchQueue.main.async {
                guard let self else { return }
                self.on = false
                self.status = .error
                self.detail = "Sunshine kept stopping, so Docked left it off. \(reason)"
                self.notice = "Try the switch again. The log is in \(StreamingPaths.log.path)."
            }
        }
    }

    func enable(_ value: Bool) {
        on = value
        if value {
            if !welcomeSeen {
                welcomeSeen = true
                UserDefaults.standard.set(true, forKey: "streaming.welcome")
            }
            start()
        } else { stop() }
    }

    func setQuality(_ q: StreamingQuality) {
        guard q != quality else { return }
        quality = q
        if on { restart() }
    }

    func start() {
        guard !starting, !supervisor.running else { return }
        starting = true
        generation += 1
        let token = generation, games = self.games, quality = self.quality   // read here, on the main thread
        say("Getting Sunshine ready…", status: .installing)
        work.async { [weak self] in
            guard let self else { return }
            do {
                let app = try StreamingInstall.ensure { [weak self] what, fraction in
                    DispatchQueue.main.async {
                        guard self?.generation == token else { return }
                        self?.detail = what
                        self?.installProgress = fraction
                    }
                }
                self.finishStart(app: app, token: token, games: games, quality: quality)
            } catch { self.fail(error.localizedDescription, token: token) }
        }
    }

    private func finishStart(app: URL, token: Int, games: [Game], quality: StreamingQuality) {
        do {
            let exe = app.appendingPathComponent("Contents/MacOS/Sunshine")
            guard FileManager.default.isExecutableFile(atPath: exe.path) else {
                throw StreamingError.text("Sunshine wasn't where Docked expected it.")
            }
            say("Writing TV settings…", status: .installing)
            try StreamingFiles.prepare(quality: quality, games: games)
            let c = StreamingCredentials.ensure()
            let r = run(exe.path, [StreamingPaths.config.path, "--creds", c.user, c.password], timeout: 30)
            guard r.code == 0 else { throw StreamingError.text("Sunshine wouldn't accept its settings. Try again in a moment.") }
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.installProgress = nil
                self.supervisor.executable = exe
                self.supervisor.start()
                self.starting = false
            }
        } catch { fail(error.localizedDescription, token: token) }
    }

    func stop() {
        generation += 1
        starting = false
        installProgress = nil
        supervisor.stop()
    }

    func restart() { stop(); start() }

    func libraryChanged(_ games: [Game]) {
        self.games = games
        appsWork?.cancel()
        guard on else { return }   // nothing to keep up to date, and no covers to make, while streaming is off
        let w = DispatchWorkItem { [weak self] in
            do { try StreamingApps.write(games: games) }   // no restart: it would end a stream that's playing
            catch { self?.say("The TV app list wasn't saved: \(error.localizedDescription)", status: .error) }
        }
        appsWork = w
        work.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    // Sunshine's UI says "Allow" for a pairing request; Moonlight shows a four-digit PIN.
    func refreshPairings() {
        work.async { [weak self] in
            guard let self else { return }
            do {
                let c = StreamingCredentials.ensure()
                let found = try StreamingAPI.pairings(user: c.user, password: c.password)
                DispatchQueue.main.async { self.pairings = found }
            } catch { self.say("Couldn't see pairing requests: \(error.localizedDescription)", status: nil) }
        }
    }

    func refreshClients() {
        work.async { [weak self] in
            guard let self else { return }
            do {
                let c = StreamingCredentials.ensure()
                let found = try StreamingAPI.clients(user: c.user, password: c.password)
                DispatchQueue.main.async { self.clients = found }
            } catch { self.say("Couldn't see paired devices: \(error.localizedDescription)", status: nil) }
        }
    }

    func pair(_ pairing: StreamingPairing, pin: String) {
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else { say("The PIN is four digits, as Moonlight shows.", status: nil); return }
        work.async { [weak self] in
            guard let self else { return }
            do {
                let c = StreamingCredentials.ensure()
                guard try StreamingAPI.pair(user: c.user, password: c.password, pairing: pairing, pin: pin) else {
                    self.say("Moonlight didn't finish pairing. Check the PIN and try again.", status: nil); return
                }
                DispatchQueue.main.async { self.notice = "\(pairing.name) is paired. It can now play your games." }
                self.refreshClients(); self.refreshPairings()
            } catch { self.say("Pairing didn't finish: \(error.localizedDescription)", status: nil) }
        }
    }

    func unpair(_ client: StreamingClient) {
        work.async { [weak self] in
            guard let self else { return }
            do {
                let c = StreamingCredentials.ensure()
                _ = try StreamingAPI.unpair(user: c.user, password: c.password, uuid: client.uuid)
                DispatchQueue.main.async { self.notice = "\(client.name) was removed." }
                self.refreshClients()
            } catch { self.say("Couldn't remove \(client.name): \(error.localizedDescription)", status: nil) }
        }
    }

    func permissionsChanged() { DispatchQueue.main.async { self.permissionTick &+= 1 } }

    private func say(_ text: String, status: StreamingStatus?) {
        DispatchQueue.main.async {
            if let status { self.status = status }
            self.detail = text
            self.installProgress = nil
        }
    }

    private func fail(_ text: String, token: Int? = nil) {
        DispatchQueue.main.async {
            guard token == nil || self.generation == token else { return }
            self.starting = false
            self.on = false
            self.status = .error
            self.detail = text
            self.installProgress = nil
        }
    }
}
