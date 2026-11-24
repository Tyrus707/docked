import Foundation

// ---- how much room a queue needs ----
// Games convert one at a time, so it is the worst moment that counts: what the earlier ones leave behind, plus the one converting.
func spaceForQueue(_ jobs: [Job]) -> Int64 {
    var kept: Int64 = 0, worst: Int64 = 0
    for j in jobs {
        worst = max(worst, kept + spaceNeeded(j.bytes))
        switch j.after { case .ask: kept += j.bytes * 2; case .leftovers: kept += j.bytes; case .everything: kept += j.bytes }   // the originals only free space once the Trash is emptied
    }
    return worst
}
func spaceText(need: Int64, free: Int64) -> (text: String, short: Bool) {
    let f = ByteCountFormatter(); f.countStyle = .file
    return free >= need ? ("Needs about \(f.string(fromByteCount: need)) while converting. You have \(f.string(fromByteCount: free)).", false)
        : ("Needs about \(f.string(fromByteCount: need)) while converting, but you have \(f.string(fromByteCount: free)). Free up about \(f.string(fromByteCount: need - free)).", true)
}

// ---- a report someone can post in public ----
// Takes out what says who or where: the home folder, the user name, other disks, addresses, and anything that looks like a key.
func redact(_ s: String, home: String = NSHomeDirectory(), user: String = NSUserName(), full: String = NSFullUserName()) -> String {
    var t = s.replacingOccurrences(of: home, with: "~")
    func swap(_ p: String, _ w: String) { t = t.replacingOccurrences(of: p, with: w, options: [.regularExpression, .caseInsensitive]) }
    swap(#"/Users/[^/\s"']+"#, "~"); swap(#"/Volumes/[^/\n"']+"#, "/Volumes/(disk)"); swap(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "(email)"); swap(#"\b\d{1,3}(\.\d{1,3}){3}\b"#, "(address)"); swap(#"\b[0-9a-f]{24,}\b"#, "(hidden)"); swap(#"\b(gh[pousr]_|github_pat_|sk-)[A-Za-z0-9_-]{10,}"#, "(hidden)")
    for n in Set([user, full] + full.split(separator: " ").map(String.init)) where n.count >= 3 { swap("(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: n) + "(?![A-Za-z0-9])", "(name)") }
    return t
}
func makeReport(title: String, step: String, error: String, log: [String], version: String, os: String, chip: String, space: Int64) -> String {
    let f = ByteCountFormatter(); f.countStyle = .file
    return redact("Docked \(version), engine \(pinnedEngine.prefix(12))\nmacOS \(os), \(chip), \(f.string(fromByteCount: space)) free\nGame: \(title)\nStopped at: \(step)\n\n\(error)\n\nLast lines:\n" + log.suffix(60).joined(separator: "\n"))
}
func chipName() -> String { var n = 0; guard sysctlbyname("machdep.cpu.brand_string", nil, &n, nil, 0) == 0, n > 0 else { return "unknown chip" }; var b = [CChar](repeating: 0, count: n); sysctlbyname("machdep.cpu.brand_string", &b, &n, nil, 0); return String(cString: b) }

// ---- updates: looked for only when asked ----
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
let releasePage = URL(string: "https://github.com/Tyrus707/docked/releases/latest")!
func newer(_ a: String, than b: String) -> Bool {
    func n(_ s: String) -> [Int]? { let t = s.hasPrefix("v") ? String(s.dropFirst()) : s, p = t.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }; return p.isEmpty || p.contains(nil) ? nil : p.map { $0! } }
    guard let x = n(a), let y = n(b) else { return false }
    for i in 0..<max(x.count, y.count) { let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0; if p != q { return p > q } }
    return false
}
enum UpdateAnswer: Equatable { case newest, available(String), unknown }
func readRelease(_ d: Data?, _ code: Int, current: String = appVersion) -> UpdateAnswer {
    guard code == 200, let d, d.count < 1_000_000, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let tag = j["tag_name"] as? String, tag.count < 24, tag.range(of: #"^v?\d+(\.\d+){0,3}$"#, options: .regularExpression) != nil else { return .unknown }
    return newer(tag, than: current) ? .available(tag.hasPrefix("v") ? String(tag.dropFirst()) : tag) : .newest
}
func checkForUpdate(_ done: @escaping (UpdateAnswer) -> Void) {
    var r = URLRequest(url: URL(string: "https://api.github.com/repos/Tyrus707/docked/releases/latest")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15); r.setValue("Docked", forHTTPHeaderField: "User-Agent"); r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let c = URLSessionConfiguration.ephemeral; c.httpCookieStorage = nil; let s = URLSession(configuration: c)
    s.dataTask(with: r) { d, p, _ in let a = readRelease(d, (p as? HTTPURLResponse)?.statusCode ?? 0); DispatchQueue.main.async { done(a) }; s.finishTasksAndInvalidate() }.resume()
}
