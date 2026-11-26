import Foundation
import CryptoKit

// Replacing Docked with a newer one. Nothing is trusted but a signature made with a key that only its maker has: not the site it came from, not its name, not its fingerprint.
struct UpdateError: LocalizedError { let text: String; init(_ t: String) { text = t }; var errorDescription: String? { text } }
enum Update {
    static let publicKey = "ygJGgHe2MhcJXj2FRGtyGHwPlvCJYTzuqzUwSY1L7Ho="
    static let base = "https://github.com/Tyrus707/docked/releases/download/"
    static let limit = 60_000_000
    // The version is signed together with the file, so an old genuine update cannot be passed off as a new one
    static func said(_ version: String, _ zip: Data) -> Data { Data("docked-update-v1|\(version)|".utf8) + Data(SHA256.hash(data: zip)) }
    static func genuine(_ zip: Data, _ sig: Data, version: String, key: String = publicKey) -> Bool {
        guard let k = Data(base64Encoded: key), k.count == 32, let p = try? Curve25519.Signing.PublicKey(rawRepresentation: k), sig.count == 64 else { return false }
        return p.isValidSignature(sig, for: said(version, zip))
    }
    private static func run(_ tool: String, _ a: [String]) throws { let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = a; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; try p.run(); p.waitUntilExit(); if p.terminationStatus != 0 { throw UpdateError("The update could not be prepared.") } }

    // Checks the update, builds the new app beside the old one, and swaps them in one step.
    static func install(_ zip: Data, _ sig: Data, version: String, over app: URL, current: String = appVersion, key: String = publicKey) throws {
        let fm = FileManager.default
        guard version.range(of: #"^\d+(\.\d+){0,3}$"#, options: .regularExpression) != nil, newer(version, than: current) else { throw UpdateError("That is not a newer version.") }
        guard zip.count < limit, genuine(zip, sig, version: version, key: key) else { throw UpdateError("The update could not be verified, so nothing was changed. Download it from the Docked page instead.") }
        let dir = app.deletingLastPathComponent(); guard fm.isWritableFile(atPath: dir.path), !app.path.contains("/AppTranslocation/") else { throw UpdateError("Docked can't replace itself where it is. Move it to Applications and open it from there.") }
        let work = dir.appendingPathComponent(".docked-update-\(UUID().uuidString)"); try fm.createDirectory(at: work, withIntermediateDirectories: false); defer { try? fm.removeItem(at: work) }
        let z = work.appendingPathComponent("u.zip"), out = work.appendingPathComponent("x"); try zip.write(to: z); try run("/usr/bin/ditto", ["-x", "-k", z.path, out.path])
        let new = out.appendingPathComponent("Docked.app"), c = new.appendingPathComponent("Contents"), pl = c.appendingPathComponent("Info.plist")
        guard (try? fm.contentsOfDirectory(atPath: out.path))?.filter({ !$0.hasPrefix(".") }) == ["Docked.app"], var i = NSDictionary(contentsOf: pl) as? [String: Any], i["CFBundleIdentifier"] as? String == Bundle(url: app)?.bundleIdentifier, i["CFBundleShortVersionString"] as? String == version else { throw UpdateError("The update is not Docked \(version). Nothing was changed.") }
        if let e = fm.enumerator(at: new, includingPropertiesForKeys: [.isSymbolicLinkKey]) { for case let f as URL in e where (try? f.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { throw UpdateError("The update holds something it should not. Nothing was changed.") } }
        try run("/usr/bin/codesign", ["--verify", "--strict", new.path])
        // The conversion tools are 110 MB and rarely change, so an update leaves them out and they are carried over. They are checked against the fingerprint the app already held.
        let oldInfo = appInfo(app) as? [String: Any] ?? [:], tools = app.appendingPathComponent("Contents/Resources/tools.tar.xz"), to = c.appendingPathComponent("Resources/tools.tar.xz")
        if !fm.fileExists(atPath: to.path), fm.fileExists(atPath: tools.path), let want = oldInfo["DSPayloadSHA256"] as? String {
            if clonefile(tools.path, to.path, 0) != 0 { try fm.copyItem(at: tools, to: to) }
            guard sha256(to) == want else { throw UpdateError("Docked's own tools look damaged. Download the full version from the Docked page. Nothing was changed.") }
            i["DSPayloadSHA256"] = want; if let m = oldInfo["DSToolsMinimum"] { i["DSToolsMinimum"] = m }
            try PropertyListSerialization.data(fromPropertyList: i, format: .xml, options: 0).write(to: pl); try run("/usr/bin/codesign", ["--force", "--sign", "-", new.path]); try run("/usr/bin/codesign", ["--verify", "--strict", new.path])
        }
        try swap(new, app)
    }
    // Both change places in one step. The old one is left in the caller's work folder and goes with it: older versions are on the Docked page, so none is kept.
    static func swap(_ new: URL, _ app: URL) throws {
        guard renamex_np(new.path, app.path, UInt32(RENAME_SWAP)) == 0 else { throw UpdateError(errno == EPERM || errno == EACCES ? "macOS did not allow Docked to replace itself. In System Settings, open Privacy & Security, then App Management, and turn on Docked." : "Docked could not be replaced. Nothing was changed.") }
    }
    // Up to 1.5 every update left a whole old app in Docked's Backups folder, and macOS listed each one as another Docked. They go, and the folder too once empty. Nothing else in it is touched.
    static func clearBackups(_ backups: URL) {
        let fm = FileManager.default
        for n in (try? fm.contentsOfDirectory(atPath: backups.path)) ?? [] where n.hasPrefix("Docked ") && ((n.contains(" before ") && n.hasSuffix(".app")) || n.hasSuffix("(previous version).zip")) { try? fm.removeItem(at: backups.appendingPathComponent(n)) }
        if (try? fm.contentsOfDirectory(atPath: backups.path))?.allSatisfy({ $0 == ".DS_Store" }) == true { try? fm.removeItem(at: backups) }
    }
    static func fetch(_ version: String, _ done: @escaping (Result<(Data, Data), Error>) -> Void) {
        let c = URLSessionConfiguration.ephemeral; c.httpCookieStorage = nil; c.timeoutIntervalForResource = 300; let s = URLSession(configuration: c), at = base + "v\(version)/Docked-Update.zip"
        func get(_ u: String, _ max: Int, _ f: @escaping (Data?) -> Void) { guard let l = URL(string: u) else { return f(nil) }; s.downloadTask(with: l) { t, r, _ in guard (r as? HTTPURLResponse)?.statusCode == 200, r?.url?.scheme == "https", let t, let n = (try? t.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, n <= max else { return f(nil) }; f(try? Data(contentsOf: t)) }.resume() }
        get(at + ".sig", 200) { g in
            guard let g, let sig = Data(base64Encoded: String(decoding: g, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else { return DispatchQueue.main.async { done(.failure(UpdateError("The update could not be downloaded."))) } }
            get(at, limit) { z in DispatchQueue.main.async { s.finishTasksAndInvalidate(); if let z { done(.success((z, sig))) } else { done(.failure(UpdateError("The update could not be downloaded."))) } } }
        }
    }
    // Opens the new one once this one has gone; asked twice, as macOS can miss the first while it takes in the replaced app (a second only brings it to the front)
    static func reopen(_ app: URL) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /bin/sleep 1; /usr/bin/open \"$2\"; /bin/sleep 4; /usr/bin/open \"$2\"", "sh", String(getpid()), app.path]; try? p.run() }
}
