import Foundation
import Security

// The things Docked keeps secret: the RetroAchievements token (never the password) and Sunshine's own pairing password.
// They live in one file only this Mac's user can read. The login Keychain ties an item to the exact build that made it,
// and Docked is ad-hoc signed, so after every update the old item was out of reach and the player had to sign in again.
// The token is also what RetroArch reads from its own settings while a game plays, so a private file loses nothing.
enum Keychain {
    // In Application Support, away from the library folder that Finder, scripts and assistants browse
    static var file: URL {
        ProcessInfo.processInfo.environment["DOCKED_ROOT"] != nil ? Paths.root.appendingPathComponent("Secrets.json")
            : URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Docked/Secrets.json")
    }

    static func string(service: String, account: String) -> String? {
        if let v = load()[key(service, account)] { return v }
        // An older build kept it in the Keychain: move it over once, while that build's item can still be read
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
                                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data, let v = String(data: d, encoding: .utf8) else { return nil }
        set(v, service: service, account: account)
        return v
    }

    static func set(_ value: String?, service: String, account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)   // nothing is left behind in the Keychain
        var all = load()
        if let value, !value.isEmpty { all[key(service, account)] = value } else { all[key(service, account)] = nil }
        save(all)
    }

    private static func key(_ service: String, _ account: String) -> String { service + "\n" + account }
    private static func load() -> [String: String] {
        guard let d = try? Data(contentsOf: file), let j = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return j
    }
    private static func save(_ all: [String: String]) {
        let fm = FileManager.default, dir = file.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let d = try? JSONSerialization.data(withJSONObject: all, options: [.sortedKeys]) else { return }
        // A private new file, then swapped in, so a crash mid-save never loses every sign-in
        let tmp = dir.appendingPathComponent(".Secrets-\(UUID().uuidString).json")
        guard fm.createFile(atPath: tmp.path, contents: d, attributes: [.posixPermissions: 0o600]) else { return }
        if rename(tmp.path, file.path) != 0 { try? fm.removeItem(at: tmp) }
    }
}
