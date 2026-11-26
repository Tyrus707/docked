import SwiftUI

extension Model {
    // Looks over every converted game that is here, off the main thread: signatures take a moment each.
    func checkHealth() {
        guard health == nil else { return }
        let n = healthScan.start()
        let list = games.filter { $0.rom == nil && !$0.missing && $0.away == nil }, lib = library, compat = compat
        health = HealthState()
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [Health] = []
            for (i, g) in list.enumerated() {
                DispatchQueue.main.async { if self.healthScan.current(n) { self.health?.progress = "Checking \(i + 1) of \(list.count)…" } }
                let e = lib.entry(g.titleID)
                out.append(healthOf(app: g.url, titleID: g.titleID, name: g.name, engine: e.engine, kept: e.kept, hasOriginals: !keptFiles(g.titleID).isEmpty, compat: compat[g.titleID.uppercased()]))
            }
            out.sort { ($0.good ? 2 : $0.problems.isEmpty ? 1 : 0, $0.name) < ($1.good ? 2 : $1.problems.isEmpty ? 1 : 0, $1.name) }
            DispatchQueue.main.async { if self.health != nil, self.healthScan.current(n) { self.health = HealthState(list: out, progress: nil) } }
        }
    }
    // Each one is added to the queue from its kept files, just as Add Update or DLC would, into the folder it is in now
    func rebuild(_ list: [Health]) {
        guard ready else { health = nil; showSetup = true; return }
        let wasTarget = target, wasFriends = reviewFriends; target = .mac; reviewFriends = false   // a rebuild never carries over the multiplayer choice of an earlier review
        var queued = 0, not: [String] = []
        for h in list where h.fixable {
            guard let g = games.first(where: { $0.url.path == h.path }) else { continue }
            review = Review(parts: []); review.add(keptFiles(g.titleID)); reviewNote = nil
            reviewPlace = g.url.deletingLastPathComponent(); if placeProblem(reviewPlace) != nil { reviewPlace = Paths.games }
            if convert() { queued += 1 } else { not.append("\(g.name): \(reviewNote ?? "it couldn't be added")") }
        }
        review = Review(parts: []); reviewNote = nil; target = wasTarget; reviewFriends = wasFriends; health = nil
        if queued > 0 { tell(queued == 1 ? "1 game will be rebuilt. It stays playable until the new one is ready." : "\(queued) games will be rebuilt, one at a time. Each stays playable until its new one is ready.") }
        if !not.isEmpty { message = "These weren't rebuilt: " + not.prefix(4).joined(separator: "; ") }
    }
}

struct HealthState: Equatable { var list: [Health] = []; var progress: String? = "Looking over your games…" }

struct HealthView: View {
    @EnvironmentObject var model: Model
    var state: HealthState { model.health ?? HealthState() }
    var fixable: [Health] { state.list.filter(\.fixable) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Library Health").font(.title2.weight(.semibold))
            if let p = state.progress { HStack { ProgressView().controlSize(.small); Text(p).foregroundStyle(.secondary) }.frame(height: 80) }
            else {
                Text(healthSummary(state.list)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !state.list.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(state.list) { h in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: !h.problems.isEmpty ? "exclamationmark.triangle.fill" : h.better.isEmpty && h.reports.isEmpty ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                        .foregroundStyle(!h.problems.isEmpty ? style.danger : h.better.isEmpty && h.reports.isEmpty ? style.ok : style.warn).frame(width: 18).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(h.name).foregroundStyle(style.text)
                                        ForEach(h.problems + h.better + h.reports, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                                        if h.good { Text(h.engine == nil ? "Plays as it should." : "Plays as it should, made with the engine in use.").font(.caption).foregroundStyle(.secondary) }
                                        if !h.good && !h.canRebuild { Text(h.kept ? "You chose Keep This Build, so it isn't rebuilt." : "Docked doesn't have its original files. Add them with Add Update or DLC to rebuild it.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                                    }
                                    Spacer()
                                    if h.fixable { Button("Rebuild") { model.rebuild([h]) }.controlSize(.small) }
                                }.padding(10)
                                Divider()
                            }
                        }
                    }.frame(maxHeight: 360).background(style.tile).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack {
                Text("A rebuild converts the game again from its kept files. Saves and play time stay.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { model.health = nil }.keyboardShortcut(.cancelAction)
                if fixable.count > 1 { Button("Rebuild All \(fixable.count)") { model.rebuild(fixable) }.keyboardShortcut(.defaultAction) }
            }
        }.padding(24).frame(width: 600).background(Backdrop())
    }
}
