import Foundation

// Where everything lives. The engine's build tools cannot handle spaces in paths, so this is ~/Docked.
enum Paths {
    static let root: URL = ProcessInfo.processInfo.environment["DOCKED_ROOT"].map { URL(fileURLWithPath: $0) } ?? home(URL(fileURLWithPath: NSHomeDirectory()))
    // Up to 1.4 the folder was called Dockside. It is renamed once, whole, and a hidden link keeps its old name working: games and build folders hold full paths.
    // Nothing is ever merged or replaced: if there is already something called Docked, or the rename is refused, the old folder stays in use.
    static func home(_ h: URL) -> URL {
        let new = h.appendingPathComponent("Docked", isDirectory: true), old = h.appendingPathComponent("Dockside", isDirectory: true)
        var s = stat(); guard lstat(old.path, &s) == 0, s.st_mode & S_IFMT == S_IFDIR else {
            if lstat(old.path, &s) != 0, lstat(new.path, &s) == 0, s.st_mode & S_IFMT == S_IFDIR, isOurs(new) { link(old, new) }   // cut short between the two steps
            return new
        }
        try? Data().write(to: old.appendingPathComponent(renamedMark))   // first, so a rename cut short is known for what it is
        guard renamex_np(old.path, new.path, UInt32(RENAME_EXCL)) == 0 else { return old }
        link(old, new); return new
    }
    private static func isOurs(_ d: URL) -> Bool { FileManager.default.fileExists(atPath: d.appendingPathComponent(renamedMark).path) }
    private static let renamedMark = ".renamed-from-dockside"
    private static func link(_ old: URL, _ new: URL) { if symlink("Docked", old.path) == 0 { lchflags(old.path, UInt32(UF_HIDDEN)) } }
    // A saved path that starts in the folder's old name, as it is now
    static func now(_ path: String, root: URL = Paths.root, home: String = NSHomeDirectory()) -> String {
        let old = home + "/Dockside"; guard root.path == home + "/Docked", path == old || path.hasPrefix(old + "/") else { return path }
        return root.path + path.dropFirst(old.count)
    }
    // The tools the app carries, once unpacked; else a separate setup's.
    static var tools: URL { root.appendingPathComponent("tools") }
    // The engine Docked was built with, or a signed engine update (Engine.swift).
    static var unpacked: Bool { Engine.active != nil }
    static var engine: URL { unpacked ? tools.appendingPathComponent("engine") : root.appendingPathComponent("engine") }
    static var script: URL { engine.appendingPathComponent("scripts/build_ipa_from_nsp.py") }
    static var python: URL { unpacked ? tools.appendingPathComponent("bin/python3") : root.appendingPathComponent("venv/bin/python3") }
    static var games: URL { root.appendingPathComponent("Games") }
    static var inputs: URL { root.appendingPathComponent("Inputs") }
    static let xcode = "/Applications/Xcode.app/Contents/Developer"
}

// The exact engine version that was reviewed, as in ENGINE_PIN (build.sh checks they agree). The app runs no other, unless it comes as an engine update signed by Docked's maker.
let pinnedEngine = "35fea5c2ee781689ff224e614a8da71867a571bf"
let pinnedEngineDate = "2026-11-26T16:33:44Z"
// The engine in use: the one above, or a newer signed one.
var activeEngine: String { Engine.active?.commit ?? pinnedEngine }
let requiredXcode = "27.2"

// MARK: - Engine events (one JSON object per line)

enum EngineEvent: Equatable {
    case stage(k: Int, n: Int, name: String)
    case step(String)
    case progress(frac: Double?, eta: Double?, note: String)
    case stageEnd(ok: Bool, warn: Bool, name: String, summary: String)   // warn: the step finished without what it makes
    case game(titleID: String, name: String, out: String?)
    case say(String)

    static func parse(_ line: String) -> EngineEvent? {
        guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let ev = o["ev"] as? String else { return nil }
        func s(_ k: String) -> String { o[k] as? String ?? "" }
        func d(_ k: String) -> Double? { (o[k] as? NSNumber)?.doubleValue }
        switch ev {
        case "stage": return .stage(k: Int(d("k") ?? 0), n: Int(d("n") ?? 0), name: s("name"))
        case "step": return .step(s("step"))
        case "progress": return .progress(frac: d("frac"), eta: d("eta"), note: s("note"))
        case "stage_end": return .stageEnd(ok: o["ok"] as? Bool ?? true, warn: o["warn"] as? Bool ?? false, name: s("name"), summary: s("summary"))
        case "game": return .game(titleID: s("title_id"), name: s("name"), out: o["out"] as? String)
        case "say": return .say(s("msg"))
        default: return nil
        }
    }
}

// Splits a byte stream into lines, holding back a partial last line (also mid-character).
struct LineBuffer {
    private var data = Data()
    mutating func append(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let i = data.firstIndex(of: 10) {
            lines.append(String(decoding: data[data.startIndex..<i], as: UTF8.self))
            data.removeSubrange(data.startIndex...i)
        }
        return lines
    }
}

// MARK: - Choosing what to build

struct BuildInput: Equatable {
    var path: URL          // what the engine is given
    var key: String        // names this build's folder
    var title: String      // shown until the engine reports the real name
    var needsKeys: Bool
    var bytes: Int64
}

enum InputError: LocalizedError, Equatable {
    case unsupported, mixed, missing
    var errorDescription: String? {
        switch self {
        case .unsupported: return "That isn't a game dump this app can read. Add .nsp, .xci, .nsz, .xcz or .nup files, or a dump folder."
        case .mixed: return "Add one game at a time: either its .nsp/.xci files together, one .nup file, or one folder."
        case .missing: return "That file or folder can't be found."
        }
    }
}

let packageTypes: Set<String> = ["nsp", "xci", "nsz", "xcz"]

func folderSize(_ url: URL) -> Int64 {
    let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
    if let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { return Int64(v.fileSize ?? 0) }
    var total: Int64 = 0
    guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
    for case let f as URL in e { total += Int64((try? f.resourceValues(forKeys: Set(keys)))?.fileSize ?? 0) }
    return total
}

// A folder-safe, stable name: readable part plus a short hash of the input.
func buildKey(_ urls: [URL]) -> String {
    let name = urls[0].deletingPathExtension().lastPathComponent
    let safe = String(name.unicodeScalars.filter { $0.isASCII && CharacterSet.alphanumerics.contains($0) }.map(Character.init)).prefix(32)
    var h: UInt64 = 0xcbf29ce484222325
    for b in urls.map(\.path).sorted().joined(separator: "\n").utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return (safe.isEmpty ? "game" : String(safe)) + "-" + String(h, radix: 16)
}

func resolveInput(_ urls: [URL], family: String? = nil, inputsRoot: URL = Paths.inputs) throws -> BuildInput {
    let fm = FileManager.default
    guard let first = urls.first else { throw InputError.unsupported }
    for u in urls where !fm.fileExists(atPath: u.path) { throw InputError.missing }
    let key = family.map { buildFolderKey($0) } ?? buildKey(urls), title = first.deletingPathExtension().lastPathComponent
    let bytes = urls.reduce(0) { $0 + folderSize($1) }
    var isDir: ObjCBool = false
    _ = fm.fileExists(atPath: first.path, isDirectory: &isDir)

    if isDir.boolValue {
        guard urls.count == 1 else { throw InputError.mixed }
        let items = (try? fm.contentsOfDirectory(at: first, includingPropertiesForKeys: nil)) ?? []
        let exts = Set(items.map { $0.pathExtension.lowercased() })
        let packages = !exts.isDisjoint(with: packageTypes)
        let dump = items.contains { ["base", "updates", "exefs"].contains($0.lastPathComponent) }
        guard packages || dump || exts.contains("nup") else { throw InputError.unsupported }
        return BuildInput(path: first, key: key, title: first.lastPathComponent, needsKeys: packages, bytes: bytes)
    }
    if first.pathExtension.lowercased() == "nup" {
        guard urls.count == 1 else { throw InputError.mixed }
        return BuildInput(path: first, key: key, title: title, needsKeys: false, bytes: bytes)
    }
    let good = urls.filter { packageTypes.contains($0.pathExtension.lowercased()) }
    guard !good.isEmpty else { throw InputError.unsupported }
    guard good.count == urls.count else { throw InputError.mixed }
    // Loose files: link just these into a folder of their own, so nothing else beside them (a Downloads folder) is read.
    // Hard links cost no space; other disks get symbolic links. The originals are never changed.
    let stage = inputsRoot.appendingPathComponent(key, isDirectory: true)
    // Made beside the old folder and swapped in only when complete: the chosen files may be the old folder's own,
    // and it may hold the last copy if the originals were deleted.
    let fresh = inputsRoot.appendingPathComponent(key + ".new", isDirectory: true)
    try? fm.removeItem(at: fresh)
    try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
    do {
        for u in good {
            let to = fresh.appendingPathComponent(u.lastPathComponent)
            do { try fm.linkItem(at: u, to: to) } catch { try fm.createSymbolicLink(at: to, withDestinationURL: u) }
        }
    } catch { try? fm.removeItem(at: fresh); throw error }
    if fm.fileExists(atPath: stage.path) { _ = try fm.replaceItemAt(stage, withItemAt: fresh) } else { try fm.moveItem(at: fresh, to: stage) }
    return BuildInput(path: stage, key: key, title: title, needsKeys: true, bytes: bytes)
}

func buildArguments(_ input: BuildInput, keys: String?, quick: Bool = false, phone out: URL? = nil, xcode: XcodeBuild? = nil) -> [String] {
    var a = ["-u", Paths.script.path, input.path.path, "--platform", out == nil && xcode == nil ? "mac-app" : "ios", "--progress", "json",
             "--work-dir", Paths.games.appendingPathComponent(input.key + "_build").path]
    if input.needsKeys, let keys { a += ["-k", keys] }
    if let x = xcode { a += ["--prepare-xcode", "--xcode-workspace", x.workspace.path]; if let b = x.bundle { a += ["--bundle-id", b] }; if quick { a += ["--gpu", "none"] }; return a }
    if let out { a += ["-o", out.path]; if quick { a += ["--gpu", "none"] }; return a }
    if quick { a += ["--gpu", "none", "--no-prebake"] }   // the game builds its pipelines itself, on first start
    return a
}

// How hard converting may work the Mac. Full speed leaves the engine's own defaults alone.
// Balanced and Background cap the engine's workers; Background also runs it at low priority.
// None of them change what the engine produces.
enum Speed: String, Codable, CaseIterable {
    case full, balanced, background
    var label: String {
        switch self { case .full: return "Full Speed"; case .balanced: return "Balanced"; case .background: return "Background" }
    }
    var note: String {
        switch self {
        case .full: return "Uses all of your Mac. The fastest way to convert."
        case .balanced: return "Uses about half of your Mac, so you can play while it works."
        case .background: return "Works quietly at low priority. Slowest, and the lightest on your Mac."
        }
    }
    init(effort: Int) { self = effort >= 100 ? .full : effort >= 50 ? .balanced : .background }   // the percentage of 1.8.1
}

func conversionWorkers(_ speed: Speed, cores: Int = ProcessInfo.processInfo.activeProcessorCount) -> Int {
    let n = max(1, cores)
    switch speed { case .full: return n; case .balanced: return max(1, n / 2); case .background: return max(1, n / 4) }
}

// Worker counts only. PYTHON_CPU_COUNT caps every step that sizes itself from the core
// count (the code rewrite's processes, the shader steps), so the per-module rewrite
// workers stay the engine's own choice. The prewarm thread count is deliberately not here:
// it can change how archive files are grouped, even though the finished game still works.
func conversionEnvironment(_ base: [String: String], speed: Speed, cores: Int = ProcessInfo.processInfo.activeProcessorCount) -> [String: String] {
    var e = base
    guard speed != .full else { return e }
    let workers = String(conversionWorkers(speed, cores: cores))
    e["J"] = workers
    e["DMSH_PROCS"] = workers
    e["PYTHON_CPU_COUNT"] = workers
    return e
}

func engineEnvironment(speed: Speed = .full) -> [String: String] {
    var e = ProcessInfo.processInfo.environment
    e["DEVELOPER_DIR"] = Paths.xcode
    e["PATH"] = (Paths.unpacked ? Paths.tools.path + "/bin:" : Paths.root.path + "/venv/bin:") + "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    e["LANG"] = "en_US.UTF-8"
    return conversionEnvironment(e, speed: speed)
}

// When converting may run: at once, only on the power adapter, or overnight. Converting works a Mac hard for a long time.
enum ConvertWhen: String, Codable, CaseIterable {
    case now, plugged, overnight
    var label: String { switch self { case .now: return "Right Away"; case .plugged: return "When Plugged In"; case .overnight: return "Overnight" } }
    var note: String {
        switch self {
        case .now: return "Games start converting as soon as you add them."
        case .plugged: return "Games convert only on the power adapter, with Low Power Mode off. Unplug or turn Low Power Mode on and it pauses, keeping its finished steps."
        case .overnight: return "Games convert while you're away: on the power adapter, Low Power Mode off, from 11 PM to 7 AM or after 15 minutes without use."
        }
    }
}
// Why converting waits now, or nil when it may go. idle: seconds since the keyboard, mouse or a controller was last used.
func convertWait(_ w: ConvertWhen, onPower: Bool, lowPower: Bool, hour: Int, idle: Double) -> String? {
    guard w != .now else { return nil }
    if !onPower { return lowPower ? "Waiting for the power adapter and Low Power Mode to turn off" : "Waiting for the power adapter" }
    if lowPower { return "Waiting for Low Power Mode to turn off" }
    if w == .overnight, !(hour >= 23 || hour < 7), idle < 900 { return "Waiting for tonight" }
    return nil
}

// Needs about twice the game plus 10 GB while building.
func spaceNeeded(_ bytes: Int64) -> Int64 { bytes * 2 + 10_000_000_000 }

func freeSpace() -> Int64 {
    freeSpace(at: URL(fileURLWithPath: NSHomeDirectory()))
}

// The player's own prod.keys, found on its own when it is in the Docked folder or beside the app. Never inside the app.
func findKeys(_ saved: String?, beside: URL = Bundle.main.bundleURL.deletingLastPathComponent()) -> String? {
    let places: [String?] = [saved, Paths.root.appendingPathComponent("prod.keys").path, beside.appendingPathComponent("prod.keys").path]
    return places.compactMap { $0 }.first { FileManager.default.isReadableFile(atPath: $0) }
}

// MARK: - Library

struct Game: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String
    var titleID: String
    var version = ""
    var rom: Rom?
    var needs = ""   // the macOS a converted game asks for
    var missing = false   // its file is gone, or on a drive that isn't connected
    var away: String?     // offloaded: where it is now. It is also missing, so nothing reads its file here
    var cannot: String? { away.map { "Offloaded to \(offloadName($0)). Download it to play" } ?? (missing ? whereMissing(url.path) : rom == nil ? cannotPlay(needs: needs) : nil) }
}

// A converted game, read from its app
func gameAt(_ u: URL) -> Game? {
    guard u.pathExtension == "app", let p = appInfo(u), let tid = p["DMTitleID"] as? String else { return nil }
    return Game(url: u, name: p["CFBundleName"] as? String ?? u.deletingPathExtension().lastPathComponent, titleID: tid, version: p["CFBundleShortVersionString"] as? String ?? "", needs: p["LSMinimumSystemVersion"] as? String ?? gameMinimum)
}

func scanLibrary(_ dir: URL = Paths.games) -> [Game] {
    let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    return items.compactMap(gameAt).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

// A library folder and the console folders in it
func libraryFolders(_ dir: URL) -> [URL] {
    let subs = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true && $0.pathExtension.lowercased() != "app" && !$0.lastPathComponent.hasSuffix("_build") }
    return [dir] + subs
}

// A profile in the engine's repository means someone tested the game; without one the build is a best guess.
func isTested(_ titleID: String) -> Bool {
    titleID.count == 16 && titleID.allSatisfy(\.isHexDigit) && FileManager.default.fileExists(atPath: Paths.engine.appendingPathComponent("dm/games/\(titleID.uppercased())/game.tsv").path)
}

// MARK: - Setup checks

struct Check: Identifiable {
    var id: String { title }
    var title: String
    var ok: Bool
    var detail: String
    var fix: String   // a Terminal command, or "" when there is none
    var installs = false   // Docked puts this in place itself
}

@discardableResult
func run(_ exe: String, _ args: [String], timeout: TimeInterval = 30) -> (code: Int32, out: String) {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: exe); p.arguments = args; p.environment = engineEnvironment()
    p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, error.localizedDescription) }
    let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit(); killer.cancel()
    return (p.terminationStatus, String(decoding: d, as: UTF8.self))
}

// What a Mac can do here. The library and other consoles work on any Mac that opens Docked; Switch games and converting need more.
struct MacKind { var version: [Int]; var appleChip: Bool
    static let this: MacKind = {
        let v = ProcessInfo.processInfo.operatingSystemVersion; var x: Int32 = 0, n = MemoryLayout<Int32>.size
        return MacKind(version: [v.majorVersion, v.minorVersion, v.patchVersion], appleChip: sysctlbyname("hw.optional.arm64", &x, &n, nil, 0) == 0 && x == 1)   // the Mac's own chip, also when Docked runs translated
    }()
    func atLeast(_ need: String) -> Bool { let n = need.split(separator: ".").map { Int($0) ?? 0 }; for i in 0..<max(n.count, version.count) { let a = i < version.count ? version[i] : 0, b = i < n.count ? n[i] : 0; if a != b { return a > b } }; return true }
}
let gameMinimum = "26.6"      // what the engine's games and Xcode 27.2 both need
var toolsMinimum: String { if Paths.unpacked { return (try? String(contentsOf: Paths.tools.appendingPathComponent(".tools-minimum"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "27.0" }; return Bundle.main.object(forInfoDictionaryKey: "DSToolsMinimum") as? String ?? gameMinimum }   // what the carried tools were built for
func laterOf(_ a: String, _ b: String) -> String { MacKind(version: a.split(separator: ".").map { Int($0) ?? 0 }, appleChip: true).atLeast(b) ? a : b }
func cannotConvert(_ m: MacKind = .this, tools: String = toolsMinimum) -> String? {
    if !m.appleChip { return "Converting Switch games needs a Mac with an Apple chip (M1 or later). Games for other consoles work here." }
    let need = laterOf(gameMinimum, tools); if !m.atLeast(need) { return "Converting Switch games needs macOS \(need) or later. Games for other consoles work here." }
    return nil
}
func cannotPlay(needs: String, _ m: MacKind = .this) -> String? {
    if !m.appleChip { return "Needs a Mac with an Apple chip" }
    return needs.isEmpty || m.atLeast(needs) ? nil : "Needs macOS \(needs) or later"
}

func runChecks(carriesTools: Bool = bundledPayload != nil) -> [Check] {
    let fm = FileManager.default
    if let why = cannotConvert() { return [Check(title: "This Mac", ok: false, detail: why, fix: "")] }
    let xv = NSDictionary(contentsOfFile: "/Applications/Xcode.app/Contents/version.plist")?["CFBundleShortVersionString"] as? String
    let xcode = xv == requiredXcode
    let license = xv != nil && run("/usr/bin/xcodebuild", ["-license", "check"]).code == 0
    let metal = license && run("/usr/bin/xcrun", ["-sdk", "macosx", "metal", "--version"]).code == 0
    let brew = fm.isExecutableFile(atPath: "/opt/homebrew/bin/brew")
    let toolDir = Paths.unpacked ? Paths.tools.path + "/bin" : "/opt/homebrew/bin"
    let glslang = fm.isExecutableFile(atPath: toolDir + "/glslangValidator")
    let zstd = fm.isExecutableFile(atPath: toolDir + "/zstd")
    let head = Paths.unpacked ? activeEngine : fm.fileExists(atPath: Paths.script.path) ? run("/usr/bin/git", ["-C", Paths.engine.path, "rev-parse", "HEAD"]).out.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let py = fm.isExecutableFile(atPath: Paths.python.path) && run(Paths.python.path, ["-I", "-c", "import sys,lz4.block,capstone,fontTools,nsz,zbic; assert sys.version_info>=(3,12)"]).code == 0
    let setup = "/bin/zsh \"" + (Bundle.main.url(forResource: "setup", withExtension: "sh")?.path ?? "setup.sh") + "\""
    let apple = [
        Check(title: "Xcode \(requiredXcode)", ok: xcode, detail: xv.map { "Found \($0)" } ?? "Not installed", fix: ""),
        Check(title: "Apple's Xcode licence", ok: license, detail: license ? "Accepted" : "You need to read and accept it yourself", fix: "sudo \(Paths.xcode)/usr/bin/xcodebuild -license"),
        Check(title: "Apple's Metal compiler", ok: metal, detail: metal ? "Installed" : "A free Apple download, after the licence", fix: "DEVELOPER_DIR=\(Paths.xcode) xcodebuild -downloadComponent MetalToolchain"),
    ]
    if carriesTools || Paths.unpacked {
        let ok = Paths.unpacked && py && glslang && zstd, older = !Paths.unpacked && fm.fileExists(atPath: Paths.tools.appendingPathComponent(".dockside-pin").path)
        return apple + [Check(title: "Conversion tools", ok: ok, detail: ok ? "Installed" : older ? "This Docked comes with a newer engine. Install it to keep converting" : "Included in Docked. Needs about 2.5 GB free", fix: "", installs: carriesTools)]
    }
    return apple + [
        Check(title: "Homebrew", ok: brew, detail: brew ? "Installed" : "Install it from brew.sh", fix: ""),
        Check(title: "Helper tools", ok: glslang && zstd, detail: glslang && zstd ? "Installed" : "glslang and zstd, from Homebrew", fix: setup),
        Check(title: "Conversion engine", ok: head == pinnedEngine, detail: head.isEmpty ? "Not installed" : head == pinnedEngine ? "Reviewed version \(head.prefix(8))" : "Not the reviewed version", fix: setup),
        Check(title: "Python tools", ok: py, detail: py ? "Installed" : "Kept apart from the rest of your Mac", fix: setup),
    ]
}
