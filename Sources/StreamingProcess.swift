import Foundation

protocol StreamProcessLike: AnyObject {
    var onExit: ((Int32) -> Void)? { get set }
    func terminate()
}

final class StreamProcess: StreamProcessLike {
    private let process = Process()
    var onExit: ((Int32) -> Void)?

    init(executable: URL, arguments: [String]) throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw StreamingError.text("Sunshine isn't ready to start.")
        }
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        // The supervisor lives on the main thread, so its news of an exit does too.
        process.terminationHandler = { [weak self] p in DispatchQueue.main.async { self?.onExit?(p.terminationStatus) } }
        try process.run()
    }

    func terminate() { if process.isRunning { process.terminate() } }
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
            else { p = try StreamProcess(executable: executable, arguments: [config.path]) }
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
