import Foundation
import CryptoKit

// A newer conversion engine without a new Docked. Only an engine Docked's maker reviewed and signed is ever used: the signature covers the engine's every file
// (its tree), so neither GitHub nor the download can change what runs. The new engine is built and tried beside the one in use, swapped in only while nothing
// converts, and the one before is kept so the player can go back to it.
struct EngineInfo: Codable, Equatable {
    struct Pack: Codable, Equatable {
        var name: String, sha256: String, bytes: Int
        var from: String? = nil, fromTree: String? = nil   // a difference from that engine, which must have that tree
    }
    var format: Int
    var commit: String
    var date: String      // the commit's time, ISO 8601: which of two engines is newer
    var minApp: String    // the oldest Docked it works with
    var tree: String
    var summary: String   // a line for players: what is new
    var full: Pack
    var deltas: [Pack]
    var when: Date? { ISO8601DateFormatter().date(from: date) }
}

struct EngineError: LocalizedError { let text: String; init(_ t: String) { text = t }; var errorDescription: String? { text } }

enum Engine {
    static let base = "https://github.com/Tyrus707/docked/releases/download/engine/"
    static let limit = 400_000_000
    static var pinnedDate: Date { ISO8601DateFormatter().date(from: pinnedEngineDate) ?? .distantPast }

    // ---- what is signed ----
    static func said(_ manifest: Data) -> Data { Data("docked-engine-v1|".utf8) + manifest }
    static func isCommit(_ s: String) -> Bool { s.count == 40 && s.allSatisfy { "0123456789abcdef".contains($0) } }
    static func isHash(_ s: String) -> Bool { s.count == 64 && s.allSatisfy { "0123456789abcdef".contains($0) } }
    static func isName(_ s: String) -> Bool { s.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$"#, options: .regularExpression) != nil && !s.contains("..") }
    static func read(_ manifest: Data, _ sig: Data, key: String = Update.publicKey) -> EngineInfo? {
        guard manifest.count < 64_000, let k = Data(base64Encoded: key), k.count == 32, let p = try? Curve25519.Signing.PublicKey(rawRepresentation: k), sig.count == 64,
              p.isValidSignature(sig, for: said(manifest)), let i = try? JSONDecoder().decode(EngineInfo.self, from: manifest) else { return nil }
        let packs = [i.full] + i.deltas
        guard i.format == 1, isCommit(i.commit), i.when != nil, isHash(i.tree), i.summary.count < 400,
              packs.allSatisfy({ isName($0.name) && isHash($0.sha256) && $0.bytes > 0 && $0.bytes < limit }), i.full.from == nil,
              i.deltas.allSatisfy({ $0.from.map(isCommit) == true && $0.fromTree.map(isHash) == true }) else { return nil }
        return i
    }

    // ---- what is installed ----
    struct Installed: Equatable { var commit: String; var date: Date; var info: EngineInfo? }   // info: nil for the engine this Docked was built with
    private static let lock = NSLock()
    private static var known: [String: Installed?] = [:]
    static var active: Installed? { installed(Paths.tools) }
    // A tools folder's engine, if Docked may use it: the one it was built with, or a signed one at least as new that this Docked is recent enough for.
    static func installed(_ tools: URL, key: String = Update.publicKey, app: String = appVersion) -> Installed? {
        guard let pin = (try? String(contentsOf: tools.appendingPathComponent(".dockside-pin"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines), isCommit(pin) else { return nil }
        if pin == pinnedEngine { return Installed(commit: pin, date: pinnedDate, info: nil) }
        let id = [tools.path, pin, key, app].joined(separator: "|")
        lock.lock(); defer { lock.unlock() }
        if let r = known[id] { return r }
        var r: Installed?
        if let m = try? Data(contentsOf: tools.appendingPathComponent(".dockside-engine.json")), let s = try? String(contentsOf: tools.appendingPathComponent(".dockside-engine.sig"), encoding: .utf8),
           let sig = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)), let i = read(m, sig, key: key), i.commit == pin, !newer(i.minApp, than: app),
           let d = i.when, d >= pinnedDate { r = Installed(commit: pin, date: d, info: i) }
        known[id] = r; return r
    }
    static func forget() { lock.lock(); known = [:]; lock.unlock() }
    static var previous: URL { Paths.root.appendingPathComponent("tools.previous") }

    // ---- is there a newer one ----
    enum Answer: Equatable { case newest, available(EngineInfo), needsApp(String), unknown }
    // published: false when GitHub says there is no engine release at all (404), so the engine Docked came with is the newest there is.
    static func answer(_ manifest: Data?, _ sig: Data?, active: Installed?, published: Bool = true, app: String = appVersion, key: String = Update.publicKey) -> Answer {
        if !published, active != nil { return .newest }
        guard let manifest, let sig = sig.flatMap({ Data(base64Encoded: String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }),
              let i = read(manifest, sig, key: key), let when = i.when else { return .unknown }
        if let a = active, i.commit == a.commit || when <= a.date { return .newest }
        if newer(i.minApp, than: app) { return .needsApp(i.minApp) }
        return .available(i)
    }
    // Asks for the engine's version file only; nothing is sent but the request. Answers on the main thread, with the signed bytes and their signature.
    static func check(_ done: @escaping (Answer, Data?, Data?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let (m, code) = small("engine.json"), s = m == nil ? nil : small("engine.json.sig").0, a = answer(m, s, active: active, published: code != 404)
            let sig = s.flatMap { Data(base64Encoded: String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
            DispatchQueue.main.async { done(a, m, sig) }
        }
    }
    private static func session() -> URLSession { let c = URLSessionConfiguration.ephemeral; c.httpCookieStorage = nil; c.timeoutIntervalForRequest = 30; c.timeoutIntervalForResource = 1800; return URLSession(configuration: c) }
    // The file, and GitHub's answer code (0 when nothing came back at all).
    private static func small(_ name: String) -> (Data?, Int) {
        guard let u = URL(string: base + name) else { return (nil, 0) }
        var r = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20); r.setValue("Docked", forHTTPHeaderField: "User-Agent")
        let s = session(), done = DispatchSemaphore(value: 0); var out: Data?, code = 0
        s.dataTask(with: r) { d, p, _ in code = (p as? HTTPURLResponse)?.statusCode ?? 0; if code == 200, p?.url?.scheme == "https", let d, d.count < 64_000 { out = d }; done.signal() }.resume()
        done.wait(); s.finishTasksAndInvalidate(); return (out, code)
    }
    // One pack, to a file in dir. Waits: only ever called off the main thread.
    static func download(_ p: EngineInfo.Pack, to dir: URL) -> URL? {
        guard isName(p.name), let u = URL(string: base + p.name) else { return nil }
        let s = session(), done = DispatchSemaphore(value: 0); var out: URL?
        s.downloadTask(with: u) { t, r, _ in
            defer { done.signal() }
            guard (r as? HTTPURLResponse)?.statusCode == 200, r?.url?.scheme == "https", let t, (try? t.resourceValues(forKeys: [.fileSizeKey]))?.fileSize == p.bytes else { return }
            let to = dir.appendingPathComponent(".engine-\(UUID().uuidString).download"); if (try? FileManager.default.moveItem(at: t, to: to)) != nil { out = to }
        }.resume()
        done.wait(); s.finishTasksAndInvalidate(); return out
    }

    // ---- the engine's fingerprint: Bundle/engine_tree.py takes it the same way ----
    static func tree(_ dir: URL) -> String? {
        let fm = FileManager.default
        guard let e = fm.enumerator(atPath: dir.path) else { return nil }
        var rows: [(String, String)] = []
        while let rel = e.nextObject() as? String {
            let name = (rel as NSString).lastPathComponent, type = e.fileAttributes?[.type] as? FileAttributeType
            if type == .typeDirectory { if name == "__pycache__" { e.skipDescendants() }; continue }
            if name == ".DS_Store" || name.hasSuffix(".pyc") { continue }
            guard type == .typeRegular, let h = sha256(dir.appendingPathComponent(rel)) else { rows.append((rel, "?")); continue }
            let x = ((e.fileAttributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o111 != 0
            rows.append((rel, h + "\t" + (x ? "x" : "-")))
        }
        let text = rows.sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }.map { $0.0 + "\t" + $0.1 + "\n" }.joined()
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // ---- putting a new one in place ----
    // Makes the new tools in tools.next: a copy of the ones in use (a clone, so it costs no space), with the new engine, checked file by file against what was
    // signed and tried once. The tools in use are only read. Returns tools.next, ready to swap in.
    static func prepare(manifest: Data, sig: Data, root: URL = Paths.root, key: String = Update.publicKey, app: String = appVersion, free: Int64 = freeSpace(),
                        fetch: (EngineInfo.Pack, URL) -> URL? = { Engine.download($0, to: $1) }, works: (URL) -> Bool = engineWorks) throws -> URL {
        let fm = FileManager.default, tools = root.appendingPathComponent("tools"), next = root.appendingPathComponent("tools.next"), x = root.appendingPathComponent("engine.partial")
        guard let i = read(manifest, sig, key: key) else { throw EngineError("The engine update could not be verified, so nothing was changed.") }
        guard !newer(i.minApp, than: app) else { throw EngineError("This engine needs Docked \(i.minApp) or later. Update Docked first.") }
        guard let now = installed(tools, key: key, app: app) else { throw EngineError("Install the conversion tools first.") }
        guard i.commit != now.commit, let when = i.when, when > now.date else { throw EngineError("You already have this engine or a newer one.") }
        guard !root.path.contains(" ") else { throw InstallError.spaces }
        let here = tree(tools.appendingPathComponent("engine"))
        let d = i.deltas.first(where: { $0.from == now.commit && $0.fromTree == here }), pack = d ?? i.full   // only what changed, when the engine here is exactly the one it was made from
        guard free > Int64(pack.bytes) * 10 + 1_000_000_000 else { throw EngineError("There isn't enough space for the new engine. It needs about \(byteText(Int64(pack.bytes) * 10 + 1_000_000_000)).") }
        for u in [next, x] { try? fm.removeItem(at: u) }
        var good = false
        defer { try? fm.removeItem(at: x); if !good { try? fm.removeItem(at: next) } }
        guard let file = fetch(pack, root) else { throw EngineError("The new engine could not be downloaded. Try again later.") }
        defer { try? fm.removeItem(at: file) }
        guard sha256(file) == pack.sha256 else { throw EngineError("The download was not the engine that was signed, so nothing was changed.") }
        if clonefile(tools.path, next.path, 0) != 0 { try fm.copyItem(at: tools, to: next) }
        try fm.createDirectory(at: x, withIntermediateDirectories: false)
        let r = run("/usr/bin/tar", ["-xJf", file.path, "-C", x.path], timeout: 900)
        let came = x.appendingPathComponent("engine"), engine = next.appendingPathComponent("engine")
        guard r.code == 0, fm.fileExists(atPath: came.path) else { throw EngineError("The new engine could not be unpacked. Nothing was changed.") }
        if d == nil { try fm.removeItem(at: engine); try fm.moveItem(at: came, to: engine) }
        else { try apply(came, removed: x.appendingPathComponent("engine.removed"), to: engine) }
        guard tree(engine) == i.tree else { throw EngineError("The new engine did not match what was signed, so nothing was changed.") }
        try Data((i.commit + "\n").utf8).write(to: next.appendingPathComponent(".dockside-pin"))
        try manifest.write(to: next.appendingPathComponent(".dockside-engine.json"))
        try Data((sig.base64EncodedString() + "\n").utf8).write(to: next.appendingPathComponent(".dockside-engine.sig"))
        guard installed(next, key: key, app: app)?.commit == i.commit else { throw EngineError("The new engine could not be put in place. Nothing was changed.") }
        guard works(next) else { throw EngineError("The new engine did not start on this Mac, so Docked kept the one you have.") }
        good = true; return next
    }
    // A difference: what went is removed, then what is new or changed is put in. Every path stays inside the engine.
    static func apply(_ came: URL, removed: URL, to engine: URL) throws {
        let fm = FileManager.default
        func inside(_ rel: String) -> URL? {
            let parts = rel.split(separator: "/", omittingEmptySubsequences: false)
            guard !rel.isEmpty, !rel.hasPrefix("/"), !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
            return engine.appendingPathComponent(rel)
        }
        for rel in ((try? String(contentsOf: removed, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) {
            guard let u = inside(rel) else { throw EngineError("The engine update named a file outside the engine. Nothing was changed.") }
            var s = stat(); if lstat(u.path, &s) == 0, s.st_mode & S_IFMT != S_IFDIR { try fm.removeItem(at: u) }
        }
        guard let e = fm.enumerator(atPath: came.path) else { return }
        var files: [String] = []   // listed first: they are moved out of the folder being listed
        while let rel = e.nextObject() as? String { if e.fileAttributes?[.type] as? FileAttributeType == .typeRegular { files.append(rel) } }
        for rel in files {
            guard let to = inside(rel) else { throw EngineError("The engine update named a file outside the engine. Nothing was changed.") }
            var s = stat(); if lstat(to.path, &s) == 0 { try fm.removeItem(at: to) }
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: came.appendingPathComponent(rel), to: to)
        }
    }
    // The new tools in place of the ones in use, in one step; those are kept as tools.previous (and an older previous goes).
    static func swapIn(_ next: URL, root: URL = Paths.root) throws {
        let fm = FileManager.default, tools = root.appendingPathComponent("tools"), prev = root.appendingPathComponent("tools.previous")
        guard renamex_np(next.path, tools.path, UInt32(RENAME_SWAP)) == 0 else { throw EngineError("The new engine could not be put in place. Nothing was changed.") }
        forget()
        if fm.fileExists(atPath: prev.path) { let t = root.appendingPathComponent(".removing-\(UUID().uuidString)"); if (try? fm.moveItem(at: prev, to: t)) != nil { DispatchQueue.global(qos: .utility).async { try? fm.removeItem(at: t) } } }
        try? fm.moveItem(at: next, to: prev)   // if this fails the old tools wait in tools.next, which goes next time
    }
    // Back to the engine before, in one step. The newer one becomes the previous, so this can be undone.
    static func goBack(root: URL = Paths.root, key: String = Update.publicKey, app: String = appVersion) throws {
        let tools = root.appendingPathComponent("tools"), prev = root.appendingPathComponent("tools.previous")
        guard installed(prev, key: key, app: app) != nil else { throw EngineError("There is no earlier engine to go back to.") }
        guard renamex_np(prev.path, tools.path, UInt32(RENAME_SWAP)) == 0 else { throw EngineError("Docked could not go back to the earlier engine. Nothing was changed.") }
        forget()
    }
    // What an update cut short leaves; never while one is being made.
    static func tidy(root: URL = Paths.root) {
        let fm = FileManager.default
        for n in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where n == "tools.next" || n == "engine.partial" || (n.hasPrefix(".engine-") && n.hasSuffix(".download")) || (n.hasPrefix(".removing-") && UUID(uuidString: String(n.dropFirst(10))) != nil) {
            try? fm.removeItem(at: root.appendingPathComponent(n))
        }
    }
}

// The engine starts with these tools: its Python packages load and it reads its own options.
func engineWorks(_ tools: URL) -> Bool {
    let py = tools.appendingPathComponent("bin/python3").path
    return run(py, ["-I", "-c", "import sys,lz4.block,capstone,fontTools,nsz,zbic; assert sys.version_info>=(3,12)"]).code == 0
        && run(py, ["-u", tools.appendingPathComponent("engine/scripts/build_ipa_from_nsp.py").path, "--help"], timeout: 120).code == 0
}
func engineDay(_ d: Date) -> String { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f.string(from: d) }
