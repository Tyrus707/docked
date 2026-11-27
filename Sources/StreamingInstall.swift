import AppKit
import Foundation

struct SunshineRelease: Equatable {
    var tag: String
    var url: URL
    var sha256: String
}

// Docked carries no Sunshine in the download. The first time TV streaming is switched on it takes the newest stable
// macOS release from GitHub, checks the hash GitHub publishes with it, and keeps the app in its own hidden folder.
enum StreamingInstall {
    static let bundleID = "dev.lizardbyte.app.Sunshine"
    static let releases = "https://api.github.com/repos/SunshineStream/Sunshine/releases/latest"

    static func executable(in app: URL) -> URL? {
        let exe = app.appendingPathComponent("Contents/MacOS/Sunshine")
        return FileManager.default.isExecutableFile(atPath: exe.path) ? exe : nil
    }

    // An existing Sunshine is only reused if it is really Sunshine and its signature still checks out.
    static func signed(_ app: URL) -> Bool {
        guard executable(in: app) != nil, Bundle(url: app)?.bundleIdentifier == bundleID else { return false }
        return run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], timeout: 300).code == 0
    }

    static func installedApp() -> URL? {
        var choices: [URL?] = [NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)]
        let fm = FileManager.default
        let apps = [URL(fileURLWithPath: "/Applications/Sunshine.app"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Sunshine.app")]
        choices += apps
        return choices.compactMap { $0 }.first { signed($0) }
    }

    static func isHex(_ s: String, count: Int = 64) -> Bool {
        s.count == count && s.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 || $0.value >= 97 && $0.value <= 102 }
    }

    static func parseRelease(_ data: Data, arch: String = MacKind.this.appleChip ? "arm64" : "x86_64") throws -> SunshineRelease {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              j["prerelease"] as? Bool != true, let tag = j["tag_name"] as? String,
              tag.hasPrefix("v"), tag.count > 1,
              let assets = j["assets"] as? [[String: Any]],
              let asset = assets.first(where: { ($0["name"] as? String) == "Sunshine-macOS-\(arch).dmg" }),
              let link = asset["browser_download_url"] as? String, let url = URL(string: link), url.scheme == "https",
              let digest = asset["digest"] as? String, digest.hasPrefix("sha256:"),
              isHex(String(digest.dropFirst("sha256:".count))) else {
            throw StreamingError.text("GitHub didn't give Docked a checked Sunshine release for this Mac. Try again later.")
        }
        return SunshineRelease(tag: tag, url: url, sha256: String(digest.dropFirst("sha256:".count)))
    }

    static func ensure(progress: @escaping (String, Double?) -> Void = { _, _ in }) throws -> URL {
        if let app = installedApp() { return app }
        if signed(StreamingPaths.app) { return StreamingPaths.app }

        let fm = FileManager.default
        try fm.createDirectory(at: StreamingPaths.base, withIntermediateDirectories: true)
        var hidden = StreamingPaths.base
        var values = URLResourceValues(); values.isHidden = true; try? hidden.setResourceValues(values)
        let work = StreamingPaths.base.appendingPathComponent(".setup-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: work) }

        progress("Checking the newest Sunshine…", nil)
        guard let json = try? Lookup.get(URL(string: releases)!, limit: 1 << 20) else {
            throw StreamingError.text("Docked couldn't check GitHub for Sunshine. Check your connection and try again.")
        }
        let release = try parseRelease(json)
        let dmg = work.appendingPathComponent("Sunshine.dmg")
        try RetroArch.download(release.url, to: dmg, limit: 200 << 20) { progress("Downloading Sunshine \(release.tag)…", $0) }
        progress("Checking the download…", nil)
        guard sha256(dmg) == release.sha256 else {
            throw StreamingError.text("The Sunshine download didn't match GitHub's checksum, so it wasn't used. Try again later.")
        }

        let mount = work.appendingPathComponent("disk")
        try fm.createDirectory(at: mount, withIntermediateDirectories: false)
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path], timeout: 300).code == 0 else {
            throw StreamingError.text("Sunshine's disk image couldn't be opened.")
        }
        let copy = work.appendingPathComponent("Sunshine.app")
        let copied = run("/usr/bin/ditto", [mount.appendingPathComponent("Sunshine.app").path, copy.path], timeout: 600).code == 0
        run("/usr/bin/hdiutil", ["detach", "-force", mount.path], timeout: 60)
        guard copied, executable(in: copy) != nil else {
            throw StreamingError.text("Sunshine wasn't where Docked expected it in the download.")
        }
        guard signed(copy) else {
            throw StreamingError.text("Sunshine's signature didn't check out, so it wasn't used.")
        }
        try? fm.removeItem(at: StreamingPaths.app)
        do { try fm.moveItem(at: copy, to: StreamingPaths.app) }
        catch { throw StreamingError.text("Docked couldn't put Sunshine in its own folder. \(error.localizedDescription)") }
        RetroArch.unregister(StreamingPaths.app)   // never show up in Launchpad as an app of its own
        return StreamingPaths.app
    }
}
