import AppKit

// Play time from the system's own app-opened and app-closed notices: no polling, so nothing runs while you play.
final class PlayTracker {
    private var started: [pid_t: (id: String, at: Date)] = [:]
    var identify: (URL) -> String? = { _ in nil }
    var countedUntil: (String) -> Date? = { _ in nil }   // time already kept, so a game open across a restart is not counted twice
    var finished: (String, Date, Date) -> Void = { _, _, _ in }
    var changed: () -> Void = {}
    private(set) var running = Set<String>()

    func start() {
        let n = NSWorkspace.shared.notificationCenter
        n.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] in self?.opened($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication) }
        n.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] in self?.closed($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication) }
        NSWorkspace.shared.runningApplications.forEach(opened)   // a game that was already open
    }

    // A game opened in another app (RetroArch): that run of it is this game.
    func adopt(_ a: NSRunningApplication, as id: String) {
        guard !a.isTerminated else { return }
        started[a.processIdentifier] = (id, Date()); running.insert(id); changed()
    }

    // A process can be told of before its start time is known.
    private func sessionStart(launched: Date?, counted: Date?, now: Date = Date()) -> Date { min(now, max(launched ?? now, counted ?? .distantPast)) }

    // The game's window belongs to the program inside its app, so either of them counts, once.
    private func opened(_ a: NSRunningApplication?) {
        guard let a, let u = a.bundleURL ?? a.executableURL, let id = identify(u), started[a.processIdentifier] == nil else { return }
        started[a.processIdentifier] = (id, sessionStart(launched: a.launchDate, counted: countedUntil(id))); running.insert(id); changed()
    }

    // Docked is quitting: keep what has been played so far.
    func flush(_ now: Date = Date()) {
        var first: [String: Date] = [:]
        for s in started.values { first[s.id] = min(first[s.id] ?? s.at, s.at) }
        for (id, at) in first { finished(id, at, now) }
        started = [:]
    }

    private func closed(_ a: NSRunningApplication?) {
        guard let a, let s = started.removeValue(forKey: a.processIdentifier) else { return }
        guard !started.values.contains(where: { $0.id == s.id }) else { return }
        running.remove(s.id); finished(s.id, s.at, Date()); changed()
    }
}
