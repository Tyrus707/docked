import Foundation

// How long each step usually takes, so the time left covers the steps still to come and not just this one.
// Starts from a measured conversion and then learns from each finished one on this Mac.
struct Estimator: Codable, Equatable {
    // The engine reports no progress for these and their length varies several times over between games, so they are never guessed.
    static let untimed: Set<String> = ["Pipeline archive", "Prewarm pipelines", "Pipeline prebuild"]
    var order = ["extract", "rewrite", "shader split", "Mac shaders", "Mac host", "Pipeline archive", "Prewarm pipelines", "Mac app"]
    var seconds: [String: Double] = ["extract": 6, "rewrite": 20, "shader split": 12, "Mac shaders": 300, "Mac host": 25, "Pipeline archive": 200, "Prewarm pipelines": 2, "Mac app": 35]

    // "extract v0" and "extract v2228224" are the same kind of step.
    static func kind(_ name: String) -> String {
        for p in ["extract DLC", "pack DLC", "unpack DLC"] where name == p { return p }
        for p in ["extract", "unpack", "pack", "check"] where name.hasPrefix(p + " ") { return p }
        return name
    }

    // Seconds left, or nil when there is nothing to go on. engineETA is the engine's own count for the current step.
    func remaining(step: String, elapsed: Double, engineETA: Double?) -> Double? {
        let k = Self.kind(step)
        if Self.untimed.contains(k) { return nil }
        guard !step.isEmpty else { return total(order[...]) }
        let now: Double
        if let e = engineETA, e >= 0 { now = e }
        else if let s = seconds[k], s > elapsed { now = s - elapsed }
        else if seconds[k] != nil, elapsed < 60 { now = 5 }   // just past its usual time
        else { return nil }                                   // unknown, or well past its usual time
        guard let i = order.firstIndex(of: k) else { return now + rest(after: step) }
        return now + total(order[(i + 1)...])
    }

    // A step not in the usual order (DLC, captures) comes before the shaders.
    private func rest(after step: String) -> Double {
        let i = order.firstIndex(of: "rewrite") ?? 0
        return total(order[i...])
    }

    private func total(_ steps: ArraySlice<String>) -> Double { steps.reduce(0) { $0 + (Self.untimed.contains($1) ? 0 : seconds[$1] ?? 0) } }

    // Reused steps take a moment and would spoil the next estimate, so only real work counts.
    mutating func learn(_ times: [(String, Double)]) {
        for (name, t) in times where t >= 3 && t.isFinite {
            let k = Self.kind(name)
            seconds[k] = seconds[k].map { ($0 + t) / 2 } ?? t
        }
    }

    static func load() -> Estimator {
        UserDefaults.standard.data(forKey: "stepTimes").flatMap { try? JSONDecoder().decode(Estimator.self, from: $0) } ?? Estimator()
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "stepTimes") } }
}

func timeLeftText(_ seconds: Double?, step: String = "", pipelineToCome: Bool = false) -> String? {
    if seconds == nil, Estimator.untimed.contains(Estimator.kind(step)) { return "The pipeline step can take 3 to 30 minutes" }
    guard let s = seconds else { return nil }
    let tail = pipelineToCome ? ", plus the pipeline step" : ""
    if s < 60 { return "Estimated time remaining: less than a minute" + tail }
    let m = Int((s / 60).rounded(.up))
    return "Estimated time remaining: " + (m < 60 ? "about \(m) min" : "about \(m / 60) h \(m % 60) min") + tail
}

func elapsedText(_ s: Double) -> String { let m = max(0, Int(s)) / 60; return m < 1 ? "Started just now" : "Running for \(m) min" }
