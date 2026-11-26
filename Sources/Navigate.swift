import AppKit
import GameController

// Moving around with a controller or the arrow keys. Nothing is polled: a controller's own events, and the keyboard's, move it.
enum Move { case left, right, up, down, accept, back, favorite, play, nextSection, previousSection, home }
struct Cursor: Equatable { var row: String, game: String }

// Where each way leads, worked out from what is on screen: rows of games, or one list folded into columns
func step(_ c: Cursor?, _ m: Move, rows: [(id: String, games: [String])], columns: Int?) -> Cursor? {
    let rows = rows.filter { !$0.games.isEmpty }; guard let first = rows.first else { return nil }
    guard let c, let r = rows.firstIndex(where: { $0.id == c.row }), let i = rows[r].games.firstIndex(of: c.game) else { return Cursor(row: first.id, game: first.games[0]) }
    let l = rows[r].games
    func at(_ r: Int, _ i: Int) -> Cursor { let g = rows[r].games; return Cursor(row: rows[r].id, game: g[min(max(i, 0), g.count - 1)]) }
    if let n = columns, n > 0 {
        // Several lists folded the same way, one under another (a grid in groups): up and down cross into the next one, in the same column.
        switch m {
        case .left: return at(r, i - 1); case .right: return at(r, i + 1)
        case .up: return i - n >= 0 ? at(r, i - n) : r > 0 ? at(r - 1, (rows[r - 1].games.count - 1) / n * n + i % n) : c
        case .down: return i + n < l.count ? at(r, i + n) : i / n < (l.count - 1) / n ? at(r, l.count - 1) : r < rows.count - 1 ? at(r + 1, i % n) : c
        default: return c
        }
    }
    switch m { case .left: return at(r, i - 1); case .right: return at(r, i + 1); case .up: return r > 0 ? at(r - 1, i) : c; case .down: return r < rows.count - 1 ? at(r + 1, i) : c; default: return c }
}

// Couch Mode: shelves across the top, several rows of games on screen, one game chosen.
// The shelf and game are remembered by name, so a refreshed library keeps the place even when shelves come and go.
struct CouchSpot: Equatable {
    var shelf = 0
    var shelfID: String?
    var at: [String: Int] = [:]         // shelf id -> game number
    var gameID: [String: String] = [:]  // shelf id -> game id
    var game: String?                   // the chosen game, even if its shelf changes
    func shelfIndex(_ rows: [(id: String, games: [String])]) -> Int {
        if let shelfID, let i = rows.firstIndex(where: { $0.id == shelfID }) { return i }
        return min(max(shelf, 0), max(rows.count - 1, 0))
    }
    func index(_ shelf: String, _ count: Int) -> Int { min(max(at[shelf] ?? 0, 0), max(count - 1, 0)) }
    func index(_ shelf: String, _ games: [String]) -> Int {
        if let id = gameID[shelf], let i = games.firstIndex(of: id) { return i }
        return index(shelf, games.count)
    }
    // A shelf can appear or disappear when a game is favorited. Follow the chosen game first, so that does not strand it.
    func resolved(_ rows: [(id: String, games: [String])]) -> CouchSpot {
        let rows = rows.filter { !$0.games.isEmpty }
        guard !rows.isEmpty else { return self }
        var s = self
        if let game, let r = rows.firstIndex(where: { $0.id == s.shelfID }), let i = rows[r].games.firstIndex(of: game) {
            s.select(rows, r, i)
        } else if let game, let r = rows.firstIndex(where: { $0.games.contains(game) }), let i = rows[r].games.firstIndex(of: game) {
            s.select(rows, r, i)
        } else {
            let r = s.shelfIndex(rows); s.select(rows, r, s.index(rows[r].id, rows[r].games))
        }
        return s
    }
    fileprivate mutating func select(_ rows: [(id: String, games: [String])], _ r: Int, _ i: Int) {
        shelf = r; shelfID = rows[r].id; at[rows[r].id] = i
        gameID[rows[r].id] = rows[r].games[i]; game = rows[r].games[i]
    }
}
func couchStep(_ s: CouchSpot, _ m: Move, rows: [(id: String, games: [String])]) -> CouchSpot {
    let rows = rows.filter { !$0.games.isEmpty }
    guard !rows.isEmpty else { return s }
    var s = s.resolved(rows)
    let r = s.shelf, shelf = rows[r], i = s.index(shelf.id, shelf.games)
    switch m {
    case .left, .right:
        s.select(rows, r, m == .left ? max(i - 1, 0) : min(i + 1, shelf.games.count - 1))
    case .up, .down:
        let n = r + (m == .down ? 1 : -1)   // up and down change row, stopping at the ends
        if rows.indices.contains(n) { s.select(rows, n, s.index(rows[n].id, rows[n].games)) }
    case .nextSection, .previousSection:
        let d = m == .nextSection ? 1 : -1  // the shoulders change shelf and go round
        let n = (r + d + rows.count) % rows.count
        s.select(rows, n, s.index(rows[n].id, rows[n].games))
    default: break
    }
    return s
}

final class Navigator {
    var act: (Move, Bool) -> Void = { _, _ in }   // and whether a controller did it
    var couch: () -> Bool = { false }   // in Couch Mode, Escape, Space and F work too
    private var keys: Any?, seen: [NSObjectProtocol] = [], repeater: DispatchSourceTimer?, held: Move?
    func start() {
        GCController.shouldMonitorBackgroundEvents = false
        let n = NotificationCenter.default
        seen = [n.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] x in (x.object as? GCController).map { self?.listen($0) } }, n.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.hold(nil) }, n.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.hold(nil) }]
        GCController.controllers().forEach(listen)
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let s = self, let w = e.window, w.attachedSheet == nil, NSApp.modalWindow == nil, w.canBecomeMain, !(w.firstResponder is NSText), e.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return e }
            let m: Move? = [123: .left, 124: .right, 125: .down, 126: .up, 36: .accept, 76: .accept][Int(e.keyCode)] ?? (s.couch() ? [53: .back, 49: .play, 3: .favorite, 48: e.modifierFlags.contains(.shift) ? .previousSection : .nextSection][Int(e.keyCode)] : nil); guard let m else { return e }
            s.act(m, false); return nil
        }
    }
    private func ready() -> Bool { NSApp.isActive && NSApp.modalWindow == nil && NSApp.mainWindow?.attachedSheet == nil }
    private func press(_ m: Move) { if ready() { act(m, true) } }
    // A direction held down goes on moving, and only while it is held is there a timer
    private func hold(_ m: Move?) {
        if m == held { return }; held = m; repeater?.cancel(); repeater = nil; guard let m, ready() else { return }
        act(m, true); let t = DispatchSource.makeTimerSource(queue: .main); t.schedule(deadline: .now() + 0.38, repeating: 0.11); t.setEventHandler { [weak self] in if self?.ready() == true { self?.act(m, true) } else { self?.hold(nil) } }; repeater = t; t.resume()
    }
    private func listen(_ c: GCController) {
        guard let g = c.extendedGamepad else { return }; c.handlerQueue = .main
        g.valueChangedHandler = { [weak self] g, _ in
            let x = abs(g.leftThumbstick.xAxis.value) > 0.6 ? g.leftThumbstick.xAxis.value : g.dpad.xAxis.value, y = abs(g.leftThumbstick.yAxis.value) > 0.6 ? g.leftThumbstick.yAxis.value : g.dpad.yAxis.value
            self?.hold(x < -0.5 ? .left : x > 0.5 ? .right : y > 0.5 ? .up : y < -0.5 ? .down : nil)
        }
        if let h = g.buttonHome { h.preferredSystemGestureState = .disabled; h.pressedChangedHandler = { [weak self] _, _, down in if down { self?.press(.home) } } }   // Home opens and closes Couch Mode
        for (b, m) in [(g.buttonA, Move.accept), (g.buttonB, .back), (g.buttonY, .favorite), (g.buttonMenu, .play), (g.rightShoulder, .nextSection), (g.leftShoulder, .previousSection)] { b.pressedChangedHandler = { [weak self] _, _, down in if down { self?.press(m) } } }
    }
}
