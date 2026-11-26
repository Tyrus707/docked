import Foundation

// Library health: every converted game looked over in one place, and the ones a rebuild would help, rebuilt together.
struct Health: Identifiable, Equatable {
    var id: String { path }
    let path: String, titleID: String, name: String
    var problems: [String] = []   // it may not open, or not as it should
    var better: [String] = []     // it plays, but a rebuild would give it more
    var reports: [String] = []    // what players say; a rebuild can't change it
    var engine: String?           // the engine it was made with, when Docked kept track
    var canRebuild = false        // its original files are kept, and the player hasn't chosen to keep this build
    var kept = false
    var good: Bool { problems.isEmpty && better.isEmpty && reports.isEmpty }
    var fixable: Bool { canRebuild && (!problems.isEmpty || !better.isEmpty) }
}

// One game, looked over. Slow parts (the signature) come in from outside, so a test can pass its own.
func healthOf(app: URL, titleID: String, name: String, engine: String?, active: String = activeEngine, kept: Bool, hasOriginals: Bool, compat: Compat?,
              verify: (URL) -> Bool? = signatureHolds, friends: (URL) -> Bool = Friends.supported) -> Health {
    var h = Health(path: app.path, titleID: titleID.uppercased(), name: name, engine: engine, canRebuild: hasOriginals && !kept, kept: kept)
    if !selfContained(app, titleID: titleID) { h.problems.append("It is missing a part it needs, or still uses files outside itself.") }
    else if verify(app) == false { h.problems.append("Its signature doesn't match what is inside it, so macOS may refuse to open it.") }
    if let e = engine, e != active { h.better.append("It was made with an older engine. A rebuild uses the newer one.") }
    if !friends(app) { h.better.append("It was made before Play with friends. A rebuild adds it.") }
    if let c = compat, c.kind == .poor { h.reports.append("Players report it doesn't run yet (\(c.label)).") }
    return h
}

// What the health check says at the top
func healthSummary(_ list: [Health]) -> String {
    let bad = list.filter { !$0.problems.isEmpty }.count, better = list.filter { $0.problems.isEmpty && !$0.better.isEmpty }.count
    let reported = list.filter { $0.problems.isEmpty && $0.better.isEmpty && !$0.reports.isEmpty }.count, fine = list.count - bad - better - reported
    var s: [String] = []
    if fine > 0 { s.append(fine == list.count ? (fine == 1 ? "Your converted game looks good." : "All \(fine) converted games look good.") : fine == 1 ? "1 looks good." : "\(fine) look good.") }
    if bad > 0 { s.append(bad == 1 ? "1 needs attention." : "\(bad) need attention.") }
    if better > 0 { s.append(better == 1 ? "1 would be better after a rebuild." : "\(better) would be better after a rebuild.") }
    if reported > 0 { s.append(reported == 1 ? "1 has a report from players." : "\(reported) have reports from players.") }
    return list.isEmpty ? "There are no converted games to check yet." : s.joined(separator: " ")
}
