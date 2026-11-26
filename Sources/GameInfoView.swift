import SwiftUI

// A game Docked couldn't tell for sure, waiting for the player to say which it is
struct Picking: Identifiable { var id: String { rom.id }; var rom: Rom; var choices: [Candidate]; var byHand: Bool }

extension Model {
    // Just added: looked up at once if the player has said yes, asked about the first time
    func lookUpAdded(_ ids: [String]) {
        let new = ids.filter { id in library.roms.contains { $0.id == id && $0.info == nil } }
        guard !new.isEmpty else { return }
        switch lookUp {
        case true?: new.forEach { find($0) }
        case false?: return
        case nil: waitingLookUp += new; askLookUp = true
        }
    }
    func allowLookUp(_ yes: Bool) { lookUp = yes; let w = waitingLookUp; waitingLookUp = []; if yes { w.forEach { find($0) } } }
    // Turned on in Settings: the games already here are looked up too
    func lookUpAll() { library.roms.filter { $0.info == nil }.forEach { find($0.id) } }

    func find(_ id: String, byHand: Bool = false) {
        guard let r = library.roms.first(where: { $0.id == id }), let c = console(r.console), !c.native, finding.insert(id).inserted else { return }
        let run: (@escaping () -> Void) -> Void = byHand ? { Lookup.queue.async(execute: $0) } : { Lookup.work.addOperation($0) }   // one asked for by hand doesn't wait behind the rest
        run {
            let m = Result { try Lookup.match(r) }
            // Sure of it: details and cover straight away. By hand, the player always sees the choices, the best first.
            if !byHand, case .success(.found(let best)) = m {
                let f = Lookup.fill(r, best)
                DispatchQueue.main.async { self.finding.remove(id); self.use(id, f.info, cover: f.cover, rename: false) }
                return
            }
            var choices: [Candidate] = []
            if case .success(.found(let best)) = m { choices = [best] }
            if case .success(.choose(let cs)) = m { choices = cs }
            if byHand { for x in (try? Lookup.search(r.name, c)) ?? [] where !choices.contains(where: { $0.key == x.key }) { choices.append(x) } }
            DispatchQueue.main.async {
                self.finding.remove(id)
                if case .failure(let e) = m, byHand { self.message = "Docked couldn't look up \(r.name). \(e.localizedDescription)"; return }
                if byHand || !choices.isEmpty { self.ask(Picking(rom: r, choices: Array(choices.prefix(12)), byHand: byHand)) }
            }
        }
    }
    func ask(_ p: Picking) { if picking == nil && !sheetUp { picking = p } else if !picks.contains(where: { $0.id == p.id }) { picks.append(p) } }
    func nextPick() { guard picking == nil, !picks.isEmpty, !sheetUp else { return }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if self.picking == nil, !self.sheetUp, !self.picks.isEmpty { self.picking = self.picks.removeFirst() } } }
    func chose(_ p: Picking, _ c: Candidate?) {
        guard var c else { return }
        c.info.how = "chosen"; finding.insert(p.rom.id)
        Lookup.queue.async { let f = Lookup.fill(p.rom, c); DispatchQueue.main.async { self.finding.remove(p.rom.id); self.use(p.rom.id, f.info, cover: f.cover, rename: true) } }
    }
    // The name follows the list's unless the player has renamed the game themselves
    func use(_ id: String, _ info: GameInfo, cover: URL?, rename: Bool) {
        guard let i = library.roms.firstIndex(where: { $0.id == id }) else { return }
        var r = library.roms[i]
        if cover == nil { try? FileManager.default.removeItem(at: Lookup.artFile(id)) }   // a cover from an earlier, wrong match goes
        if rename || r.name == cleanName(URL(fileURLWithPath: r.path)) { r.name = info.name }
        r.info = info; library.roms[i] = r
        refresh(r)
    }
    func forgetInfo(_ id: String) {
        guard let i = library.roms.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: Lookup.artFile(id))
        library.roms[i].info = nil; library.roms[i].name = cleanName(URL(fileURLWithPath: library.roms[i].path))
        refresh(library.roms[i])
    }
    // The game's new name, details and cover, without looking through every folder again: a big library found in a row stays smooth
    private func refresh(_ r: Rom) {
        guard let j = games.firstIndex(where: { $0.rom?.id == r.id }) else { reload(); return }
        var g = games[j]; g.rom = r; g.name = r.name; games[j] = g; dropArt(g)
    }
}

struct GamePicker: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss
    let pick: Picking
    @State private var query: String
    @State private var found: [Candidate]
    @State private var searching = false
    init(pick: Picking) { self.pick = pick; _query = State(initialValue: pick.rom.name); _found = State(initialValue: pick.choices) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pick.byHand ? "Find \(pick.rom.name)" : "Which game is this?").font(.title2.weight(.semibold))
                Text(pick.byHand ? "Choose the game this file is, and Docked fills in its cover and details." : "\(URL(fileURLWithPath: pick.rom.path).lastPathComponent) could be more than one game.").font(.callout).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
            HStack {
                TextField("Game name", text: $query).textFieldStyle(.roundedBorder).onSubmit(search)
                Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(found) { c in row(c) }
                    if found.isEmpty && !searching { Text("Nothing matched. Try fewer words, or the name it had in the shop.").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30) }
                    if searching { ProgressView().controlSize(.small).padding(.top, 30) }
                }
            }.frame(height: 270)
            Text("From libretro's public game list. Covers from libretro-thumbnails.").font(.caption).foregroundStyle(.secondary)
            HStack {
                if pick.byHand, pick.rom.info != nil { Button("Remove Found Details") { model.forgetInfo(pick.rom.id); dismiss() } }
                Spacer()
                if !pick.byHand, !model.picks.isEmpty { Button("Skip All") { model.picks = []; dismiss() } }
                Button(pick.byHand ? "Cancel" : "Skip") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 500)
    }
    func row(_ c: Candidate) -> some View {
        let region = c.info.title.range(of: #"\([^)]*\)"#, options: .regularExpression).map { String(c.info.title[$0].dropFirst().dropLast()) }
        let more = [c.info.line, c.info.genre, region].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return Button { model.chose(pick, c); dismiss() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) { Text(c.info.name).foregroundStyle(style.text); if !more.isEmpty { Text(more).font(.caption).foregroundStyle(style.soft) } }
                Spacer(); Text("Use").font(.callout.weight(.medium)).foregroundStyle(style.accent)
            }.padding(10).background(style.tile, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(c.info.name), \(more)")
    }
    func search() {
        let q = query.trimmingCharacters(in: .whitespaces); guard !q.isEmpty, let c = console(pick.rom.console) else { return }
        searching = true; found = []
        Lookup.queue.async { let r = (try? Lookup.search(q, c)) ?? []; DispatchQueue.main.async { found = r; searching = false } }
    }
}

// What the game list knows, beside the game
struct GameAbout: View {
    private let look = style
    let info: GameInfo
    @State private var more = false
    var body: some View {
        if let a = info.about {
            VStack(alignment: .leading, spacing: 6) {
                Text("About").font(.callout.weight(.semibold)).foregroundStyle(style.text).accessibilityAddTraits(.isHeader)
                Text(a).font(.caption).foregroundStyle(style.soft).lineLimit(more ? nil : 6).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                HStack {
                    if a.count > 280 { Button(more ? "Less" : "More") { more.toggle() }.buttonStyle(.plain).font(.caption).foregroundStyle(style.accent) }
                    Spacer()
                    if let f = info.aboutFrom, let u = URL(string: f) { Button("From Wikipedia") { NSWorkspace.shared.open(u) }.buttonStyle(.plain).font(.caption).foregroundStyle(style.accent).help("Text under CC BY-SA 4.0") }
                    else { Text("From libretro's game list").font(.caption).foregroundStyle(style.soft) }
                }
            }
        }
    }
}
