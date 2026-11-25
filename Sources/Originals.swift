import Foundation

// Moving the files a game was converted from to the Trash. Only ever the exact files that were converted, never a folder, never prod.keys,
// and never a permanent delete.
struct SourceFile: Codable, Equatable { var path: String; var size: Int64 }

struct Originals: Equatable {
    var links: [URL] = []        // Docked's own links
    var files: [URL] = []        // the player's files, confirmed to be the ones that were converted
    var bytes: Int64 = 0
    var isEmpty: Bool { links.isEmpty && files.isEmpty }
}

private func fileID(_ u: URL) -> NSObject? { (try? u.resolvingSymlinksInPath().resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject }
func sameFile(_ a: URL, _ b: URL) -> Bool { guard let x = fileID(a), let y = fileID(b) else { return false }; return x.isEqual(y) }
private func isConvertible(_ u: URL) -> Bool {
    let v = try? u.resourceValues(forKeys: [.isRegularFileKey]); let e = u.pathExtension.lowercased()
    return v?.isRegularFile == true && (packageTypes.contains(e) || e == "nup")
}

func findOriginals(links: [URL], sources: [SourceFile]) -> Originals {
    var o = Originals()
    for l in links where FileManager.default.fileExists(atPath: l.path) { o.links.append(l); o.bytes += folderSize(l.resolvingSymlinksInPath()) }
    for s in sources {
        let u = URL(fileURLWithPath: s.path)
        guard isConvertible(u), folderSize(u) == s.size, !links.contains(where: { $0.path == u.path }) else { continue }
        // A .nup has no link; anything else must be the very file behind one.
        if u.pathExtension.lowercased() == "nup" { o.files.append(u); o.bytes += s.size }
        else if links.contains(where: { sameFile($0, u) }) { o.files.append(u) }
    }
    return o
}

// Returns the files that could not be moved. A link is dropped only once the file it stands for is in the Trash;
// where Docked's link is the last copy, the link itself goes to the Trash.
func trashOriginals(_ o: Originals, trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> [URL] {
    var failed: [URL] = []
    var linked: [(URL, [URL])] = o.links.map { l in (l, o.files.filter { sameFile(l, $0) }) }
    for f in o.files where !o.links.contains(where: { sameFile($0, f) }) { do { try trash(f) } catch { failed.append(f) } }
    while let (link, files) = linked.popLast() {
        let isSymlink = (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil
        var ok = true
        for f in files { do { try trash(f) } catch { failed.append(f); ok = false } }
        if !ok { continue }
        if files.isEmpty && !isSymlink { do { try trash(link) } catch { failed.append(link) } }
        else { try? FileManager.default.removeItem(at: link) }
    }
    return failed
}
