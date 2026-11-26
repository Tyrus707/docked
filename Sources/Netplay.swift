import Foundation

// Retro games online with a friend, through RetroArch's own netplay and libretro's free relay (so no router set-up).
// The host's RetroArch announces a room with a random name and password in libretro's lobby; the friend gets a docked://join link,
// and their Docked finds that room and joins it with the same game. Docked runs no server of its own for this.
enum Netplay {
    static var lobby = URL(string: "https://lobby.libretro.com/list")!
    static var file: URL { RetroArch.support.appendingPathComponent("netplay.cfg") }
    struct Room: Equatable { let ip: String, port: Int, session: String? }
    enum Role: Equatable { case host(Invite), join(Invite, Room) }

    // RetroArch's settings for this one game, appended after Docked's own
    static func lines(_ r: Role) -> String {
        let l = RetroArch.line
        switch r {
        case let .host(i):
            return l("netplay_nickname", i.room) + l("netplay_password", i.key) + l("netplay_public_announce", "true") + l("netplay_use_mitm_server", "true") + l("netplay_nat_traversal", "true") + l("netplay_allow_slaves", "true")
        case let .join(i, _):
            return l("netplay_nickname", "Docked-friend") + l("netplay_password", i.key)
        }
    }
    static func arguments(_ r: Role) -> [String] {
        switch r {
        case .host: return ["--host"]
        case let .join(_, room): return ["--connect", room.ip, "--port", String(room.port)] + (room.session.map { ["--mitm-session", $0] } ?? [])
        }
    }

    // The host's room in the lobby's list: through the relay when it has one, else straight to the host
    static func room(_ d: Data, named name: String) -> Room? {
        guard let all = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return nil }
        for x in all {
            let f = x["fields"] as? [String: Any] ?? x
            guard f["username"] as? String == name else { continue }
            func n(_ k: String) -> Int { (f[k] as? NSNumber)?.intValue ?? Int(f[k] as? String ?? "") ?? 0 }
            let mip = f["mitm_ip"] as? String ?? "", session = (f["mitm_session"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if !mip.isEmpty, n("mitm_port") > 0 { return Room(ip: mip, port: n("mitm_port"), session: session) }
            if let ip = f["ip"] as? String, !ip.isEmpty, n("port") > 0 { return Room(ip: ip, port: n("port"), session: nil) }
        }
        return nil
    }
    // Looks for the room every 3 seconds for a minute: the host may still be starting. Calls back on the main queue.
    static func find(_ i: Invite, until: Date = Date().addingTimeInterval(60), done: @escaping (Room?) -> Void) {
        var r = URLRequest(url: lobby, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15); r.setValue("Docked", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: r) { d, p, _ in
            if let d, (p as? HTTPURLResponse)?.statusCode == 200, d.count < 8_000_000, let room = room(d, named: i.room) { return DispatchQueue.main.async { done(room) } }
            guard Date() < until else { return DispatchQueue.main.async { done(nil) } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { find(i, until: until, done: done) }
        }.resume()
    }
}
