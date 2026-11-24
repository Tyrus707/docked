import Foundation

// Runs one build at a time: converting is heavy and memory is shared with the Mac.
final class Builder: ObservableObject {
    @Published var running = false
    @Published var title = ""
    @Published var stage = ""
    @Published var stageIndex = 0
    @Published var stageCount = 0
    @Published var frac: Double?
    @Published var eta: Double?
    @Published var tested: Bool?
    @Published var log: [String] = []
    @Published var error: String?
    private(set) var titleID: String?
    private(set) var output: URL?   // the finished app, as the engine named it
    var onFinish: () -> Void = {}

    var started = Date(), stageStarted = Date()
    private var estimator = Estimator.load(), times: [(String, Double)] = [], etaAt = Date()
    private(set) var skipsPipeline = false
    @Published var parts: (done: Int, total: Int)?   // the pipeline step's own progress
    private var work: URL?, watch: DispatchSourceTimer?, partsAt: (count: Int, at: Date)?
    private var proc: Process?
    private var activity: NSObjectProtocol?
    private(set) var failedAt = ""
    private var lastRed = "", stderrTail = "", cancelled = false

    func start(_ input: BuildInput, keys: String?, quick: Bool = false) {
        skipsPipeline = quick; work = Paths.games.appendingPathComponent(input.key + "_build")
        launch(exe: Paths.python.path, args: buildArguments(input, keys: keys, quick: quick), title: input.title)
    }

    func launch(exe: String, args: [String], title: String) {
        guard !running else { return }
        self.title = title; stage = "Starting"; stageIndex = 0; stageCount = 0; frac = nil; eta = nil; tested = nil
        started = Date(); stageStarted = started; estimator = Estimator.load(); times = []; stepOpen = nil; titleID = nil; output = nil
        log = []; error = nil; lastRed = ""; stderrTail = ""; cancelled = false
        try? FileManager.default.createDirectory(at: Paths.games, withIntermediateDirectories: true)
        let p = Process(), out = Pipe(), err = Pipe()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args; p.environment = engineEnvironment()
        p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        p.currentDirectoryURL = Paths.games
        // Exit is handled only after both pipes are drained, so the engine's last message is never lost.
        let group = DispatchGroup()
        group.enter(); group.enter(); group.enter()
        var buf = LineBuffer()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; group.leave(); return }
            let events = buf.append(d).compactMap(EngineEvent.parse)
            DispatchQueue.main.async { events.forEach { self?.handle($0) } }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; group.leave(); return }
            let s = String(decoding: d, as: UTF8.self)
            DispatchQueue.main.async { self.map { $0.stderrTail = String(($0.stderrTail + s).suffix(2000)) } }
        }
        p.terminationHandler = { _ in group.leave() }
        do { try p.run() } catch {
            out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
            self.error = "The conversion engine did not start: \(error.localizedDescription)"; return
        }
        proc = p; running = true
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Converting a game")
        group.notify(queue: .main) { [weak self] in self?.finished(p.terminationStatus) }
    }

    func cancel() { cancelled = true; stage = "Stopping"; proc?.terminate() }   // SIGTERM: the engine stops its own tools

    func handle(_ e: EngineEvent) {
        switch e {
        case let .stage(k, n, name): endStep(); stageIndex = k; stageCount = n; stage = name; stageStarted = Date(); frac = nil; eta = nil; watchPipeline()
        case let .step(s): frac = nil; eta = nil; if !s.isEmpty { add("  " + s) }
        case let .progress(f, t, _): frac = f; eta = t; etaAt = Date()
        case .stageEnd: endStep(); frac = 1; eta = nil
        case let .game(id, name, out): title = name; titleID = id.uppercased(); tested = isTested(id); output = out.map { URL(fileURLWithPath: $0) }
        case let .say(m):
            if m.hasPrefix("[RED]") || m.contains("] [RED]") { lastRed = m.components(separatedBy: "[RED]").last!.trimmingCharacters(in: .whitespaces) }
            add(m)
        }
    }

    private var stepOpen: String?
    private func endStep() {
        if stageCount > 0, stepOpen != "\(stageIndex)" { times.append((stage, Date().timeIntervalSince(stageStarted))); stepOpen = "\(stageIndex)" }
    }

    // Every 10 seconds, off the main thread, and only during that one step.
    func watchPipeline() {
        watch?.cancel(); watch = nil; parts = nil; partsAt = nil
        guard stage == "Pipeline archive", let w = work else { return }
        let since = stageStarted, t = DispatchSource.makeTimerSource(queue: .global(qos: .utility)); var total: Int?
        t.schedule(deadline: .now() + 2, repeating: 10)
        t.setEventHandler { [weak self] in
            if total == nil { total = Pipeline.total(w) }
            guard let n = total else { return }
            let d = min(Pipeline.done(w, since: since), n)
            DispatchQueue.main.async {
                guard let s = self, s.running, s.stage == "Pipeline archive" else { return }
                if d != s.partsAt?.count { s.partsAt = (d, Date()) }
                if s.parts?.done != d || s.parts?.total != n { s.parts = (d, n); s.frac = Double(d) / Double(n) }
            }
        }
        watch = t; t.resume()
    }

    // From how long the finished parts took; nothing until one is finished.
    func pipelineLeft(_ now: Date = Date()) -> Double? {
        guard let p = parts, let a = partsAt, p.done > 0 else { return nil }
        let each = a.at.timeIntervalSince(stageStarted) / Double(p.done)
        return max(0, each * Double(p.total - p.done) - now.timeIntervalSince(a.at))
    }

    // The engine's own figure counts down between its reports.
    func remaining(_ now: Date = Date()) -> Double? {
        guard running else { return nil }
        return estimator.remaining(step: stageCount > 0 ? stage : "", elapsed: now.timeIntervalSince(stageStarted), engineETA: eta.map { max(0, $0 - now.timeIntervalSince(etaAt)) }, quick: skipsPipeline, pipelineLeft: pipelineLeft(now))
    }

    var report: String { let v = ProcessInfo.processInfo.operatingSystemVersion; return makeReport(title: titleID.map { "\(title) [\($0)]" } ?? title, step: failedAt, error: error ?? "", log: log, version: appVersion, os: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)", chip: chipName(), space: freeSpace()) }
    func whole(quick: Bool) -> Double { estimator.whole(quick: quick) }
    private func add(_ s: String) { log.append(s); if log.count > 300 { log.removeFirst(log.count - 200) } }

    private func finished(_ code: Int32) {
        running = false; proc = nil; watch?.cancel(); watch = nil; parts = nil
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        if code == 0 { endStep(); estimator.learn(times); estimator.save(); stage = "Done" }
        else if cancelled { stage = "Stopped" }
        else {
            failedAt = stageCount > 0 ? "step \(stageIndex) of \(stageCount), \(stage)" : stage; stage = "Failed"
            error = !lastRed.isEmpty ? lastRed : !stderrTail.isEmpty ? String(stderrTail.suffix(600)) : "The engine stopped with code \(code)."
        }
        onFinish()
    }
}
