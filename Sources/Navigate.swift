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
        switch m { case .left: return at(r, i - 1); case .right: return at(r, i + 1); case .up: return i - n >= 0 ? at(r, i - n) : c; case .down: return i + n < l.count ? at(r, i + n) : i / n < (l.count - 1) / n ? at(r, l.count - 1) : c; default: return c }
    }
    switch m { case .left: return at(r, i - 1); case .right: return at(r, i + 1); case .up: return r > 0 ? at(r - 1, i) : c; case .down: return r < rows.count - 1 ? at(r + 1, i) : c; default: return c }
}

// Couch Mode: a row of shelves, one shown at a time. Each shelf keeps its own place, so going back to it lands where the player left it.
struct CouchSpot: Equatable {
    var shelf = 0, at: [Int: Int] = [:]
    func index(_ count: Int) -> Int { min(max(at[shelf] ?? 0, 0), max(count - 1, 0)) }
}
func couchStep(_ s: CouchSpot, _ m: Move, counts: [Int]) -> CouchSpot {
    guard !counts.isEmpty else { return s }
    var s = s; s.shelf = min(max(s.shelf, 0), counts.count - 1)
    let i = s.index(counts[s.shelf])
    switch m {
    case .left: s.at[s.shelf] = max(i - 1, 0)
    case .right: s.at[s.shelf] = min(i + 1, max(counts[s.shelf] - 1, 0))
    case .up, .down, .nextSection, .previousSection:
        let wrap = m == .nextSection || m == .previousSection, d = m == .down || m == .nextSection ? 1 : -1
        var n = s.shelf
        for _ in counts.indices {   // past empty shelves; up and down stop at the ends, the shoulders go round
            n += d; if wrap { n = (n + counts.count) % counts.count } else if n < 0 || n >= counts.count { return s }
            if counts[n] > 0 { s.shelf = n; return s }
        }
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
            let m: Move? = [123: .left, 124: .right, 125: .down, 126: .up, 36: .accept, 76: .accept][Int(e.keyCode)] ?? (s.couch() ? [53: .back, 49: .play, 3: .favorite, 48: .nextSection][Int(e.keyCode)] : nil); guard let m else { return e }
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
