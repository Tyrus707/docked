import Foundation

// How long each step usually takes, so the time left covers the steps still to come and not just this one.
// Starts from a measured conversion and then learns from each finished one on this Mac.
struct Estimator: Codable, Equatable {
    // Steps a quick conversion leaves out
    static let pipeline: Set<String> = ["Pipeline archive", "Prewarm pipelines", "Pipeline prebuild"]
    // An iPhone conversion shares the first steps, then compiles every shader for the phone. Times measured with one large game.
    static let phoneSteps: [(String, Double)] = [("extract", 6), ("rewrite", 20), ("shader split", 12), ("iOS shaders", 600), ("app build", 30), ("IPA pack", 290)]
    // For Xcode, the project takes the place of the app and its package
    static let xcodeSteps: [(String, Double)] = phoneSteps.prefix(4) + [("prepare Xcode", 15)]
    static func steps(xcode: Bool) -> [(String, Double)] { xcode ? xcodeSteps : phoneSteps }
    private static func usual(_ n: String) -> Double? { (phoneSteps + xcodeSteps).first { $0.0 == n }?.1 }
    var order = ["extract", "rewrite", "shader split", "Mac shaders", "Mac host", "Pipeline archive", "Prewarm pipelines", "Mac app"]
    var seconds: [String: Double] = ["extract": 6, "rewrite": 20, "shader split": 12, "Mac shaders": 300, "Mac host": 25, "Pipeline archive": 480, "Prewarm pipelines": 2, "Mac app": 35]

    // "extract v0" and "extract v2228224" are the same kind of step.
    static func kind(_ name: String) -> String {
        for p in ["extract DLC", "pack DLC", "unpack DLC"] where name == p { return p }
        for p in ["extract", "unpack", "pack", "check"] where name.hasPrefix(p + " ") { return p }
        return name
    }

    // Seconds left for the whole conversion, every step included. engineETA is the engine's own count for the current step, pipelineLeft Docked's count of its parts.
    func remaining(step: String, elapsed: Double, engineETA: Double?, quick: Bool = false, pipelineLeft: Double? = nil, phone: Bool = false, xcode: Bool = false) -> Double {
        let k = Self.kind(step), steps = phone ? Self.steps(xcode: xcode).map(\.0) : order.filter { !quick || !Self.pipeline.contains($0) }
        guard !step.isEmpty else { return total(steps[...]) }
        let usual = seconds[k] ?? Self.usual(k), now: Double
        if k == "Pipeline archive", let p = pipelineLeft { now = p }
        else if let e = engineETA, e >= 0, e.isFinite { now = e }
        else if let u = usual, u > elapsed { now = u - elapsed }
        else { now = max(10, elapsed * 0.2) }   // past its usual time, or a step never seen: a little more, growing with how long it has run
        if let i = steps.firstIndex(of: k) { return now + total(steps[(i + 1)...]) }
        return now + total(steps[(steps.firstIndex(of: "rewrite") ?? 0)...])   // a step not in the usual order (DLC, captures) comes before the shaders
    }
    func whole(quick: Bool, phone: Bool = false, xcode: Bool = false) -> Double { remaining(step: "", elapsed: 0, engineETA: nil, quick: quick, phone: phone, xcode: xcode) }

    private func total(_ steps: ArraySlice<String>) -> Double { steps.reduce(0) { sum, n in sum + (seconds[n] ?? Self.usual(n) ?? 0) } }

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

func shortTime(_ s: Double) -> String { let m = Int((max(0, s) / 60).rounded(.up)); return s < 60 ? "less than a minute" : m < 60 ? "about \(m) min" : "about \(m / 60) h \(m % 60) min" }
func timeLeftText(_ s: Double?) -> String? { s.map { "Estimated time remaining: " + shortTime($0) } }

func elapsedText(_ s: Double) -> String { let m = max(0, Int(s)) / 60; return m < 1 ? "Started just now" : "Running for \(m) min" }
