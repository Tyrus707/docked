import Foundation
import CryptoKit

// The conversion tools carried inside the app, unpacked once into the Docked folder.
enum InstallError: LocalizedError, Equatable {
    case damaged, spaces, noSpace, failed(String)
    var errorDescription: String? {
        switch self {
        case .damaged: return "This copy of Docked is damaged. Copy it to this Mac again."
        case .spaces: return "Your home folder's name has a space in it, which the conversion tools can't handle."
        case .noSpace: return "There isn't enough space. The conversion tools need about 2.5 GB."
        case .failed(let s): return "The conversion tools could not be unpacked. \(s)"
        }
    }
}

var bundledPayload: URL? { Bundle.main.url(forResource: "tools", withExtension: "tar.xz") }
var bundledPayloadSHA: String { Bundle.main.object(forInfoDictionaryKey: "DSPayloadSHA256") as? String ?? "" }

func sha256(_ url: URL) -> String? {
    guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? h.close() }
    var s = SHA256()
    while let d = try? h.read(upToCount: 4 << 20), !d.isEmpty { s.update(data: d) }
    return s.finalize().map { String(format: "%02x", $0) }.joined()
}

// Checked before unpacking, and put in place only when complete.
func installTools(_ payload: URL, sha: String, root: URL = Paths.root) throws {
    let fm = FileManager.default
    guard !root.path.contains(" ") else { throw InstallError.spaces }
    guard !sha.isEmpty, sha256(payload) == sha else { throw InstallError.damaged }
    guard freeSpace() > 2_500_000_000 else { throw InstallError.noSpace }
    let part = root.appendingPathComponent("tools.partial", isDirectory: true)
    try? fm.removeItem(at: part)
    try fm.createDirectory(at: part, withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("Games"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: part) }
    let r = run("/usr/bin/tar", ["-xJf", payload.path, "-C", part.path], timeout: 900)
    let new = part.appendingPathComponent("tools", isDirectory: true)
    guard r.code == 0, fm.fileExists(atPath: new.appendingPathComponent(".dockside-pin").path) else { throw InstallError.failed(String(r.out.suffix(200))) }
    let to = root.appendingPathComponent("tools", isDirectory: true)
    if fm.fileExists(atPath: to.path) { _ = try fm.replaceItemAt(to, withItemAt: new) } else { try fm.moveItem(at: new, to: to) }
}
