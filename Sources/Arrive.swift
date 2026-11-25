import Foundation

// A Docked opened from where it was downloaded: it offers to take the place of the older one in Applications, or to move there when there is none.
// Nothing is fetched and nothing else is replaced. The player has already chosen to open this copy, and macOS has already checked it.
enum Arrive {
    enum Offer: Equatable { case update(app: URL, has: String), move(to: URL)
        var app: URL { switch self { case let .update(a, _): return a; case let .move(a): return a } } }
    static var places: [URL] { [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")] }
    private static func real(_ u: URL) -> String { var b = [CChar](repeating: 0, count: Int(PATH_MAX)); return realpath(u.path, &b) != nil ? String(cString: b) : u.standardizedFileURL.path }
    private static func isFolder(_ u: URL) -> Bool { var s = stat(); return lstat(u.path, &s) == 0 && s.st_mode & S_IFMT == S_IFDIR }
    private static func info(_ app: URL) -> [String: Any] { NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:] }
    static func version(_ app: URL) -> String? { info(app)["CFBundleShortVersionString"] as? String }
    private static func hasTools(_ app: URL) -> Bool { FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/tools.tar.xz").path) }

    static func offer(me: URL, places: [URL] = Arrive.places) -> Offer? {
        let i = info(me); guard let id = i["CFBundleIdentifier"] as? String, let mine = i["CFBundleShortVersionString"] as? String else { return nil }
        let at = real(me), here = places.filter(isFolder); if here.contains(where: { at.hasPrefix(real($0) + "/") }) { return nil }
        for p in here { let a = p.appendingPathComponent("Docked.app", isDirectory: true); if isFolder(a), info(a)["CFBundleIdentifier"] as? String == id { let has = version(a) ?? "0"; return newer(mine, than: has) && (hasTools(me) || !hasTools(a)) ? .update(app: a, has: has) : nil } }
        for p in here where FileManager.default.isWritableFile(atPath: p.path) { let a = p.appendingPathComponent("Docked.app", isDirectory: true); var s = stat(); if lstat(a.path, &s) != 0 { return .move(to: a) } }
        return nil
    }

    // Copied beside its place, checked, and put there in one step. An older one is kept in backups.
    static func go(_ me: URL, _ o: Offer, backups: URL) throws {
        let fm = FileManager.default, app = o.app, dir = app.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: dir.path) else { throw UpdateError("Docked is not allowed to change the \(dir.lastPathComponent) folder. Drag it there yourself.") }
        let work = dir.appendingPathComponent(".docked-update-\(UUID().uuidString)"); try fm.createDirectory(at: work, withIntermediateDirectories: false); defer { try? fm.removeItem(at: work) }
        let new = work.appendingPathComponent("Docked.app"); try fm.copyItem(at: me, to: new)
        // Already opened and allowed by the player, so it is not asked about a second time
        for f in [new] + ((fm.enumerator(at: new, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []) { _ = removexattr(f.path, "com.apple.quarantine", XATTR_NOFOLLOW) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); p.arguments = ["--verify", "--strict", new.path]; p.standardError = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError("This copy of Docked is damaged. Download it again. Nothing was changed.") }
        guard offer(me: me, places: [dir]) == o else { throw UpdateError("The Docked in \(dir.lastPathComponent) has changed, so nothing was replaced.") }
        switch o {
        case let .update(_, has): try Update.swap(new, app, was: has, backups: backups)
        case .move: guard renamex_np(new.path, app.path, UInt32(RENAME_EXCL)) == 0 else { throw UpdateError("Docked could not be moved. Drag it to \(dir.lastPathComponent) yourself.") }
        }
    }
    static func title(_ o: Offer) -> String { switch o { case let .update(_, has): return "Update Docked \(has) to \(appVersion)?"; case .move: return "Move Docked to Applications?" } }
    static func text(_ o: Offer) -> String { switch o { case let .update(a, has): return "Docked \(has) is in \(a.deletingLastPathComponent().lastPathComponent). This copy is newer and can take its place. Your games, saves and settings stay, and the old version is kept in the Dockside folder, in Backups."; case .move: return "It opens from there from now on. You can delete the download afterwards." } }
}
