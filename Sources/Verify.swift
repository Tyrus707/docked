import Foundation

// A converted game is checked before Docked calls it done: an engine that exits cleanly can still leave a game short of something.
struct GameCheck: Equatable {
    var problems: [String] = []   // it may not open, or not as it should
    var notes: [String] = []      // it opens, but its graphics are not all prepared, so the first play stutters while the Mac makes the rest
    var ok: Bool { problems.isEmpty && notes.isEmpty }
    var text: String {
        if !problems.isEmpty { return "Converted, but " + problems.joined(separator: ", and ") + ". Its leftovers were kept, so converting it again is quicker." }
        return "Ready to play, but " + notes.joined(separator: ", and ") + ", so the first play may stutter. Its leftovers were kept, so converting it again only redoes that part."
    }
}

// warned: the steps the engine said finished without what they make. verify: whether the app's signature holds (codesign; a test passes its own).
func checkGame(_ app: URL, titleID: String, quick: Bool, warned: [String], verify: (URL) -> Bool? = signatureHolds) -> GameCheck {
    var c = GameCheck()
    guard selfContained(app, titleID: titleID) else { c.problems.append("it is missing a part it needs, or still uses files outside itself"); return c }
    if verify(app) == false { c.problems.append("its signature does not match what is inside it, so macOS may refuse to open it") }
    for w in warned { c.notes.append("one step did not finish (\(w))") }
    guard !quick else { return c }   // the game builds its pipelines itself on its first start, as chosen
    let pso = app.appendingPathComponent("Contents/PlugIns/PipelineArchive.bundle/Contents/Resources/pso"), files = (try? FileManager.default.contentsOfDirectory(atPath: pso.path)) ?? []
    // A game without graphics to prepare gets no archive. One that has an archive must have it whole.
    if FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/PlugIns/PipelineArchive.bundle").path) {
        if !files.contains("prebuilt.tsv") || !files.contains(where: { $0.hasSuffix(".mtl4a") && !$0.contains("-prewarm-") }) { c.notes.append("its pipeline archive is incomplete") }
        else if let n = leftOut(pso.appendingPathComponent("archive.tsv")), n > 0 { c.notes.append("\(n) of its graphics pipelines could not be prepared ahead") }
    }
    return c
}

// How many pipelines the archive says the compiler failed on (archive.tsv's "failed" line, written by the engine for people and logs).
func leftOut(_ tsv: URL) -> Int? {
    guard let t = try? String(contentsOf: tsv, encoding: .utf8) else { return nil }
    for l in t.split(separator: "\n") where l.hasPrefix("failed\t") {
        let rest = l.dropFirst(7), nums = rest.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return nums.prefix(2).reduce(0, +)   // bases, then compute pipelines
    }
    return nil
}

// codesign without --deep: the app's own seal and its parts' signatures, in seconds. nil when it could not tell (it ran out of time, or did not start).
func signatureHolds(_ app: URL) -> Bool? {
    let r = run("/usr/bin/codesign", ["--verify", app.path], timeout: 300)
    switch r.code { case 0: return true; case 1, 3: return false; default: return nil }
}
