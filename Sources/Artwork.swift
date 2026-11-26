import Foundation
import ImageIO

// Where Docked keeps game art, how much room it takes, and what of it no game in the library uses any more.
// Four places, all inside Docked's folder:
//   Artwork            covers the player chose (Choose Cover…, or a picture dropped on a game)
//   Metadata/Covers    covers found online for games from other consoles
//   Metadata/Tiles     the covers as the library shows them, made once and kept so they load at once next time
//   Metadata/AppIcons  a converted game's own art, kept so it stays when the game is offloaded
func artStem(_ id: String) -> String { id.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-") }

struct ArtPlace: Identifiable, Equatable {
    let id: String, name: String, url: URL
    var files = 0, bytes: Int64 = 0
    var spare: [URL] = [], spareBytes: Int64 = 0   // belongs to no game Docked knows, or replaced by newer art
}

enum Artwork {
    static var yours: URL { Paths.root.appendingPathComponent("Artwork") }
    static var found: URL { Paths.root.appendingPathComponent("Metadata/Covers") }
    static var made: URL { Paths.root.appendingPathComponent("Metadata/Tiles") }
    static var icons: URL { Paths.root.appendingPathComponent("Metadata/AppIcons") }
    static let version = "1"   // made covers from before a change to how they are drawn are made again

    // A made cover: named for its game, then for the art it was made from, so new art makes a new file and the old one is a leftover
    static func tile(_ id: String, from key: String) -> URL { made.appendingPathComponent(artStem(id) + "~" + fnv(version + "|" + key) + ".jpg") }
    static func fnv(_ s: String) -> String { var h: UInt64 = 0xcbf29ce484222325; for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }; return String(h, radix: 16) }
    // A picture as it is now: where, when it last changed, and its size
    static func fingerprint(_ u: URL) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: u.path), let d = a[.modificationDate] as? Date else { return nil }
        return "\(u.path)|\(String(format: "%.6f", d.timeIntervalSince1970))|\((a[.size] as? NSNumber)?.int64Value ?? 0)"
    }

    // A converted game's own art, kept here so it stays when its app is offloaded to a cloud folder.
    static func appIcon(_ id: String) -> URL { icons.appendingPathComponent(artStem(id) + ".png") }
    @discardableResult static func keepAppIcon(_ id: String, from app: URL) -> Bool {
        let fm = FileManager.default, source = app.appendingPathComponent("Contents/Resources/AppIcon.icns"), to = appIcon(id)
        guard let a = try? fm.attributesOfItem(atPath: source.path), let changed = a[.modificationDate] as? Date else { return false }
        if let kept = try? fm.attributesOfItem(atPath: to.path), let keptAt = kept[.modificationDate] as? Date, keptAt >= changed { return true }   // already kept, and not older
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else { return false }
        let count = CGImageSourceGetCount(src)
        func width(_ i: Int) -> Int { (CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int ?? 0 }
        let best = (0..<max(1, count)).max { width($0) < width($1) } ?? 0
        guard let image = CGImageSourceCreateImageAtIndex(src, best, nil) else { return false }
        try? fm.createDirectory(at: icons, withIntermediateDirectories: true)
        guard let dst = CGImageDestinationCreateWithURL(to as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dst, image, nil)
        return CGImageDestinationFinalize(dst)
    }

    // The newest made cover already on disk, so a game whose files went away keeps the art it had.
    static func newestTile(_ id: String, excluding key: String? = nil) -> URL? {
        let prefix = artStem(id) + "~", skip = key.map { tile(id, from: $0).lastPathComponent }, keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: made, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        var best: (URL, Date)?
        for f in files where f.lastPathComponent.hasPrefix(prefix) && f.lastPathComponent != skip {
            guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            let d = v.contentModificationDate ?? .distantPast
            if best == nil || d > best!.1 { best = (f, d) }
        }
        return best?.0
    }

    // When chosen art is cleared or changed, an away game must not bring back an older cover.
    static func removeMade(_ id: String) {
        let prefix = artStem(id) + "~"
        for f in (try? FileManager.default.contentsOfDirectory(at: made, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] where f.lastPathComponent.hasPrefix(prefix) { try? FileManager.default.removeItem(at: f) }
    }

    // ids: every game Docked knows, including those on a drive that isn't connected, so their art is never a leftover.
    static func survey(ids: [String]) -> [ArtPlace] {
        let known = Set(ids.map { artStem($0).lowercased() })
        func look(_ id: String, _ name: String, _ u: URL, stem: (String) -> String) -> ArtPlace {
            var p = ArtPlace(id: id, name: name, url: u), newest: [String: (URL, Date, Int64)] = [:]
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
            for f in (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? [] {
                guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
                let n = Int64(v.fileSize ?? 0), s = stem(f.deletingPathExtension().lastPathComponent).lowercased(), d = v.contentModificationDate ?? .distantPast
                p.files += 1; p.bytes += n
                if !known.contains(s) || f.pathExtension == "part" { p.spare.append(f); p.spareBytes += n; continue }
                guard id == "made" else { continue }
                // More than one made cover for a game: the newest is the one in use
                if let o = newest[s] { let (keep, drop) = o.1 >= d ? (o, (f, d, n)) : ((f, d, n), o); newest[s] = keep; p.spare.append(drop.0); p.spareBytes += drop.2 } else { newest[s] = (f, d, n) }
            }
            return p
        }
        return [look("yours", "Covers you chose", yours) { $0 },
                look("found", "Covers found online", found) { $0 },
                look("made", "Covers ready to show", made) { String($0.split(separator: "~", maxSplits: 1).first ?? "") },
                look("icons", "Game icons kept on this Mac", icons) { $0 }]
    }

    // Covers the player chose go to the Trash; the others are only copies Docked can find or make again. Returns the bytes freed.
    @discardableResult static func removeSpare(_ places: [ArtPlace]) -> Int64 {
        var freed: Int64 = 0
        for p in places {
            for f in p.spare {
                let n = Int64((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                do { if p.id == "yours" { try FileManager.default.trashItem(at: f, resultingItemURL: nil) } else { try FileManager.default.removeItem(at: f) }; freed += n } catch {}
            }
        }
        return freed
    }
}

// A game's file was deleted, rather than being on a drive that isn't connected or in a folder that has moved:
// the folder it was in is still there, and it isn't.
func deletedFile(_ path: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }, ids: DriveIDs = .shared) -> Bool {
    if let d = drive(of: path, ids: ids), !d.connected { return false }
    return !exists(path) && exists((path as NSString).deletingLastPathComponent)
}
