import AppKit

protocol StreamProcessLike: AnyObject {
    var onExit: ((Int32) -> Void)? { get set }
    func terminate()
}

// Sunshine started through Launch Services, as its own app, so macOS asks about Screen Recording and system audio
// for Sunshine (signed by LizardByte, the same app across Docked updates). Started as Docked's child, macOS asked
// Docked, and an ad-hoc signed update looked like a new app: the permission was lost and Moonlight got error 503.
final class StreamApp: StreamProcessLike {
    private var app: NSRunningApplication?
    private var watch: NSKeyValueObservation?
    private var ending = false
    var onExit: ((Int32) -> Void)?

    init(bundle: URL, arguments: [String]) throws {
        guard FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/MacOS/Sunshine").path) else {
            throw StreamingError.text("Sunshine isn't ready to start.")
        }
        let c = NSWorkspace.OpenConfiguration()
        c.arguments = arguments
        c.activates = false
        c.hides = true
        c.addsToRecentItems = false
        c.createsNewApplicationInstance = true   // its own copy, even if the player's own Sunshine is open
        NSWorkspace.shared.openApplication(at: bundle, configuration: c) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { app?.terminate(); return }
                guard let app, error == nil else { self.onExit?(1); return }
                if self.ending { app.terminate(); return }
                self.app = app
                self.watch = app.observe(\.isTerminated, options: [.new]) { [weak self] a, _ in
                    guard a.isTerminated else { return }
                    DispatchQueue.main.async { guard let self else { return }; self.watch = nil; self.onExit?(self.ending ? 0 : 1) }
                }
            }
        }
    }

    // Asked to quit, then made to if it hasn't in 2 seconds, so a stopped Sunshine never keeps the port
    func terminate() {
        ending = true
        guard let a = app, !a.isTerminated else { return }
        a.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if !a.isTerminated { a.forceTerminate() } }
    }
}

// A small supervisor: three restarts for a crash, then a quiet, friendly stop. Tests give it a fake launch.
final class SunshineSupervisor {
    var maxRetries = 3
    var executable = StreamingPaths.executable
    var config = StreamingPaths.config
    var launch: (() throws -> StreamProcessLike)?
    var onState: (StreamingStatus, String) -> Void = { _, _ in }
    var onGiveUp: (String) -> Void = { _ in }

    private var current: StreamProcessLike?
    private var failures = 0
    private var stopping = false
    var running: Bool { current != nil }

    func start() {
        stopping = false
        failures = 0
        startOnce()
    }

    func stop() {
        stopping = true
        current?.terminate()
        current = nil
        onState(.stopped, "Stopped")
    }

    private func startOnce() {
        do {
            let p: StreamProcessLike
            if let launch { p = try launch() }
            else { p = try StreamApp(bundle: executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(), arguments: [config.path]) }
            current = p
            p.onExit = { [weak self, weak p] code in if let p { self?.exited(p, code) } }
            onState(.running, "Running")
        } catch {
            giveUp(error.localizedDescription)
        }
    }

    // Only the Sunshine running now counts. A stopped one exits a moment after a restart has started the next,
    // and must not clear it or start a second copy on the same port.
    func exited(_ p: StreamProcessLike, _ code: Int32) {
        guard !stopping, p === current else { return }
        current = nil
        if code == 0 { onState(.stopped, "Stopped"); return }
        failures += 1
        if failures <= maxRetries {
            onState(.starting, "Sunshine stopped. Restarting (\(failures) of \(maxRetries))…")
            startOnce()
        } else {
            giveUp("The last try didn't stay running.")
        }
    }

    private func giveUp(_ reason: String) {
        current = nil
        onState(.error, "Sunshine couldn't stay running.")
        onGiveUp(reason)
    }
}
