import AppKit

// Installing on an iPhone or iPad with Xcode: the engine prepares a project for each game, all in one workspace. Xcode signs it with the player's own Apple account; Docked never sees that account.
enum InstallWay: String { case xcode, ipa }
struct XcodeBuild: Equatable { var workspace: URL, bundle: String? }
struct XcodeGame: Equatable, Identifiable { var name: String, project: URL; var id: String { project.path }; var there: Bool { FileManager.default.fileExists(atPath: project.appendingPathComponent("project.pbxproj").path) } }
var xcodeWorkspace: URL { phoneFolder.appendingPathComponent("Docked.xcworkspace") }
func xcodeProject(in build: URL) -> URL { build.appendingPathComponent("xcode/DmIOS.xcodeproj") }
func hasXcodeProject(_ build: URL) -> Bool { XcodeGame(name: "", project: xcodeProject(in: build)).there }

// Two people can't use the same app ID, so each Mac has its own. It stays the same, because another ID would be another app with its own saves.
func bundleID(_ key: String, mark: String) -> String { "local.docked.m" + mark + ".g" + key.lowercased().unicodeScalars.filter { $0.isASCII && CharacterSet.alphanumerics.contains($0) }.map { String(Character($0)) }.joined() }
func macMark(_ d: UserDefaults = .standard) -> String { if let m = d.string(forKey: "macMark"), m.count == 8, m.allSatisfy(\.isHexDigit) { return m }; let m = String(UUID().uuidString.prefix(8)).lowercased(); d.set(m, forKey: "macMark"); return m }
// A project that is already there keeps the ID it has, also one changed in Xcode
func xcodeBuild(for key: String, games: URL = Paths.games, workspace: URL = xcodeWorkspace, mark: String = macMark()) -> XcodeBuild { XcodeBuild(workspace: workspace, bundle: hasXcodeProject(games.appendingPathComponent(key + "_build")) ? nil : bundleID(key, mark: mark)) }

private func contents(_ w: URL) -> URL { w.appendingPathComponent("contents.xcworkspacedata") }
private func groups(_ d: XMLDocument) -> [(XMLElement, XcodeGame)] {
    (d.rootElement()?.elements(forName: "Group") ?? []).compactMap { g in
        guard let at = g.elements(forName: "FileRef").first?.attribute(forName: "location")?.stringValue, at.hasPrefix("absolute:") else { return nil }
        return (g, XcodeGame(name: g.attribute(forName: "name")?.stringValue ?? "Game", project: URL(fileURLWithPath: String(at.dropFirst(9)))))
    }
}
func xcodeGames(_ w: URL = xcodeWorkspace) -> [XcodeGame] { guard let d = try? XMLDocument(contentsOf: contents(w), options: []) else { return [] }; return groups(d).map(\.1).filter(\.there) }
// Games whose project was cleaned up would show in red in Xcode
func tidyWorkspace(_ w: URL = xcodeWorkspace) {
    guard let d = try? XMLDocument(contentsOf: contents(w), options: []) else { return }
    let gone = groups(d).filter { !$0.1.there }; if gone.isEmpty { return }
    gone.forEach { $0.0.detach() }; try? d.xmlData(options: .nodePrettyPrint).write(to: contents(w), options: .atomic)
}
var xcodeApp: URL { URL(fileURLWithPath: Paths.xcode).deletingLastPathComponent().deletingLastPathComponent() }
func openInXcode(_ w: URL = xcodeWorkspace, _ failed: @escaping (String) -> Void) {
    tidyWorkspace(w)
    NSWorkspace.shared.open([w], withApplicationAt: xcodeApp, configuration: NSWorkspace.OpenConfiguration()) { _, e in if e != nil { DispatchQueue.main.async { failed("Xcode could not be opened. Check that it is in the Applications folder.") } } }
}
