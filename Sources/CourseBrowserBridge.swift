import Foundation

// The page shown inside the game window. Docked writes it into a small folder
// the game host reads; Docked's macOS File menu launches the game with that
// folder, and the host shows the page when the window is ready. There is no
// in-game key. No account, no Nintendo connection, no uploads, no
// save writes from the page: every course change goes through Docked's checker.
enum SMM2WebPage {
    static let html = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=1280, initial-scale=1">
<title>Course Browser</title>
<style>
 :root { --ink:#101624; --paper:#f5f0e4; --panel:#1d2940; --line:#344765; --chalk:#f7f4ec; --muted:#a8b3c9; --gold:#ffd166; --mint:#66d9b0; --warn:#ff9b89; --blue:#66a9ff; }
 * { box-sizing:border-box }
 html,body { margin:0; height:100%; background:var(--ink); color:var(--chalk); font-family:"Avenir Next","SF Pro Text",system-ui,sans-serif; font-size:15px }
 body { display:grid; grid-template-rows:60px 1fr 92px; overflow:hidden }
 header { display:flex; align-items:center; gap:14px; padding:0 20px; background:#111a2b; border-bottom:1px solid var(--line) }
 .brand { display:flex; align-items:baseline; gap:10px }
 h1 { font-size:22px; letter-spacing:.01em; margin:0; font-weight:680 }
 .brand em { font-style:normal; font-size:12px; color:var(--gold); border:1px solid var(--gold); border-radius:2px; padding:3px 7px; letter-spacing:.08em; text-transform:uppercase }
 .hint { color:var(--muted); font-size:12px; white-space:nowrap }
 .hint b { color:var(--gold); font-weight:650 }
 .find { margin-left:auto; display:flex; gap:6px; align-items:center }
 .find input { width:240px; background:#0a1120; border:1px solid var(--line); border-radius:3px; padding:8px 10px; color:var(--chalk); font:inherit; outline:none }
 .find input:focus,button:focus,select:focus { outline:2px solid var(--gold); outline-offset:1px }
 button,select { font:inherit; color:var(--chalk); background:#26375a; border:1px solid var(--line); border-radius:3px; padding:8px 11px; cursor:pointer }
 button:hover:not(:disabled) { background:#33476f }
 button:disabled { opacity:.4; cursor:default }
 button.primary { background:var(--gold); color:#1a1302; border-color:var(--gold); font-weight:680 }
 button.primary:hover:not(:disabled) { background:#ffe3a3 }
 body>main { display:grid; grid-template-columns:minmax(0,1fr) 390px; min-height:0; background:#0e1523 }
 #catalog { overflow:auto; padding:20px 22px 28px; scrollbar-color:var(--line) transparent }
 .hello { display:flex; align-items:flex-end; justify-content:space-between; gap:20px; margin-bottom:18px }
 .hello h2 { font-size:27px; margin:0 0 5px; font-weight:680; letter-spacing:-.01em }
 .hello p { margin:0; color:var(--muted); font-size:13px; max-width:620px; line-height:1.45 }
 .shelf { margin:0 0 26px }
 .shelf-head { display:flex; align-items:baseline; justify-content:space-between; gap:12px; margin:0 0 9px }
 .shelf-head h2 { font-size:17px; margin:0; font-weight:660 }
 .shelf-head h2::before { content:""; display:inline-block; width:5px; height:17px; background:var(--gold); margin-right:9px; vertical-align:-2px }
 .shelf-head span { color:var(--muted); font-size:12px }
 .rail { display:flex; gap:12px; overflow:auto; padding:2px 2px 10px; scrollbar-color:var(--line) transparent }
 .card { flex:0 0 214px; background:var(--panel); border:1px solid var(--line); border-radius:5px; padding:0; text-align:left; overflow:hidden; color:var(--chalk) }
 .card[aria-pressed="true"] { border-color:var(--mint); box-shadow:0 0 0 1px var(--mint) }
 .card-art { height:112px; width:100%; display:flex; align-items:center; justify-content:center; background:#08101d; overflow:hidden }
 .card-art img,.card-art svg { width:100%; height:100%; display:block; object-fit:cover }
 .card-art.blank { color:var(--muted); font-size:12px; text-align:center; padding:12px; line-height:1.4 }
 .card-body { padding:9px 10px 11px }
 .card-body b { display:block; font-size:14px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; margin-bottom:4px }
 .card-body small { display:block; color:var(--muted); font-size:11px; line-height:1.5 }
 .code { font-family:ui-monospace,Menlo,monospace; color:var(--mint) }
 .likes { color:var(--gold) }
 aside { border-left:1px solid var(--line); background:#141e31; padding:18px; overflow:auto; min-height:0 }
 aside h2 { font-size:12px; color:var(--gold); letter-spacing:.1em; text-transform:uppercase; margin:0 0 10px }
 #big { height:230px; background:#08101d; border:1px solid var(--line); border-radius:4px; display:flex; align-items:center; justify-content:center; overflow:hidden }
 #big img,#big svg { width:100%; height:100%; object-fit:contain }
 #big .blank { color:var(--muted); font-size:13px; text-align:center; padding:20px; line-height:1.5 }
 #honesty { color:var(--muted); font-size:12px; margin:9px 0 14px; line-height:1.45; min-height:34px }
 #title { font-size:20px; font-weight:680; margin:0 0 4px }
 #ident { font-family:ui-monospace,Menlo,monospace; color:var(--mint); font-size:13px; margin-bottom:10px }
 #facts { color:var(--chalk); font-size:13px; line-height:1.7 }
 #about { color:var(--muted); font-size:13px; line-height:1.5; margin-top:10px }
 label { display:block; color:var(--muted); font-size:12px; margin:15px 0 5px }
 select { width:100%; background:#0a1120 }
 footer { display:grid; grid-template-columns:minmax(0,1fr) auto; gap:18px; align-items:center; padding:12px 20px; background:#111a2b; border-top:1px solid var(--line) }
 #note { color:var(--muted); font-size:12px; line-height:1.5 }
 #note.warn { color:var(--warn) }
 .actions { display:flex; align-items:center; gap:8px }
 .actions select { width:auto; min-width:190px; margin:0 }
</style>
</head>
<body>
<header>
  <div class="brand"><h1>Course Browser</h1><em>SMM2</em></div>
  <div class="hint">Opened from Docked's macOS File menu only</div>
  <div class="find"><input id="q" type="search" placeholder="Find a name or ID (optional)" aria-label="Find a course"><button id="find">Find</button></div>
</header>
<main>
  <div id="catalog">
    <div class="hello"><div><h2>Browse public courses</h2><p>Start with Popular or New uploads, then scroll any category shelf. Choose a course to put into an existing Downloaded Course slot. This is a public archive browser, not Nintendo Course World.</p></div></div>
    <div id="shelves"></div>
  </div>
  <aside aria-label="Chosen course">
    <h2>Chosen course</h2>
    <div id="big"><div class="blank">Choose a course to see its real preview.</div></div>
    <div id="honesty"></div>
    <p id="title">Nothing chosen yet.</p>
    <div id="ident"></div>
    <div id="facts"></div>
    <div id="about"></div>
    <label for="slot">Downloaded Course slot</label>
    <select id="slot"></select>
  </aside>
</main>
<footer>
  <div id="note">Opened only from Docked's macOS File menu. Docked never signs in, contacts Nintendo or uploads your save. A chosen course is queued while the game runs; save and quit, and Docked checks the game is closed, backs up the save, then replaces only that course's .bcd. Coursebot keeps the slot's old thumbnail, title, maker and stats.</div>
  <div class="actions">
    <button id="cancel">Cancel queue</button>
    <button id="play">Play in SMM2</button>
    <button id="put" class="primary" disabled>Put in Coursebot</button>
    <button id="close">Close</button>
  </div>
</footer>
<script>
(function () {
  var seq = 0, waiting = {}, state = { shelves: [], courses: {}, selected: null, previewFor: null, slots: [], note: '', queued: false };
  var $ = function (id) { return document.getElementById(id); };
  function send(o) { o.id = ++seq; waiting[o.id] = o.cmd; try { window.nx.sendMessage(JSON.stringify(o)); } catch (e) { note('The game page could not reach Docked.', true); } }
  function note(text, warn) { $('note').textContent = text || "Opened only from Docked's macOS File menu. Docked never signs in, contacts Nintendo or uploads your save."; $('note').className = warn ? 'warn' : ''; }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]; }); }
  function remember(course) { state.courses[course.dataID] = course; }
  function art(p) {
    if (!p) return '<div class="blank">No preview exists for this course.</div>';
    if (p.kind === 'thumbnail') return '<img alt="Real thumbnail" src="' + p.image + '">';
    if (p.kind === 'map') return p.svg;
    return '<div class="blank">No preview exists: no picture and no readable level data.</div>';
  }
  function honesty(p) { return p && p.honesty ? p.honesty : 'No preview exists for this course. Its details are still real.'; }
  function renderShelves() {
    if (!state.shelves.length) { $('shelves').innerHTML = '<div class="hello"><p>Loading courses from the public archive…</p></div>'; return; }
    $('shelves').innerHTML = state.shelves.map(function (s) {
      if (!s.courses.length) return '';
      return '<section class="shelf"><div class="shelf-head"><h2>' + esc(s.title) + '</h2><span>' + esc(s.subtitle) + '</span></div><div class="rail">' +
        s.courses.map(function (c) {
          var bits = [c.style, c.theme].filter(Boolean).join(' · ');
          return '<button class="card" data-id="' + c.dataID + '" aria-pressed="' + (state.selected === c.dataID) + '">' +
            '<div class="card-art">' + art(c.preview) + '</div><div class="card-body"><b>' + esc(c.name || 'Untitled course') + '</b>' +
            '<small><span class="code">' + esc(c.id) + '</span><br>' + esc(c.author || 'Unknown maker') + '<br>' +
            '<span class="likes">' + (c.likes != null ? esc(c.likes) + ' likes' : 'no like count') + '</span> · ' + esc(bits) + '</small></div></button>';
        }).join('') + '</div></section>';
    }).join('') || '<div class="hello"><p>The archive answered, but no courses were in these shelves. Try Find above.</p></div>';
    Array.prototype.forEach.call(document.querySelectorAll('.card'), function (b) {
      b.addEventListener('click', function () { select(Number(b.dataset.id)); });
    });
  }
  function renderPreview(c) {
    $('big').innerHTML = art(c.preview);
    $('honesty').textContent = honesty(c.preview);
    $('title').textContent = c.name || 'Untitled course';
    $('ident').textContent = c.id;
    var facts = [c.style, c.theme, c.difficulty].filter(Boolean);
    if (c.likes != null) facts.push(c.likes + ' likes');
    if (c.plays != null) facts.push(c.plays + ' plays');
    $('facts').textContent = facts.join('  ·  ');
    $('about').textContent = c.description || '';
  }
  function select(dataID) {
    var c = state.courses[dataID]; if (!c) return;
    state.selected = dataID; state.previewFor = dataID;
    renderShelves(); renderPreview(c);
    $('put').disabled = !$('slot').value;
    send({ cmd: 'select', dataID: dataID });
  }
  function handle(m) {
    var cmd = m.cmd;
    if (cmd === 'hello') {
      state.slots = m.slots || []; state.queued = !!m.queued;
      $('slot').innerHTML = state.slots.map(function (s) { return '<option value="' + s + '">Downloaded Course ' + String(s).padStart(3, '0') + '</option>'; }).join('');
      note(m.note || '', !m.ok); send({ cmd: 'catalog' });
      return;
    }
    if (cmd === 'catalog' || cmd === 'search' || cmd === 'lookup') {
      if (cmd === 'catalog') {
        state.shelves = m.shelves || [];
        state.shelves.forEach(function (s) { (s.courses || []).forEach(remember); });
      } else {
        var found = (m.courses || []).map(function (c) { remember(c); return c; });
        state.shelves = [{ id: 'search', title: 'Found courses', subtitle: 'Your search in the public archive', courses: found }].concat(state.shelves.filter(function (s) { return s.id !== 'search'; }));
      }
      state.selected = null; state.previewFor = null;
      renderShelves();
      $('big').innerHTML = '<div class="blank">Choose a course to see its real preview.</div>';
      $('honesty').textContent = ''; $('title').textContent = 'Nothing chosen yet.'; $('ident').textContent = ''; $('facts').textContent = ''; $('about').textContent = '';
      $('put').disabled = true;
      note(m.note || (cmd === 'catalog' ? 'Scroll the shelves to browse.' : 'Courses found.'), !m.ok);
      var first = state.shelves.filter(function (s) { return s.courses && s.courses.length; })[0];
      if (first) select(first.courses[0].dataID);
      return;
    }
    if (cmd === 'select') {
      if (m.dataID != null && m.dataID !== state.previewFor) return;
      if (m.ok && m.preview && state.courses[m.dataID]) { state.courses[m.dataID].preview = m.preview; renderPreview(state.courses[m.dataID]); }
      else note(m.note || 'That course has no picture; its details are still shown.', true);
      return;
    }
    if (cmd === 'slots') {
      state.slots = m.slots || []; state.queued = !!m.queued;
      $('slot').innerHTML = state.slots.map(function (s) { return '<option value="' + s + '">Downloaded Course ' + String(s).padStart(3, '0') + '</option>'; }).join('');
      $('put').disabled = !state.selected || !state.slots.length;
      note(m.note || '', !m.ok);
      return;
    }
    if (cmd === 'inject') {
      state.queued = m.queued || state.queued;
      note(m.note || '', !m.ok);
      if (m.ok) $('put').textContent = 'Queue another course';
      return;
    }
    if (cmd === 'cancel') { state.queued = false; note(m.note || '', !m.ok); $('put').textContent = 'Put in Coursebot'; return; }
    if (cmd === 'close') { window.nx.endApplet(); return; }
    if (m.note) note(m.note, m.ok === false);
  }
  window.nx.addEventListener('message', function (e) {
    var m; try { m = JSON.parse(e.data); } catch (err) { return; }
    if (m && m.cmd) handle(m);
  });
  $('find').addEventListener('click', function () { var q = $('q').value.trim(); if (q) { note('Searching the public archive…'); send({ cmd: 'search', q: q }); } });
  $('q').addEventListener('keydown', function (e) { if (e.key === 'Enter') $('find').click(); });
  $('slot').addEventListener('change', function () { $('put').disabled = !$('slot').value || !state.selected; });
  $('put').addEventListener('click', function () {
    if (state.selected && $('slot').value) send({ cmd: 'inject', dataID: state.selected, slot: Number($('slot').value) });
  });
  $('cancel').addEventListener('click', function () { send({ cmd: 'cancel' }); });
  $('play').addEventListener('click', function () { send({ cmd: 'play' }); });
  $('close').addEventListener('click', function () { send({ cmd: 'close' }); });
  send({ cmd: 'hello' });
})();
</script>
</body>
</html>
"""#
}

// The folder the game host reads. It holds only the page and small JSON
// messages; the save is never in it. Docked writes here, the game reads here.
enum SMM2WebBridge {
    enum Direction: String { case toGame = "to-game", toDocked = "to-docked" }

    static func folder(_ titleID: String) -> URL {
        GameData.support.appendingPathComponent(titleID.uppercased()).appendingPathComponent("course-browser")
    }

    @discardableResult
    static func prepare(_ titleID: String) -> URL? {
        let dir = folder(titleID), fm = FileManager.default
        for sub in ["", Direction.toGame.rawValue, Direction.toDocked.rawValue, "html"] {
            let u = dir.appendingPathComponent(sub)
            try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        }
        // A new run starts with an empty mailbox. Stale requests from a game
        // that was killed mid-browse must not be answered twice.
        for d in [Direction.toGame, Direction.toDocked] {
            let u = dir.appendingPathComponent(d.rawValue)
            for f in ((try? fm.contentsOfDirectory(atPath: u.path)) ?? []) where f.hasSuffix(".json") {
                try? fm.removeItem(at: u.appendingPathComponent(f))
            }
        }
        guard (try? SMM2WebPage.html.write(to: dir.appendingPathComponent("html/index.html"), atomically: true, encoding: .utf8)) != nil else { return nil }
        return dir
    }

    static func json(_ object: [String: Any]) -> Data? {
        (try? JSONSerialization.data(withJSONObject: object, options: []))
    }

    @discardableResult
    static func send(_ object: [String: Any], in dir: URL) -> Bool {
        guard let data = json(object) else { return false }
        let to = dir.appendingPathComponent(Direction.toGame.rawValue)
        let name = String(format: "%020d-%@.json", Int(Date().timeIntervalSince1970 * 1_000_000), UUID().uuidString)
        let tmp = to.appendingPathComponent("." + name + ".tmp"), final = to.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
        do {
            try data.write(to: tmp, options: .atomic)
            try FileManager.default.moveItem(at: tmp, to: final)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }

    // Oldest first. A request is removed only after Docked has read it, so a
    // half-written file is never mistaken for a complete one.
    static func requests(in dir: URL) -> [[String: Any]] {
        let fm = FileManager.default, from = dir.appendingPathComponent(Direction.toDocked.rawValue)
        let names = ((try? fm.contentsOfDirectory(atPath: from.path)) ?? []).filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.sorted()
        var out: [[String: Any]] = []
        for name in names {
            let u = from.appendingPathComponent(name)
            let object = (try? Data(contentsOf: u)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            try? fm.removeItem(at: u)   // even a broken request is consumed, so it cannot be read twice
            guard let object else { continue }
            out.append(object)
        }
        return out
    }

    static func reply(_ id: Int?, _ body: [String: Any]) -> [String: Any] {
        var r = body
        if let id { r["id"] = id }
        if r["ok"] == nil { r["ok"] = true }
        return r
    }

    static func courseJSON(_ c: SMM2Course) -> [String: Any] {
        var r: [String: Any] = ["dataID": c.dataID, "id": c.courseID, "name": c.name,
                                "author": c.author, "style": c.style, "theme": c.theme,
                                "difficulty": c.difficulty, "description": c.description,
                                // A card's picture is either a real thumbnail, a drawing
                                // from this course's own bytes, or an honest "none".
                                "preview": SMM2WebPreview.json(for: c)]
        if let likes = c.likes { r["likes"] = likes }
        if let plays = c.plays { r["plays"] = plays }
        if let uploaded = c.uploaded { r["uploaded"] = uploaded }
        return r
    }

    static func catalogJSON(_ shelves: [(SMM2Shelf, [SMM2Course])]) -> [String: Any] {
        ["cmd": "catalog", "ok": true, "shelves": shelves.map { shelf, courses in
            ["id": shelf.rawValue, "title": shelf.title, "subtitle": shelf.subtitle,
             "courses": courses.map(courseJSON(_:))]
        }]
    }
}

// A command from the page is validated before it can reach a save. Unknown
// commands, empty text and slots outside Downloaded Courses are refused here.
enum SMM2WebCommand {
    case hello, catalog, search(String), lookup(String), select(UInt32), slots
    case inject(UInt32, Int), cancel, close, play

    init?(_ object: [String: Any]) {
        switch object["cmd"] as? String {
        case "hello": self = .hello
        case "catalog": self = .catalog
        case "slots": self = .slots
        case "cancel": self = .cancel
        case "close": self = .close
        case "play": self = .play
        case "search":
            guard let q = (object["q"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else { return nil }
            self = .search(q)
        case "lookup":
            guard let code = (object["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else { return nil }
            self = .lookup(code)
        case "select":
            guard let id = Self.dataID(object["dataID"]) else { return nil }
            self = .select(id)
        case "inject":
            guard let id = Self.dataID(object["dataID"]), let slot = object["slot"] as? Int,
                  SMM2Slots.downloaded.contains(slot) else { return nil }
            self = .inject(id, slot)
        default: return nil
        }
    }

    private static func dataID(_ value: Any?) -> UInt32? {
        if let n = value as? NSNumber, n.intValue > 0, n.intValue <= Int(UInt32.max) { return n.uint32Value }
        if let s = value as? String, let n = UInt32(s), n > 0 { return n }
        return nil
    }
}

// Honest previews: a real thumbnail only when the source really sent a picture,
// otherwise a diagram drawn from that course's own level bytes, otherwise a
// plain statement that there is no preview. There is no placeholder artwork.
enum SMM2WebPreview {
    static func json(for course: SMM2Course, thumbnail: Data? = nil) -> [String: Any] {
        if let image = thumbnail, SMM2CoursePreview.isRealImage(image) {
            let mime = image.starts(with: [0xFF, 0xD8, 0xFF]) ? "image/jpeg" : "image/png"
            let url = "data:\(mime);base64," + image.base64EncodedString()
            return ["kind": "thumbnail", "image": url, "honesty": "Real thumbnail from the public course server."]
        }
        guard let map = SMM2CoursePreview.map(for: course), map.isUsable else {
            return ["kind": "none", "honesty": "No preview available: the archive has no image and this course has no readable level data. Only its details are shown."]
        }
        return ["kind": "map", "svg": svg(map), "honesty": "Drawn from this course's own level data — a diagram, not a game screenshot."]
    }

    // A small SVG diagram; no server, font or guessed tile art is involved.
    static func svg(_ map: SMM2CourseMap) -> String {
        let xs = [map.bounds.left, map.bounds.right, map.start.x, map.goal.x] + map.tiles.map(\.x) + map.objects.map(\.x)
        let ys = [map.bounds.top, map.bounds.bottom, map.start.y, map.goal.y] + map.tiles.map(\.y) + map.objects.map(\.y)
        let minX = xs.min() ?? 0, maxX = max(xs.max() ?? 1, minX + 1)
        let minY = ys.min() ?? 0, maxY = max(ys.max() ?? 1, minY + 1)
        let w = 860.0, h = 470.0, pad = 22.0
        let scale = min((w - pad * 2) / Double(maxX - minX), (h - pad * 2) / Double(maxY - minY))
        func x(_ v: Int) -> Double { (Double(v - minX) - Double(maxX - minX) / 2) * scale + w / 2 }
        func y(_ v: Int) -> Double { h / 2 - (Double(v - minY) - Double(maxY - minY) / 2) * scale }
        let ground = ["#c49a5b", "#7c7b9c", "#777780", "#9a6560", "#4e94b8", "#7c7b9c", "#e8f1f7", "#c49a5b", "#87c3e7", "#62a46e"]
        let unit = max(3.0, min(11.0, scale))
        var s = "<svg viewBox=\"0 0 \(Int(w)) \(Int(h))\" xmlns=\"http://www.w3.org/2000/svg\" role=\"img\" aria-label=\"Course map\">"
        s += "<rect width=\"\(Int(w))\" height=\"\(Int(h))\" fill=\"#0a1020\"/>"
        for t in map.tiles {
            let colour = ground[map.theme >= 0 && map.theme < ground.count ? map.theme : 0]
            s += "<rect x=\"\(x(t.x) - unit / 2)\" y=\"\(y(t.y) - unit / 2)\" width=\"\(unit)\" height=\"\(unit)\" fill=\"\(colour)\"/>"
        }
        for o in map.objects {
            let hcol = Double(o.kind % 13) / 13
            s += "<rect x=\"\(x(o.x) - max(unit, Double(o.width) * scale) / 2)\" y=\"\(y(o.y) - max(unit, Double(o.height) * scale) / 2)\" width=\"\(max(unit, Double(o.width) * scale))\" height=\"\(max(unit, Double(o.height) * scale))\" rx=\"2\" fill=\"hsl(\(Int(hcol * 360)),58%,72%)\"/>"
        }
        s += "<circle cx=\"\(x(map.start.x))\" cy=\"\(y(map.start.y))\" r=\"8\" fill=\"#4cc9a0\"/><text x=\"\(x(map.start.x))\" y=\"\(y(map.start.y) + 4)\" fill=\"#0a1020\" font-size=\"11\" text-anchor=\"middle\">S</text>"
        s += "<circle cx=\"\(x(map.goal.x))\" cy=\"\(y(map.goal.y))\" r=\"8\" fill=\"#ff8577\"/><text x=\"\(x(map.goal.x))\" y=\"\(y(map.goal.y) + 4)\" fill=\"#0a1020\" font-size=\"11\" text-anchor=\"middle\">G</text>"
        return s + "</svg>"
    }
}

// Only a browser session changes the game's environment. Ordinary launches get
// exactly the one variable they had before, and game settings get none.
enum SMM2WebLaunch {
    static func environment(settings: Bool, browserDir: URL?, game: URL, browserGame: URL?) -> [String: String] {
        var env: [String: String] = [:]
        guard !settings else { return env }
        env["DM_LAUNCHER"] = "0"
        if let browserDir, let browserGame, game.standardizedFileURL == browserGame.standardizedFileURL {
            env["DM_COURSE_BROWSER"] = browserDir.path
        }
        return env
    }
}

extension SMM2WebBridge {
    static func requestID(_ object: [String: Any]) -> Int? {
        if let n = object["id"] as? NSNumber { return n.intValue }
        if let s = object["id"] as? String { return Int(s) }
        return nil
    }
}
