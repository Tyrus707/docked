import Foundation

// What a conversion leaves behind, and removing it. Only Docked's own folders are deleted for good; the player's own files only ever go to the Trash.
struct Leftovers: Equatable { var id: String; var name: String; var folders: [URL]; var bytes: Int64 }

private func isRealFolder(_ u: URL) -> Bool { var s = stat(); return lstat(u.path, &s) == 0 && s.st_mode & S_IFMT == S_IFDIR }
private func inside(_ u: URL, _ dir: URL) -> Bool { u.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path }

// Does a game hold everything it needs? A link to anything outside it means the leftovers may still be in use.
func selfContained(_ app: URL, titleID: String) -> Bool {
    let fm = FileManager.default
    guard isRealFolder(app), let p = appInfo(app), (p["DMTitleID"] as? String)?.uppercased() == titleID.uppercased(),
          fm.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/dmhost").path) else { return false }
    var real = [CChar](repeating: 0, count: Int(PATH_MAX)); guard realpath(app.path, &real) != nil else { return false }
    let root = String(cString: real) + "/"
    guard let e = fm.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return false }
    for case let f as URL in e where (try? f.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
        var t = [CChar](repeating: 0, count: Int(PATH_MAX)); guard realpath(f.path, &t) != nil, String(cString: t).hasPrefix(root) else { return false }
    }
    return true
}

// The title a build folder belongs to: its name, or the profile inside it
func titleOf(build: URL) -> String? {
    let n = String(build.lastPathComponent.dropLast(6))
    if n.count == 16, n.allSatisfy(\.isHexDigit) { return n.uppercased() }
    let p = (try? FileManager.default.contentsOfDirectory(atPath: build.appendingPathComponent("profile").path)) ?? []
    let ids = p.filter { $0.count == 16 && $0.allSatisfy(\.isHexDigit) }; return ids.count == 1 ? ids[0].uppercased() : nil
}

// Every build folder in Docked's games folder, with the small notes the engine keeps beside an app. busy: build folders in use now.
func findLeftovers(games dir: URL = Paths.games, library: [Game], busy: Set<String> = []) -> [Leftovers] {
    let fm = FileManager.default, names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    var out: [String: Leftovers] = [:]
    for n in names where n.hasSuffix("_build") && n.count > 6 {
        let u = dir.appendingPathComponent(n); guard isRealFolder(u), !busy.contains(n) else { continue }
        let id = titleOf(build: u) ?? n, g = library.first { $0.rom == nil && $0.titleID.uppercased() == id }
        var l = out[id] ?? Leftovers(id: id, name: g?.name ?? "A game no longer in Docked", folders: [], bytes: 0); l.folders.append(u); out[id] = l
    }
    return out.values.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
}

// Refuses anything that is not plainly one of Docked's own build folders. Returns what could not be removed.
func removeLeftovers(_ folders: [URL], games dir: URL = Paths.games, busy: Set<String> = []) -> [URL] {
    var failed: [URL] = []
    for u in folders {
        let n = u.lastPathComponent
        guard n.hasSuffix("_build"), n.count > 6, !n.hasPrefix("."), inside(u, dir), isRealFolder(u), !busy.contains(n) else { failed.append(u); continue }
        // Out of the way first, in one step: a removal cut short must not leave a half-empty folder the engine would trust.
        let t = dir.appendingPathComponent(".removing-\(UUID().uuidString)")
        do { try FileManager.default.moveItem(at: u, to: t) } catch { failed.append(u); continue }
        do { try FileManager.default.removeItem(at: t) } catch { failed.append(u) }
    }
    return failed
}
// What an earlier removal was cut short on
func finishRemovals(games dir: URL = Paths.games) {
    for n in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where n.hasPrefix(".removing-") && UUID(uuidString: String(n.dropFirst(10))) != nil { let u = dir.appendingPathComponent(n); if isRealFolder(u) { try? FileManager.default.removeItem(at: u) } }
}
// The engine's note beside an app, and the empty folder its files were linked in
func removeNotes(for app: URL?, title id: String, games dir: URL = Paths.games, inputs: URL = Paths.inputs) {
    let fm = FileManager.default
    if let a = app { let k = dir.appendingPathComponent(a.lastPathComponent + ".key"); var s = stat(); if lstat(k.path, &s) == 0, s.st_mode & S_IFMT == S_IFREG, s.st_size < 8_000_000 { try? fm.removeItem(at: k) } }
    let i = inputs.appendingPathComponent(id); if id.count == 16, isRealFolder(i), ((try? fm.contentsOfDirectory(atPath: i.path)) ?? ["?"]).allSatisfy({ $0 == ".DS_Store" }) { try? fm.removeItem(at: i) }
}
// The player's keys file: to the Trash, and only a file plainly named as one
func trashKeys(_ path: String, trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> Bool {
    let u = URL(fileURLWithPath: path); var s = stat()
    guard u.pathExtension.lowercased() == "keys", lstat(u.path, &s) == 0, s.st_mode & S_IFMT == S_IFREG, s.st_size < 1_000_000 else { return false }
    return (try? trash(u)) != nil
}
