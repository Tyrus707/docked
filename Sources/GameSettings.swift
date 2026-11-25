import Foundation

// A converted game's own launch settings: the list comes from the game's dm/launcher.json, and the player's choices
// are the ones its settings window keeps (the game app's preferences, "launcher.<name>"). Docked reads and writes the
// same choices, so the window you see when opening the game outside Docked and Docked's Game Settings always agree.
struct LaunchSetting: Decodable, Equatable, Identifiable {
    enum Kind: String, Decodable { case choice, toggle, range }
    var env: String, kind: Kind, section: String, label: String
    var note = "", `default` = "", level: String?, needs: String?
    var options: [[String]]?, on: String?, off: String?, min: Double?, max: Double?, step: Double?
    var id: String { env }
    var basic: Bool { level == "basic" }

    // "note" and "default" may be left out of launcher.json; the automatic decoder would reject the whole list for that
    private enum CodingKeys: String, CodingKey { case env, kind, section, label, note, `default`, level, needs, options, on, off, min, max, step }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        env = try c.decode(String.self, forKey: .env); kind = try c.decode(Kind.self, forKey: .kind)
        section = try c.decode(String.self, forKey: .section); label = try c.decode(String.self, forKey: .label)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""; `default` = try c.decodeIfPresent(String.self, forKey: .default) ?? ""
        level = try c.decodeIfPresent(String.self, forKey: .level); needs = try c.decodeIfPresent(String.self, forKey: .needs)
        options = try c.decodeIfPresent([[String]].self, forKey: .options)
        on = try c.decodeIfPresent(String.self, forKey: .on); off = try c.decodeIfPresent(String.self, forKey: .off)
        min = try c.decodeIfPresent(Double.self, forKey: .min); max = try c.decodeIfPresent(Double.self, forKey: .max)
        step = try c.decodeIfPresent(Double.self, forKey: .step)
    }

    // A range's value as text, with as many decimals as its step has: 1.0, 0.05
    func text(_ v: Double) -> String {
        let s = step ?? 0.1, d = s >= 1 ? 0 : Swift.min(4, Int((-log10(s)).rounded(.up)))
        return String(format: "%.\(d)f", v)
    }
}

struct GameSettings {
    let game: String, bundle: String
    let settings: [LaunchSetting]
    let fixed: [String: String]   // set by the game's env.txt: the game uses these whatever is saved
    private let saved: UserDefaults

    static let prefix = "launcher."

    // nil when the app has no settings list (older conversions) or can't be read
    init?(app: URL) {
        let res = app.appendingPathComponent("Contents/Resources")
        struct File: Decodable { var game: String?; var settings: [LaunchSetting] }
        guard let p = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")), let b = p["CFBundleIdentifier"] as? String,
              let d = try? Data(contentsOf: res.appendingPathComponent("dm/launcher.json")), let f = try? JSONDecoder().decode(File.self, from: d),
              !f.settings.isEmpty, let u = UserDefaults(suiteName: b) else { return nil }
        game = f.game ?? p["DMTitleID"] as? String ?? ""; bundle = b; settings = f.settings; saved = u
        var e: [String: String] = [:]
        for l in ((try? String(contentsOf: res.appendingPathComponent("dm/env.txt"), encoding: .utf8)) ?? "").split(whereSeparator: \.isNewline) {
            let t = l.trimmingCharacters(in: .whitespaces); guard !t.hasPrefix("#"), let i = t.firstIndex(of: "=") else { continue }
            e[String(t[..<i]).trimmingCharacters(in: .whitespaces)] = String(t[t.index(after: i)...]).trimmingCharacters(in: .whitespaces)
        }
        fixed = e
    }

    var sections: [String] { settings.reduce(into: [String]()) { if !$0.contains($1.section) { $0.append($1.section) } } }

    func value(_ s: LaunchSetting) -> String { fixed[s.env] ?? saved.string(forKey: Self.prefix + s.env) ?? s.default }
    func isFixed(_ s: LaunchSetting) -> Bool { fixed[s.env] != nil }
    func isSaved(_ s: LaunchSetting) -> Bool { saved.string(forKey: Self.prefix + s.env) != nil }

    // A setting that only matters when another is on, e.g. rumble strength needs rumble
    func applies(_ s: LaunchSetting) -> Bool {
        guard let n = s.needs, let i = n.firstIndex(of: "=") else { return true }
        let other = String(n[..<i]), want = String(n[n.index(after: i)...])
        guard let o = settings.first(where: { $0.env == other }) else { return true }
        return value(o) == want
    }

    func set(_ s: LaunchSetting, _ v: String) {
        guard !isFixed(s), v.utf8.count <= 256 else { return }
        if s.kind == .choice, let o = s.options, !o.contains(where: { $0.first == v }) { return }
        saved.set(v, forKey: Self.prefix + s.env)
    }

    // Back to the settings the game was tested with, like the window's own Reset button. Other choices it keeps (microphone, save sync) stay.
    func reset() { for s in settings { saved.removeObject(forKey: Self.prefix + s.env) } }
    var changed: Bool { settings.contains { isSaved($0) && value($0) != $0.default } }
}
