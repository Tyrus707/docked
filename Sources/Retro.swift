import AppKit
import CryptoKit

// ---- RetroArch, inside Docked ----
// Docked doesn't carry RetroArch. The first time a game for another console is added, Docked downloads the official
// RetroArch from libretro's buildbot and keeps it in its own folder (~/Dockside/RetroArch), never in Applications.
// Each console's core is downloaded from the same place when it is first needed. Docked starts the game in that
// RetroArch with its own settings file, so the player never has to open RetroArch or set anything up there.
struct RetroError: LocalizedError { let text: String; init(_ t: String) { text = t }; var errorDescription: String? { text } }

// A file a core needs from the player's own console. Named ones must match the known dump exactly;
// a folder takes any dump of the right size (PlayStation 2 has too many versions to list).
struct Firmware { let file: String, md5: String, label: String }
struct Bios {
    var files: [Firmware] = []
    var folder: String?          // inside RetroArch's system folder
    var size = 0                 // what a dump for the folder must weigh
    var required = true          // false: the core can start without one, but games are better with it
    var onlyFor: [String] = []   // the file types that need it; empty is all of them
    var names: String { folder != nil ? "a BIOS file" : files.map { "\($0.file) (\($0.label))" }.joined(separator: " or ") }
}

enum RetroArch {
    // The reviewed release, and its download's SHA-256. A different file is refused.
    static let version = "1.22.2"
    static var dmgSHA = "81b79121ba26d539064ae13b4d0419a120c3d165afbe656cf5f5412b15fdb434"
    static var buildbot = "https://buildbot.libretro.com"
    static var home = Paths.root.appendingPathComponent("RetroArch")
    static var app = home.appendingPathComponent("RetroArch.app")
    static var support = home                     // its settings, cores, system files and saves
    static var old = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/RetroArch")   // a RetroArch the player had before
    static var installed: Bool { FileManager.default.isExecutableFile(atPath: app.path + "/Contents/MacOS/RetroArch") }
    static var installedVersion: String? { Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String }
    static var cores: URL { support.appendingPathComponent("cores") }
    static var system: URL { support.appendingPathComponent("system") }
    static var appURL: URL { URL(string: "\(buildbot)/stable/\(version)/apple/osx/universal/RetroArch_Metal.dmg")! }
    // Apple chip or Intel, whatever Docked itself is running as
    static var arch: String { var v: Int32 = 0, n = MemoryLayout<Int32>.size; return sysctlbyname("hw.optional.arm64", &v, &n, nil, 0) == 0 && v == 1 ? "arm64" : "x86_64" }
    static func coreURL(_ file: String) -> URL { URL(string: "\(buildbot)/nightly/apple/osx/\(arch)/latest/\(file)_libretro.dylib.zip")! }

    static func core(_ c: Console) -> URL? {
        c.cores.lazy.map { cores.appendingPathComponent("\($0.file)_libretro.dylib") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func ready(_ c: Console) -> Bool { installed && core(c) != nil }

    // ---- starting a game ----
    static var settings: URL { support.appendingPathComponent("retroarch.cfg") }
    static var docked: URL { support.appendingPathComponent("docked.cfg") }
    // Its own settings, then Docked's folders on top, so nothing the player changes in RetroArch can move them.
    static func arguments(core: URL, rom: String) -> [String] { ["--config", settings.path, "--appendconfig", docked.path, "-L", core.path, rom] }
    static func prepare() throws {
        let fm = FileManager.default
        for d in ["cores", "system", "saves", "states", "screenshots", "thumbnails"] { try fm.createDirectory(at: support.appendingPathComponent(d), withIntermediateDirectories: true) }
        if !fm.fileExists(atPath: settings.path) { try line("config_save_on_exit", "true").write(to: settings, atomically: true, encoding: .utf8) }
        let mine = line("libretro_directory", cores.path) + line("system_directory", system.path) + line("savefile_directory", support.appendingPathComponent("saves").path)
            + line("savestate_directory", support.appendingPathComponent("states").path) + line("screenshot_directory", support.appendingPathComponent("screenshots").path)
            + line("thumbnails_directory", support.appendingPathComponent("thumbnails").path) + line("quit_on_close_content", "2") + filling(screen())
        try mine.write(to: docked, atomically: true, encoding: .utf8)
    }
    static func line(_ k: String, _ v: String) -> String { "\(k) = \"\(v.replacingOccurrences(of: "\"", with: ""))\"\n" }
    // Games open in a window as big as the screen, like the green button with Option held: no Space of their own, and the
    // menu bar and Dock stay. RetroArch's own full screen on a Mac always takes a Space (video_windowed_fullscreen is not
    // used there), so it is a window placed over the screen instead. Control-Command-F or RetroArch's F key still gives full screen.
    static func filling(_ r: CGRect?) -> String {
        var s = line("video_fullscreen", "false")
        // RetroArch keeps the place as whole positive numbers; a screen left of or below the main one would not fit them.
        guard let r, r.minX >= 0, r.minY >= 0, r.width >= 320, r.height >= 240 else { return s }
        for (k, v) in [("video_window_save_positions", "true"), ("video_window_custom_size_enable", "true"), ("video_windowed_position_x", "\(Int(r.minX))"),
                       ("video_windowed_position_y", "\(Int(r.minY))"), ("video_windowed_position_width", "\(Int(r.width))"), ("video_windowed_position_height", "\(Int(r.height))")] { s += line(k, v) }
        return s
    }
    // The space inside RetroArch's window when it covers the screen Docked is on, title bar left out.
    static func screen() -> CGRect? {
        guard Thread.isMainThread else { return nil }   // set-up off the main thread; prepare() runs again on it just before a game starts
        guard let s = [NSScreen.main, NSScreen.screens.first].compactMap({ $0 }).first(where: { $0.visibleFrame.minX >= 0 && $0.visibleFrame.minY >= 0 }) else { return nil }
        return NSWindow.contentRect(forFrameRect: s.visibleFrame, styleMask: [.titled, .closable, .miniaturizable, .resizable])
    }
    // Only what the player has to fix themselves; everything else Docked sets up.
    static func problem(_ c: Console, rom: String) -> String? {
        if !FileManager.default.fileExists(atPath: rom) { return "The game's file can't be found. If it's on an external drive, connect it." }
        return nil
    }

    // Art already on this Mac: the player's own, beside the game, or downloaded by RetroArch (Docked's or one they had before).
    static func art(_ r: Rom) -> URL? {
        let u = URL(fileURLWithPath: r.path), base = u.deletingPathExtension()
        let mine = Paths.root.appendingPathComponent("Artwork/" + r.id.replacingOccurrences(of: ":", with: "-") + ".png")
        let name = base.lastPathComponent.replacingOccurrences(of: "[&*/:`<>?\\\\|\"]", with: "_", options: .regularExpression)
        let box = console(r.console).map { c in [support, old].map { $0.appendingPathComponent("thumbnails/\(c.folder)/Named_Boxarts/\(name).png") } } ?? []
        return ([mine, base.appendingPathExtension("png"), base.appendingPathExtension("jpg"), Lookup.artFile(r.id)] + box).first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // ---- system files from the player's own console ----
    static var bios: [String: Bios] = [
        "ps1": Bios(files: [Firmware(file: "scph5501.bin", md5: "490f666e1afb15b7362b406ed1cea246", label: "US"), Firmware(file: "scph5502.bin", md5: "32736f17079d0b2b7024407c39bd3050", label: "Europe"), Firmware(file: "scph5500.bin", md5: "8dd7d5296a650fac7319bce665a6a53c", label: "Japan")], required: false),
        "saturn": Bios(files: [Firmware(file: "mpr-17933.bin", md5: "3240872c70984b6cbfda1586cab68dbe", label: "US and Europe"), Firmware(file: "sega_101.bin", md5: "85ec9ca47d8f6807718151cbcca8b964", label: "Japan")]),
        "ps2": Bios(folder: "pcsx2/bios", size: 4 << 20),
        "pce": Bios(files: [Firmware(file: "syscard3.pce", md5: "38179df8f4ac870017db21ebcbf53114", label: "System Card 3.0")], onlyFor: ["cue", "chd", "m3u", "ccd"]),
    ]
    // What this game still needs, or nil
    static func missingBios(_ c: Console, rom: String) -> Bios? {
        guard let b = bios[c.id], b.onlyFor.isEmpty || b.onlyFor.contains((rom as NSString).pathExtension.lowercased()) else { return nil }
        return hasBios(c) ? nil : b
    }
    static func hasBios(_ c: Console) -> Bool {
        guard let b = bios[c.id] else { return true }
        let fm = FileManager.default
        if let f = b.folder { return ((try? fm.contentsOfDirectory(atPath: system.appendingPathComponent(f).path)) ?? []).contains { !$0.hasPrefix(".") } }
        return b.files.contains { fm.fileExists(atPath: system.appendingPathComponent($0.file).path) }
    }
    // Checks a file the player chose and keeps a copy where the core looks. Returns what it was.
    @discardableResult static func addBios(_ u: URL, for c: Console) throws -> String {
        guard let b = bios[c.id] else { throw RetroError("\(c.name) doesn't need a BIOS.") }
        let size = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0, size <= 32 << 20, let d = try? Data(contentsOf: u) else { throw RetroError("That isn't a \(c.name) BIOS. It needs \(b.names), copied from your own console.") }
        let fm = FileManager.default
        func keep(_ name: String, in dir: URL) throws { try fm.createDirectory(at: dir, withIntermediateDirectories: true); let to = dir.appendingPathComponent(name); try? fm.removeItem(at: to); try d.write(to: to, options: .atomic) }
        if let f = b.folder {
            guard d.count == b.size else { throw RetroError("That isn't a \(c.name) BIOS: a BIOS dumped from a \(c.name) is \(b.size >> 20) MB.") }
            let name = u.lastPathComponent.replacingOccurrences(of: "/", with: "_"); try keep(name.hasPrefix(".") ? "bios.bin" : name, in: system.appendingPathComponent(f)); return "the \(c.name) BIOS"
        }
        let md5 = Insecure.MD5.hash(data: d).map { String(format: "%02x", $0) }.joined()
        guard let m = b.files.first(where: { $0.md5 == md5 }) else { throw RetroError("That file isn't one Docked knows for \(c.name). It needs \(b.names), copied from your own console.") }
        try keep(m.file, in: system); return "the \(m.label) \(c.name) BIOS"
    }

    // ---- setting up ----
    // Everything a console needs: RetroArch once, then its core. Blocking; call it off the main thread.
    static func setUp(_ c: Console, progress: @escaping (String, Double?) -> Void = { _, _ in }) throws {
        if !installed { try installApp(progress) }
        try prepare()
        if core(c) == nil { try installCore(c, progress) }
    }
    static func installApp(_ progress: @escaping (String, Double?) -> Void = { _, _ in }) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let work = home.appendingPathComponent(".setup-\(UUID().uuidString)"); try fm.createDirectory(at: work, withIntermediateDirectories: false); defer { try? fm.removeItem(at: work) }
        let dmg = work.appendingPathComponent("RetroArch.dmg")
        try download(appURL, to: dmg, limit: 700 << 20) { progress("Downloading RetroArch \(version)…", $0) }
        progress("Checking RetroArch…", nil)
        guard sha256(dmg) == dmgSHA else { throw RetroError("The RetroArch download didn't match the reviewed version, so it wasn't used. Try again later.") }
        let mount = work.appendingPathComponent("disk"); try fm.createDirectory(at: mount, withIntermediateDirectories: false)
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path], timeout: 300).code == 0 else { throw RetroError("RetroArch's disk image couldn't be opened.") }
        let copy = work.appendingPathComponent("RetroArch.app")
        let copied = run("/usr/bin/ditto", [mount.appendingPathComponent("RetroArch.app").path, copy.path], timeout: 600).code == 0
        run("/usr/bin/hdiutil", ["detach", "-force", mount.path], timeout: 60)
        guard copied, fm.isExecutableFile(atPath: copy.path + "/Contents/MacOS/RetroArch") else { throw RetroError("RetroArch wasn't where it should be in the download.") }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", copy.path], timeout: 300).code == 0 else { throw RetroError("RetroArch's signature didn't check out, so it wasn't used.") }
        try? fm.removeItem(at: app); try fm.moveItem(at: copy, to: app)
        adoptOld()
    }
    // A RetroArch the player had before keeps going in Docked's: its saves, save states and system files are copied over, never moved.
    static func adoptOld() {
        let fm = FileManager.default
        for d in ["saves", "states", "system"] {
            let from = old.appendingPathComponent(d), to = support.appendingPathComponent(d)
            guard let e = fm.enumerator(at: from, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let f as URL in e where (try? f.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                let rel = String(f.standardizedFileURL.path.dropFirst(from.standardizedFileURL.path.count + 1)), dest = to.appendingPathComponent(rel)
                guard !fm.fileExists(atPath: dest.path) else { continue }
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true); try? fm.copyItem(at: f, to: dest)
            }
        }
    }
    // The best core libretro builds for this Mac; when one isn't built, the next.
    @discardableResult static func installCore(_ c: Console, _ progress: @escaping (String, Double?) -> Void = { _, _ in }) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: cores, withIntermediateDirectories: true)
        for (file, label) in c.cores {
            let work = cores.appendingPathComponent(".get-\(UUID().uuidString)"); try fm.createDirectory(at: work, withIntermediateDirectories: false); defer { try? fm.removeItem(at: work) }
            let zip = work.appendingPathComponent("core.zip")
            do { try download(coreURL(file), to: zip, limit: 300 << 20) { progress("Downloading the \(label) core for \(c.name)…", $0) } } catch let e as RetroError where e.text == notBuilt { continue }
            let out = work.appendingPathComponent("x"), name = "\(file)_libretro.dylib"
            guard run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path], timeout: 120).code == 0, fm.fileExists(atPath: out.appendingPathComponent(name).path) else { throw RetroError("The \(label) core for \(c.name) couldn't be unpacked.") }
            let to = cores.appendingPathComponent(name); try? fm.removeItem(at: to); try fm.moveItem(at: out.appendingPathComponent(name), to: to)
            return to
        }
        throw RetroError("libretro doesn't have a \(c.name) core for this Mac yet.")
    }

    // ---- downloading ----
    static let notBuilt = "Not on the buildbot"
    static func download(_ from: URL, to: URL, limit: Int, progress: @escaping (Double?) -> Void) throws {
        if from.isFileURL {   // a local copy, used by the tests
            guard FileManager.default.fileExists(atPath: from.path) else { throw RetroError(notBuilt) }
            try FileManager.default.copyItem(at: from, to: to); return
        }
        guard from.scheme == "https" else { throw RetroError("Docked only downloads over a secure connection.") }
        let g = Fetch(limit: limit, progress: progress), c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.timeoutIntervalForRequest = 60; c.timeoutIntervalForResource = 3600
        let s = URLSession(configuration: c, delegate: g, delegateQueue: nil); defer { s.invalidateAndCancel() }
        s.downloadTask(with: from).resume(); g.done.wait()
        if g.status == 404 { throw RetroError(notBuilt) }
        guard g.status == 200, let f = g.file, g.size <= limit else { throw RetroError(g.error ?? "The download didn't finish. Check your connection and try again.") }
        try FileManager.default.moveItem(at: f, to: to)
    }
    static func sha256(_ u: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: u) else { return "" }; defer { try? h.close() }
        var s = SHA256(); while let d = try? h.read(upToCount: 1 << 20), !d.isEmpty { s.update(data: d) }
        return s.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class Fetch: NSObject, URLSessionDownloadDelegate {
    let done = DispatchSemaphore(value: 0), limit: Int, progress: (Double?) -> Void
    var status = 0, size = 0, file: URL?, error: String?
    init(limit: Int, progress: @escaping (Double?) -> Void) { self.limit = limit; self.progress = progress }
    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        if w > limit { t.cancel(); error = "The download was larger than expected, so it was stopped." }
        progress(e > 0 ? Double(w) / Double(e) : nil)
    }
    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo l: URL) {
        status = (t.response as? HTTPURLResponse)?.statusCode ?? 0; size = (try? l.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("docked-\(UUID().uuidString)")
        if (try? FileManager.default.moveItem(at: l, to: keep)) != nil { file = keep }
    }
    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
        if status == 0 { status = (t.response as? HTTPURLResponse)?.statusCode ?? 0 }
        if let e, error == nil { error = e.localizedDescription }
        done.signal()
    }
}
