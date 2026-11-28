import Foundation

// The page shown inside the game window. Docked writes it into a small folder
// the game host reads; the F6 key in the game opens it through the engine's own
// web view. No account, no Nintendo connection, no uploads, no save writes from
// the page: every course change goes through Docked's checked injector.
enum SMM2WebPage {
    static let html = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=1280, initial-scale=1">
<title>Course Browser</title>
<style>
 :root { --ink:#0d1220; --panel:#151d33; --line:#2b3a5c; --chalk:#eef1f7; --muted:#9aa6c0; --gold:#ffd166; --mint:#4cc9a0; --warn:#ff8577; }
 * { box-sizing:border-box }
 html,body { margin:0; height:100%; background:var(--ink); color:var(--chalk); font-family:"Avenir Next","SF Pro Text",system-ui,sans-serif; font-size:15px }
 body { display:grid; grid-template-rows:64px 1fr 104px; background-image:linear-gradient(var(--line) 1px, transparent 1px),linear-gradient(90deg, var(--line) 1px, transparent 1px); background-size:64px 64px; background-color:var(--ink) }
 header { display:flex; align-items:center; gap:16px; padding:0 22px; background:rgba(13,18,32,.94); border-bottom:1px solid var(--line) }
 h1 { font-size:23px; letter-spacing:.02em; margin:0; font-weight:650 }
 .tag { color:var(--muted); font-size:13px; border:1px solid var(--line); padding:5px 9px; border-radius:3px }
 .hint { margin-left:auto; color:var(--muted); font-size:13px }
 main { display:grid; grid-template-columns:300px minmax(360px,1fr) 440px; gap:14px; padding:14px 18px; min-height:0; background:rgba(13,18,32,.92) }
 section { background:var(--panel); border:1px solid var(--line); border-radius:4px; padding:14px; min-height:0; display:flex; flex-direction:column }
 h2 { font-size:13px; text-transform:none; letter-spacing:.08em; color:var(--gold); margin:0 0 10px; font-weight:650 }
 label { display:block; color:var(--muted); font-size:12px; margin:8px 0 4px }
 input,select,button { font:inherit; color:var(--chalk) }
 input,select { width:100%; background:#0a1020; border:1px solid var(--line); border-radius:3px; padding:9px 10px; outline:none }
 input:focus,select:focus,button:focus { outline:2px solid var(--gold); outline-offset:1px }
 .row { display:flex; gap:8px; align-items:end }
 .row>div { flex:1 }
 button { background:#213054; border:1px solid var(--line); border-radius:3px; padding:8px 12px; cursor:pointer }
 button:hover { background:#2b3d68 }
 button.primary { background:var(--gold); color:#171202; border-color:var(--gold); font-weight:650 }
 button.primary:hover { background:#ffe19b }
 button:disabled { opacity:.45; cursor:default }
 #find,#lookup { margin-top:8px; width:100% }
 .list { overflow:auto; margin-top:10px; min-height:0; flex:1 }
 .course { display:block; width:100%; text-align:left; background:transparent; border:1px solid transparent; border-bottom-color:var(--line); border-radius:0; padding:9px 8px }
 .course[aria-pressed="true"] { border-color:var(--mint); background:#1c2c44 }
 .course b { display:block; font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap }
 .course small { color:var(--muted); font-size:12px }
 .code { font-family:ui-monospace,Menlo,monospace; color:var(--mint) }
 #preview { flex:1; min-height:0; display:flex; align-items:center; justify-content:center; background:#0a1020; border:1px solid var(--line); border-radius:3px; overflow:hidden }
 #preview svg,#preview img { max-width:100%; max-height:100%; display:block }
 .empty { color:var(--muted); text-align:center; padding:20px }
 #honesty { color:var(--muted); font-size:12px; margin-top:8px; min-height:32px }
 #facts { color:var(--chalk); font-size:13px; margin-top:6px; line-height:1.5 }
 footer { display:grid; grid-template-columns:1fr auto; gap:16px; align-items:center; padding:14px 18px; background:rgba(13,18,32,.96); border-top:1px solid var(--line) }
 #note { color:var(--muted); font-size:13px; line-height:1.45 }
 #note.warn { color:var(--warn) }
 .actions { display:flex; align-items:center; gap:10px }
 .actions select { width:auto; min-width:170px }
</style>
</head>
<body>
<header>
  <h1>Course Browser</h1>
  <span class="tag">Super Mario Maker 2 · public archive</span>
  <span class="hint">F6 opens and closes this page · B closes</span>
</header>
<main>
  <section aria-label="Find a course">
    <h2>Find a course</h2>
    <label for="q">Name, style or theme</label>
    <div class="row"><div><input id="q" type="search" placeholder="Castle puzzle"></div><button id="find">Search</button></div>
    <label for="code">Or a nine-character course ID</label>
    <div class="row"><div><input id="code" placeholder="4RF-XV8-WCG"></div><button id="lookup">Look up</button></div>
    <div class="list" id="list"><div class="empty">Search the archive, or enter a course ID.</div></div>
  </section>
  <section aria-label="Preview">
    <h2>Preview</h2>
    <div id="preview"><div class="empty">Choose a course to see its real preview.</div></div>
    <div id="honesty"></div>
    <div id="facts"></div>
  </section>
  <section aria-label="About this course">
    <h2>Details</h2>
    <div id="detail" class="empty">Nothing chosen yet.</div>
  </section>
</main>
<footer>
  <div id="note">Docked never signs in, contacts Nintendo or sends your save. A course is put in one Downloaded Course slot; its thumbnail, title, maker and play stats stay as they were.</div>
  <div class="actions">
    <label for="slot" style="margin:0">Coursebot slot</label>
    <select id="slot"></select>
    <button id="cancel">Cancel queue</button>
    <button id="put" class="primary" disabled>Put in Coursebot</button>
  </div>
</footer>
<script>
(function () {
  var seq = 0, waiting = {}, state = { courses: [], selected: null, previewFor: null, slots: [], running: true, note: '' };
  var $ = function (id) { return document.getElementById(id); };
  function send(o) { o.id = ++seq; waiting[o.id] = o.cmd; try { window.nx.sendMessage(JSON.stringify(o)); } catch (e) { note('The game page could not reach Docked.', true); } }
  function note(text, warn) { $('note').textContent = text; $('note').className = warn ? 'warn' : ''; }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]; }); }
  function renderList() {
    if (!state.courses.length) { $('list').innerHTML = '<div class="empty">No courses yet.</div>'; return; }
    $('list').innerHTML = state.courses.map(function (c) {
      var bits = [c.style, c.theme, c.difficulty].filter(Boolean).join(' · ');
      return '<button class="course" data-id="' + c.dataID + '" aria-pressed="' + (state.selected === c.dataID) + '">' +
        '<b>' + esc(c.name || 'Untitled course') + '</b><small><span class="code">' + esc(c.id) + '</span> · ' +
        esc(c.author || 'Unknown maker') + '<br>' + esc(bits) + '</small></button>';
    }).join('');
    Array.prototype.forEach.call($('list').querySelectorAll('.course'), function (b) {
      b.addEventListener('click', function () { select(Number(b.dataset.id)); });
    });
  }
  function renderPreview(r) {
    if (r.kind === 'thumbnail') $('preview').innerHTML = '<img alt="Real course thumbnail" src="' + r.image + '">';
    else if (r.kind === 'map') $('preview').innerHTML = r.svg;
    else $('preview').innerHTML = '<div class="empty">No usable preview for this course.</div>';
    $('honesty').textContent = r.honesty || '';
  }
  function select(id) {
    state.selected = id; state.previewFor = id; renderList();
    var c = state.courses.filter(function (x) { return x.dataID === id; })[0];
    if (c) {
      $('detail').className = '';
      $('detail').innerHTML = '<b>' + esc(c.name || 'Untitled course') + '</b><p class="code">' + esc(c.id) + '</p>' +
        '<p>Maker: ' + esc(c.author || 'Unknown') + '</p><p>' + esc([c.style, c.theme, c.difficulty].filter(Boolean).join(' · ')) + '</p>' +
        '<p>' + (c.likes != null ? esc(c.likes) + ' likes · ' : '') + (c.plays != null ? esc(c.plays) + ' plays' : '') + '</p>' +
        '<p>' + esc(c.description || '') + '</p>';
      $('facts').textContent = c.style + ' · ' + c.theme + ' · ' + c.difficulty;
    }
    $('put').disabled = !$('slot').value;
    send({ cmd: 'select', dataID: id });
  }
  function handle(m) {
    var cmd = m.cmd, cmdOf = waiting[m.id];
    delete waiting[m.id];
    if (cmd === 'hello') {
      state.slots = m.slots || []; state.running = !!m.running;
      $('slot').innerHTML = state.slots.map(function (s) { return '<option value="' + s + '">Downloaded Course ' + String(s).padStart(3, '0') + '</option>'; }).join('');
      note(m.note || '', false);
      return;
    }
    if (cmd === 'search' || cmd === 'lookup') {
      state.courses = m.courses || []; state.selected = null; state.previewFor = null;
      renderList();
      $('preview').innerHTML = '<div class="empty">Choose a course to see its real preview.</div>';
      $('honesty').textContent = ''; $('facts').textContent = '';
      $('detail').className = 'empty'; $('detail').textContent = 'Nothing chosen yet.';
      $('put').disabled = true;
      note(m.note || (state.courses.length + ' courses found.'), !m.ok);
      if (state.courses.length) select(state.courses[0].dataID);
      return;
    }
    if (cmd === 'select') {
      if (m.dataID != null && m.dataID !== state.previewFor) return;   // ignore a slow answer for another course
      if (m.ok) renderPreview(m.preview); else note(m.note || 'No preview is available.', true);
      return;
    }
    if (cmd === 'slots') {
      state.slots = m.slots || []; state.running = !!m.running;
      $('slot').innerHTML = state.slots.map(function (s) { return '<option value="' + s + '">Downloaded Course ' + String(s).padStart(3, '0') + '</option>'; }).join('');
      $('put').disabled = !state.selected || !state.slots.length;
      note(m.note || '', false);
      return;
    }
    if (cmd === 'inject' || cmd === 'cancel') { note(m.note || '', !m.ok); if (m.note && /queued|Done/i.test(m.note)) $('put').textContent = 'Queue another course'; return; }
    if (cmd === 'close') { window.nx.endApplet(); return; }
    if (cmdOf === 'select' && m.ok) return;
    note(m.note || 'Docked could not answer that request.', true);
  }
  window.nx.addEventListener('message', function (e) {
    var m; try { m = JSON.parse(e.data); } catch (err) { return; }
    if (m && m.cmd) handle(m);
  });
  window.nx.footer.setAssign('B', 'Close Browser', function () { send({ cmd: 'close' }); });
  $('find').addEventListener('click', function () { var q = $('q').value.trim(); if (q) { note('Searching the archive…'); send({ cmd: 'search', q: q }); } });
  $('q').addEventListener('keydown', function (e) { if (e.key === 'Enter') $('find').click(); });
  $('lookup').addEventListener('click', function () { var c = $('code').value.trim(); if (c) { note('Looking up that course…'); send({ cmd: 'lookup', code: c }); } });
  $('code').addEventListener('keydown', function (e) { if (e.key === 'Enter') $('lookup').click(); });
  $('slot').addEventListener('change', function () { $('put').disabled = !$('slot').value || !state.selected; });
  $('put').addEventListener('click', function () {
    if (state.selected && $('slot').value) send({ cmd: 'inject', dataID: state.selected, slot: Number($('slot').value) });
  });
  $('cancel').addEventListener('click', function () { send({ cmd: 'cancel' }); });
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
        // that was killed mid-search must not be answered twice.
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
                                "difficulty": c.difficulty, "description": c.description]
        if let likes = c.likes { r["likes"] = likes }
        if let plays = c.plays { r["plays"] = plays }
        return r
    }
}

// A command from the page is validated before it can reach a save. Unknown
// commands, empty text and slots outside Downloaded Courses are refused here.
enum SMM2WebCommand {
    case hello, search(String), lookup(String), select(UInt32), slots
    case inject(UInt32, Int), cancel, close

    init?(_ object: [String: Any]) {
        switch object["cmd"] as? String {
        case "hello": self = .hello
        case "slots": self = .slots
        case "cancel": self = .cancel
        case "close": self = .close
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

