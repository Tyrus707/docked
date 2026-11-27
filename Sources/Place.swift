import Foundation

// Putting a finished game where the player wants it.
enum PlaceError: LocalizedError, Equatable {
    case missing, notWritable, taken(String), noSpace
    var errorDescription: String? {
        switch self {
        case .missing: return "That folder can't be found. If it's on an external drive, connect it."
        case .notWritable: return "Docked can't save to that folder. Choose another one."
        case .taken(let n): return "Something else named \(n) is already in that folder. Nothing was replaced."
        case .noSpace: return "There isn't enough space there for the game."
        }
    }
}

// An app's own Info.plist, and what Docked reads from a converted game's: its title ID, and its own preferences (the launcher's settings, under its bundle ID)
func appInfo(_ app: URL) -> NSDictionary? { NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) }
func titleID(of app: URL) -> String? { appInfo(app)?["DMTitleID"] as? String }
func gamePrefs(_ app: URL) -> UserDefaults? { (appInfo(app)?["CFBundleIdentifier"] as? String).flatMap { UserDefaults(suiteName: $0) } }

func sameVolume(_ a: URL, _ b: URL) -> Bool {
    func id(_ u: URL) -> NSObject? { (try? u.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject }
    guard let x = id(a), let y = id(b) else { return false }
    return x.isEqual(y)
}

// Why a folder can't take games, or nil.
func placeProblem(_ dir: URL) -> PlaceError? {
    var d: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &d), d.boolValue else { return .missing }
    if dir.pathComponents.contains(where: { $0.hasSuffix(".app") }) { return .notWritable }
    return FileManager.default.isWritableFile(atPath: dir.path) ? nil : .notWritable
}

// Moves a game into a folder. An older copy of the same game there goes to the Trash; anything else with that name is left alone.
// The game arrives complete or not at all: on another disk it is copied first under a temporary name.
func placeGame(_ app: URL, in dir: URL, discard: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws -> URL {
    let fm = FileManager.default
    if let p = placeProblem(dir) { throw p }
    let to = dir.appendingPathComponent(app.lastPathComponent)
    if app.deletingLastPathComponent().resolvingSymlinksInPath().path == dir.resolvingSymlinksInPath().path { return app }
    guard let id = titleID(of: app) else { throw PlaceError.missing }
    let old = fm.fileExists(atPath: to.path)
    if old, titleID(of: to) != id { throw PlaceError.taken(app.lastPathComponent) }
    if sameVolume(app, dir) {
        if old { try discard(to) }
        try fm.moveItem(at: app, to: to)
        return to
    }
    guard freeSpace(at: dir) > folderSize(app) + 500_000_000 else { throw PlaceError.noSpace }
    let part = dir.appendingPathComponent("." + app.lastPathComponent + ".partial")
    try? fm.removeItem(at: part)
    do {
        try fm.copyItem(at: app, to: part)
        if old { try discard(to) }
        try fm.moveItem(at: part, to: to)
    } catch { try? fm.removeItem(at: part); throw error }
    LeftBehind.remove(app)   // the copy is complete and in place
    return to
}
