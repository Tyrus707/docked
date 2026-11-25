import CryptoKit
import Foundation
import ImageIO
var passed = 0, failed = 0
func check(_ ok: Bool, _ what: String) { if ok { passed += 1 } else { failed += 1; print("FAIL:", what) } }
func fails2(_ what: String, _ f: () throws -> Void) { do { try f(); check(false, what) } catch { check(error is RetroError, what) } }
func fails(_ e: InputError, _ what: String, _ f: () throws -> Void) { do { try f(); check(false, what) } catch { check(error as? InputError == e, what) } }
let fm = FileManager.default
let tmp = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOCKSIDE_ROOT"]!)   // a temporary folder
func mk(_ p: String, _ s: String = "x") -> URL { let u = tmp.appendingPathComponent(p); try! fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try! Data(s.utf8).write(to: u); return u }

// events
check(EngineEvent.parse(#"{"ev":"stage","t":1,"k":2,"n":9,"name":"Extract","step":""}"#) == .stage(k: 2, n: 9, name: "Extract"), "stage")
check(EngineEvent.parse(#"{"ev":"progress","frac":null,"eta":null,"note":""}"#) == .progress(frac: nil, eta: nil, note: ""), "null progress")
check(EngineEvent.parse(#"{"ev":"progress","frac":0.5,"eta":12,"note":"n"}"#) == .progress(frac: 0.5, eta: 12, note: "n"), "progress")
check(EngineEvent.parse("not json") == nil && EngineEvent.parse(#"{"ev":"future"}"#) == nil, "unknown ignored")
var lb = LineBuffer(); let bytes = Data("é1\nab".utf8)
check(lb.append(bytes.prefix(1)).isEmpty, "half character held"); check(lb.append(bytes.dropFirst()) == ["é1"], "line joined"); check(lb.append(Data("c\n".utf8)) == ["abc"], "rest")

// inputs
let base = mk("dl/Game One [v0].nsp"), upd = mk("dl/Game One [v1].NSP"), other = mk("dl/Other.nsp"), txt = mk("dl/a.txt"), nup = mk("dl/B.nup")
let r = try! resolveInput([base, upd])
check(Set(try! fm.contentsOfDirectory(atPath: r.path.path)) == [base.lastPathComponent, upd.lastPathComponent], "only chosen files staged"); check(r.needsKeys, "packages need keys")
check(!r.path.path.contains(other.lastPathComponent) && !r.key.contains(" "), "key has no spaces")
check(buildKey([base, upd]) == buildKey([upd, base]).replacingOccurrences(of: "GameOnev1", with: "GameOnev0"), "key order"); check(buildKey([base]) != buildKey([other]), "keys differ")
let again = try! resolveInput([base, upd]); check(again == r && fm.fileExists(atPath: base.path), "adding twice is safe, originals stay")
let n = try! resolveInput([nup]); check(n.path == nup && !n.needsKeys, "nup needs no keys")
_ = mk("dump/base/exefs/main"); check(try! resolveInput([tmp.appendingPathComponent("dump")]).needsKeys == false, "dump folder")
fails(.unsupported, "text refused") { _ = try resolveInput([txt]) }; fails(.mixed, "mixed refused") { _ = try resolveInput([base, txt]) }
fails(.missing, "missing refused") { _ = try resolveInput([tmp.appendingPathComponent("none.nsp")]) }
fails(.unsupported, "empty folder refused") { let d = tmp.appendingPathComponent("e"); try fm.createDirectory(at: d, withIntermediateDirectories: true); _ = try resolveInput([d]) }
let a = buildArguments(r, keys: "/k y/prod.keys"); check(a.contains("/k y/prod.keys") && a.contains("mac-app"), "arguments"); check(!buildArguments(n, keys: "/k").contains("-k"), "nup gets no keys")
check(!isTested("../../x") && !isTested(""), "bad title IDs refused")

// library
let app = mk("Games/Foo.app/Contents/Info.plist", #"<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleName</key><string>Foo</string><key>DMTitleID</key><string>0100000000010000</string></dict></plist>"#)
_ = app; _ = mk("Games/NotAGame.app/Contents/Info.plist", "<plist><dict/></plist>"); _ = mk("Games/x_build/f")
check(scanLibrary().map(\.name) == ["Foo"], "library shows only games")

// running an engine: success, failure, cancel, crash, fails to start
func drive(_ script: String, cancelAfter: Double? = nil, exe: String = "/bin/sh") -> Builder {
    let b = Builder(); var done = false; b.onFinish = { done = true }
    b.launch(exe: exe, args: ["-c", script], title: "t")
    if b.error != nil { return b }
    if let c = cancelAfter { DispatchQueue.main.asyncAfter(deadline: .now() + c) { b.cancel() } }
    let end = Date().addingTimeInterval(15); while !done && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    check(done, "engine run ended"); return b
}
var b = drive(#"echo '{"ev":"stage","k":1,"n":2,"name":"A"}'; echo '{"ev":"game","title_id":"0100000000010000","name":"Real Name","out":"x"}'; echo '{"ev":"say","msg":"hi"}'"#)
check(b.stage == "Done" && b.title == "Real Name" && b.log.contains("hi") && b.error == nil && !b.running, "success")
check(b.tested == false, "untested flagged")
b = drive(#"echo '{"ev":"say","msg":"[RED] prod.keys is wrong"}'; exit 1"#); check(b.error == "prod.keys is wrong" && b.stage == "Failed", "engine error shown")
b = drive("echo boom >&2; exit 1"); check(b.error?.contains("boom") == true, "crash text shown")
b = drive("trap 'exit 143' TERM; while :; do sleep 0.1; done", cancelAfter: 0.5); check(b.stage == "Stopped" && b.error == nil, "cancel")
b = drive("", exe: "/nonexistent"); check(b.error != nil && !b.running, "missing engine")
// the licence command must not depend on xcode-select (sudo drops DEVELOPER_DIR)
let lic = runChecks().first { $0.title.contains("licence") }!
check(lic.fix == "sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license", "licence command names Xcode itself")

// reviewing files before converting
func P(_ n: String) -> Part { Part(tmp.appendingPathComponent("rv/" + n)) }
let gB = "Game X [01006F8002326000][v0].nsp", gU = "Game X [01006F8002326800][v2228224].nsp", gD = "Game X - Paradise [01006F80023273E8][v0].nsp"
check(P(gB).kind == .base && P(gB).version == 0, "base"); check(P(gU).kind == .update && P(gU).version == 2228224, "update"); check(P(gD).kind == .dlc, "dlc")
check(Set([gB, gU, gD].map { P($0).family }) == ["01006F8002326000"], "one family"); check(P("plain.nsp").kind == .unknown && P("plain.nsp").family == nil, "no ID")
func R(_ n: [String]) -> Review { var r = Review(parts: []); r.add(n.map { tmp.appendingPathComponent("rv/" + $0) }); return r }
check(R([]).blocker != nil, "empty blocked"); check(R([gD]).blocker?.contains("main game") == true, "DLC alone blocked"); check(R([gU, gD]).blocker?.contains("main game") == true, "update without base blocked")
check(R([gB, "Other [0100000000010000][v0].nsp"]).blocker?.contains("different games") == true, "two games blocked"); check(R([gB, "x.nup"]).blocker != nil && R(["x.nup"]).blocker == nil, "nup alone")
check(R([gD, gU, gB]).parts.map(\.kind) == [.base, .update, .dlc], "sorted"); check(R([gB, gB]).parts.count == 1, "duplicates ignored"); check(R(["plain.nsp"]).blocker == nil, "unnamed allowed")
_ = mk("engine/dm/games/01006F8002326000/game.tsv", "title_id\t01006F8002326000\nbuild\tv2228224\t3.0.3\tmain=ff\n")
check(testedVersions("01006F8002326000") == [2228224: "3.0.3"], "tested versions read")
check(R([gB]).notes.contains { $0.1 && $0.0.contains("3.0.3") && $0.0.contains("no update") }, "base alone warns"); check(R([gB, gU, gD]).notes.map(\.1) == [false], "full set has no warnings")
check(R([gB, gU.replacingOccurrences(of: "2228224", with: "65536")]).notes.contains { $0.1 && $0.0.contains("different version") }, "other update warns")
check(R(["U [0100AAAAAAAAA000][v0].nsp"]).notes.contains { $0.1 && $0.0.contains("Nobody") } || R(["U [0100AAAAAAAAA000][v0].nsp"]).family == nil, "untested warns")
check(buildFolderKey("01006F8002326000") == "01006F8002326000", "new game: title ID folder")
_ = mk("Games/OldName-abc_build/profile/01006F8002326000/game.tsv"); check(buildFolderKey("01006F8002326000") == "OldName-abc", "earlier work reused")
let fb = mk("rv/" + gB), fu = mk("rv/" + gU); let ri = try! resolveInput([fb, fu], family: "01006F8002326000")
check(ri.key == "OldName-abc" && Set(try! fm.contentsOfDirectory(atPath: ri.path.path)) == [gB, gU], "all chosen files staged in one folder")
check(P(gD).label == "Game X - Paradise" && P("[v0].nsp").label == "[v0]" && P("plain.nsp").label == "plain", "readable names")

// adding an update later
let kept = keptFiles("01006F8002326000"); check(Set(kept.map(\.lastPathComponent)) == [gB, gU], "kept files found")
try! fm.removeItem(at: fb); try! fm.removeItem(at: fu)   // the originals are gone: the links are the last copies
let fd = mk("rv/" + gD, "dlc")
var later = Review(parts: []); later.add(kept); later.add([fd]); check(later.blocker == nil && later.parts.count == 3, "added to kept files")
let l1 = try! resolveInput(later.parts.map(\.url), family: later.family)
check(Set(try! fm.contentsOfDirectory(atPath: l1.path.path)) == [gB, gU, gD] && l1.path == ri.path, "update added in the same folder")
check((try? String(contentsOf: l1.path.appendingPathComponent(gB), encoding: .utf8)) == "x", "last copy of the game survives")
check(!fm.fileExists(atPath: l1.path.path + ".new"), "no half-made folder left")
var again2 = Review(parts: []); again2.add(keptFiles("01006F8002326000")); again2.add([fd]); check(again2.parts.count == 3, "same file again isn't added twice")
_ = try? resolveInput(again2.parts.map(\.url) + [tmp.appendingPathComponent("gone.nsp")], family: again2.family)
check(Set(try! fm.contentsOfDirectory(atPath: l1.path.path)) == [gB, gU, gD], "a failed add leaves the files alone")
check(keptFiles("0100BBBBBBBBA000").isEmpty, "nothing kept for an unknown game")

// time remaining
let es = Estimator()
check(es.whole(quick: false) == 880 && es.whole(quick: true) == 398, "whole conversion, every step included")
check(es.remaining(step: "Mac shaders", elapsed: 100, engineETA: nil) == 742, "this step plus all later steps"); check(es.remaining(step: "Mac shaders", elapsed: 100, engineETA: 60) == 602, "engine figure preferred"); check(es.remaining(step: "Mac shaders", elapsed: 100, engineETA: 60, quick: true) == 120, "quick leaves the pipeline out")
check(es.remaining(step: "Mac app", elapsed: 10, engineETA: nil) == 25, "last step"); check(es.remaining(step: "extract v2228224", elapsed: 0, engineETA: nil) == 880, "versions are one kind of step"); check(es.remaining(step: "extract DLC", elapsed: 0, engineETA: 10) == 884, "DLC step")
check(es.remaining(step: "Pipeline archive", elapsed: 80, engineETA: nil) == 437 && es.remaining(step: "Pipeline archive", elapsed: 80, engineETA: nil, pipelineLeft: 100) == 137, "the pipeline step: its own count, then the rest")
for n in ["Pipeline archive", "Prewarm pipelines", "Pipeline prebuild", "NRO capture", "Mac shaders", "Mac app", "extract v0", ""] { for t in [0.0, 5, 300, 4000, 90000] { for e in [nil, 0, 30, Double.infinity, .nan, -5] as [Double?] { let r = es.remaining(step: n, elapsed: t, engineETA: e); if !(r >= 0 && r.isFinite) { check(false, "\(n) \(t) \(String(describing: e))") } } } }; check(true, "always a number, whatever the step")
check(es.remaining(step: "Pipeline archive", elapsed: 1000, engineETA: nil) == 237 && es.remaining(step: "NRO capture", elapsed: 1, engineETA: nil) == 884, "past its usual time, or never seen: still a total")
var le = es; le.learn([("Mac shaders", 500), ("Mac app", 0.4), ("New step", 30)]); check(le.seconds["Mac shaders"] == 400 && le.seconds["Mac app"] == 35 && le.seconds["New step"] == 30, "learns real work only")
check(timeLeftText(30) == "Estimated time remaining: less than a minute" && timeLeftText(301) == "Estimated time remaining: about 6 min" && timeLeftText(4000)!.hasSuffix("1 h 7 min") && timeLeftText(nil) == nil, "wording"); check(elapsedText(30) == "Started just now" && elapsedText(125) == "Running for 2 min", "elapsed")
// iPhone conversions count their own steps, and nothing of the Mac's
check(es.whole(quick: false, phone: true) == 958 && es.remaining(step: "iOS shaders", elapsed: 100, engineETA: 2000, phone: true) == 2320, "iPhone: shaders, then the app and its package")
check(es.remaining(step: "app build", elapsed: 20, engineETA: nil, phone: true) == 300 && es.remaining(step: "IPA pack", elapsed: 0, engineETA: 10, phone: true) == 10 && es.whole(quick: false) == 880, "to the last step, and the Mac's unchanged")
do { var l = es; l.learn([("iOS shaders", 1400)]); check(l.seconds["iOS shaders"] == 1400 && l.whole(quick: false, phone: true) == 1758, "learns the iPhone's steps too") }
do { // one bar: never back, never full before the end
    let o = Builder(); check(o.overall() == 0, "nothing before a start"); o.running = true; o.started = Date().addingTimeInterval(-100); var last = 0.0, ok = true
    for (n, age, f) in [("extract v0", 1.0, nil), ("Mac shaders", 1, 300), ("Mac shaders", 200, 4000), ("Mac shaders", 290, 5), ("Pipeline archive", 10, nil), ("Mac app", 30, 1), ("Mac app", 300, 0)] as [(String, Double, Double?)] {
        o.handle(.stage(k: 1, n: 8, name: n)); o.stageStarted = Date().addingTimeInterval(-age); if let f { o.handle(.progress(frac: 0.5, eta: f, note: "")) }
        o.started = o.started.addingTimeInterval(-60); let v = o.overall(); if v < last || v > 0.99 || !v.isFinite { ok = false }; last = v
    }
    check(ok && last > 0.5, "the bar only ever moves forward"); o.running = false; check(o.overall() == last, "and stays put when it stops")
}
b = drive(#"echo '{"ev":"stage","k":1,"n":1,"name":"Mac shaders"}'; sleep 1; echo '{"ev":"stage_end","k":1,"name":"Mac shaders","ok":true}'; exit 1"#); check(b.remaining() == nil, "nothing left when stopped")

// finding keys
let by = tmp.appendingPathComponent("by"); check(findKeys(nil, beside: by) == nil && findKeys("/gone", beside: by) == nil, "no keys")
let kb = mk("by/prod.keys"); check(findKeys("/gone", beside: by) == kb.path, "keys beside the app"); let kr = mk("prod.keys"); check(findKeys(nil, beside: by) == kr.path, "keys in the folder"); check(findKeys(kb.path, beside: by) == kb.path, "chosen keys first")

// choosing where games go
func game(_ p: String, _ id: String, _ body: String) -> URL {
    _ = mk(p + "/Contents/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleName</key><string>G</string><key>DMTitleID</key><string>\(id)</string></dict></plist>")
    _ = mk(p + "/Contents/body", body); return tmp.appendingPathComponent(p)
}
func body(_ u: URL) -> String? { try? String(contentsOf: u.appendingPathComponent("Contents/body"), encoding: .utf8) }
func pfails(_ e: PlaceError, _ what: String, _ f: () throws -> Void) { do { try f(); check(false, what) } catch { check(error as? PlaceError == e, "\(what): \(error)") } }
let bin = tmp.appendingPathComponent("bin"); try! fm.createDirectory(at: bin, withIntermediateDirectories: true); var dropped = 0
let toBin: (URL) throws -> Void = { dropped += 1; try fm.moveItem(at: $0, to: bin.appendingPathComponent("\(dropped).app")) }
let dst = tmp.appendingPathComponent("dst"); try! fm.createDirectory(at: dst, withIntermediateDirectories: true)
let g1 = game("pl/G.app", "0100000000010000", "one"); let at = try! placeGame(g1, in: dst, discard: toBin)
check(body(at) == "one" && !fm.fileExists(atPath: g1.path) && dropped == 0, "moved"); check((try? placeGame(at, in: dst, discard: toBin)) == at && body(at) == "one", "already there is fine")
_ = game("pl/G.app", "0100000000010000", "two"); _ = try! placeGame(g1, in: dst, discard: toBin)
check(body(at) == "two" && body(bin.appendingPathComponent("1.app")) == "one", "older copy goes to the Trash, not deleted")
_ = game("pl/G.app", "0100000000099000", "other"); pfails(.taken("G.app"), "another game is never replaced") { _ = try placeGame(g1, in: dst, discard: toBin) }
check(body(at) == "two" && body(g1) == "other", "both left alone"); pfails(.missing, "missing folder") { _ = try placeGame(g1, in: tmp.appendingPathComponent("nope"), discard: toBin) }
pfails(.notWritable, "not inside an app") { _ = try placeGame(g1, in: at.appendingPathComponent("Contents"), discard: toBin) }
let ro = tmp.appendingPathComponent("ro"); try! fm.createDirectory(at: ro, withIntermediateDirectories: true); try! fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ro.path)
pfails(.notWritable, "read-only folder") { _ = try placeGame(g1, in: ro, discard: toBin) }; check(body(g1) == "other", "game kept after failures")
if let big = ProcessInfo.processInfo.environment["BIGVOL"], let small = ProcessInfo.processInfo.environment["SMALLVOL"] {
    let v = URL(fileURLWithPath: big), w = URL(fileURLWithPath: small); check(!sameVolume(g1, v), "another disk seen")
    pfails(.noSpace, "full disk refused") { _ = try placeGame(g1, in: w, discard: toBin) }; check(body(g1) == "other" && (try! fm.contentsOfDirectory(atPath: w.path)).filter { $0.hasSuffix(".partial") || $0.hasSuffix(".app") }.isEmpty, "nothing half-copied")
    let u = try! placeGame(g1, in: v, discard: toBin); check(body(u) == "other" && !fm.fileExists(atPath: g1.path), "copied to another disk, then removed here")
    _ = game("pl/G.app", "0100000000099000", "newer"); _ = try! placeGame(g1, in: v, discard: { try fm.removeItem(at: $0) }); check(body(u) == "newer", "replaced on another disk")
    check(!(try! fm.contentsOfDirectory(atPath: v.path)).contains { $0.hasSuffix(".partial") }, "no temporary copy left")
} else { check(false, "disk tests did not run") }
b = drive(#"echo '{"ev":"game","title_id":"0100000000010000","name":"N","out":"/x/N.app"}'"#); check(b.output?.path == "/x/N.app", "finished app known")

// tools carried in the app
func ifails(_ e: InstallError, _ what: String, _ f: () throws -> Void) { do { try f(); check(false, what) } catch { check(error as? InstallError == e, "\(what): \(error)") } }
let ir = tmp.appendingPathComponent("ir"); _ = mk("pk/tools/.dockside-pin", pinnedEngine + "\n"); _ = mk("pk/tools/engine/a", "1")
let pay = tmp.appendingPathComponent("p.tar.xz"); run("/usr/bin/tar", ["-cJf", pay.path, "-C", tmp.appendingPathComponent("pk").path, "tools"]); let ps = sha256(pay)!
ifails(.damaged, "wrong fingerprint refused") { try installTools(pay, sha: String(repeating: "0", count: 64), root: ir) }; ifails(.damaged, "no fingerprint refused") { try installTools(pay, sha: "", root: ir) }
check(!fm.fileExists(atPath: ir.path), "nothing written when refused"); ifails(.spaces, "space in path refused") { try installTools(pay, sha: ps, root: tmp.appendingPathComponent("a b")) }
try! installTools(pay, sha: ps, root: ir); try! installTools(pay, sha: ps, root: ir)
check(fm.fileExists(atPath: ir.path + "/tools/engine/a") && !fm.fileExists(atPath: ir.path + "/tools.partial"), "installed, and again safely")
let junk = mk("junk.tar.xz", "not an archive"); do { try installTools(junk, sha: sha256(junk)!, root: ir); check(false, "junk refused") } catch { check(true, "") }
check(fm.fileExists(atPath: ir.path + "/tools/engine/a"), "a failed install leaves the old tools")
check(!Paths.unpacked && Paths.python.path.contains("venv"), "separate setup used until unpacked"); _ = mk("tools/.dockside-pin", pinnedEngine); check(Paths.unpacked && Paths.python.path.hasSuffix("tools/bin/python3"), "unpacked tools used")
_ = mk("tools/.dockside-pin", "other"); check(!Paths.unpacked, "another version not used")

// quick conversion
check(buildArguments(n, keys: nil, quick: true).contains("--no-prebake") && !buildArguments(n, keys: nil).contains("--gpu"), "pipeline step skipped only when asked")
// moving originals to the Trash
var od = 0; let bin2 = tmp.appendingPathComponent("bin2"); try! fm.createDirectory(at: bin2, withIntermediateDirectories: true)
let toBin2: (URL) throws -> Void = { od += 1; try fm.moveItem(at: $0, to: bin2.appendingPathComponent("\(od)-" + $0.lastPathComponent)) }
func text(_ u: URL) -> String? { try? String(contentsOf: u, encoding: .utf8) }
func stage(_ name: String, _ f: [URL]) -> [URL] { f.map { let l = tmp.appendingPathComponent("st/" + name + "/" + $0.lastPathComponent); try! fm.createDirectory(at: l.deletingLastPathComponent(), withIntermediateDirectories: true); try! fm.linkItem(at: $0, to: l); return l } }
func src(_ u: URL) -> SourceFile { SourceFile(path: u.path, size: folderSize(u)) }
let o1 = mk("or/a.nsp", "game"), o2 = mk("or/b.nsp", "update"), bystander = mk("or/other.nsp", "mine"), okeys = mk("or/prod.keys", "secret"); let sl = stage("1", [o1, o2])
let fo = findOriginals(links: sl, sources: [src(o1), src(o2), src(bystander), src(okeys)])
check(Set(fo.files.map(\.lastPathComponent)) == ["a.nsp", "b.nsp"] && fo.links.count == 2 && fo.bytes == 10, "only the converted files found")
check(trashOriginals(fo, trash: toBin2).isEmpty && od == 2, "originals trashed"); check(!fm.fileExists(atPath: o1.path) && !fm.fileExists(atPath: sl[0].path), "links dropped, so space can be freed")
check(Set((try! fm.contentsOfDirectory(atPath: bin2.path)).compactMap { text(bin2.appendingPathComponent($0)) }) == ["game", "update"], "both recoverable from the Trash"); check(text(bystander) == "mine" && text(okeys) == "secret", "nothing else touched")
let o3 = mk("or/c.nsp", "old"); let s3 = stage("3", [o3]), m3 = src(o3); try! fm.removeItem(at: o3); _ = mk("or/c.nsp", "new"); let f3 = findOriginals(links: s3, sources: [m3])
check(f3.files.isEmpty && f3.links.count == 1, "a different file with the same name is not the original"); _ = trashOriginals(f3, trash: toBin2); check(text(o3) == "new" && od == 3, "it stays; the last copy goes to the Trash, not deleted")
let o4 = mk("or/d.nsp", "stuck"); let s4 = stage("4", [o4]); let bad = trashOriginals(findOriginals(links: s4, sources: [src(o4)]), trash: { _ in throw InputError.missing })
check(bad == [o4] && text(o4) == "stuck" && fm.fileExists(atPath: s4[0].path), "no Trash: file and link both stay")
let o5 = mk("or/e.nup", "nup"), big5 = src(o5); check(findOriginals(links: [], sources: [big5]).files == [o5], "nup found"); _ = mk("or/e.nup", "changed"); check(findOriginals(links: [], sources: [big5]).isEmpty, "changed nup left alone")
check(findOriginals(links: [], sources: [src(tmp.appendingPathComponent("or")), src(okeys)]).isEmpty, "never a folder, never keys")
if let big = ProcessInfo.processInfo.environment["BIGVOL"] {
    let far = URL(fileURLWithPath: big + "/far.nsp"); try! Data("far".utf8).write(to: far); let sy = tmp.appendingPathComponent("st/far.nsp"); try! fm.createSymbolicLink(at: sy, withDestinationURL: far)
    let f6 = findOriginals(links: [sy], sources: [src(far)]); check(f6.files == [far], "file on another disk found"); _ = trashOriginals(f6, trash: { try fm.moveItem(at: $0, to: URL(fileURLWithPath: big + "/trashed")) })
    check((try? fm.destinationOfSymbolicLink(atPath: sy.path)) == nil && text(URL(fileURLWithPath: big + "/trashed")) == "far", "its link dropped, file in that disk's Trash")
}

// the pipeline step's parts
let pw = tmp.appendingPathComponent("pw"); check(Pipeline.total(pw) == nil && Pipeline.done(pw, since: .distantPast) == 0, "no list yet")
_ = mk("pw/pso/mac-work/bases.mtl4-json", String(repeating: "{\"vertex_function\": 1}\n", count: 2500)); check(Pipeline.total(pw) == 3, "2,500 makes 3 parts")
_ = mk("pw/pso/mac-work/batches.g/00001/a.mtl4a"); _ = mk("pw/pso/mac-work/batches.g/c00009/a.mtl4a"); _ = mk("pw/pso/mac-work/batches.g/00002/bases.mtl4-json")
check(Pipeline.done(pw, since: Date().addingTimeInterval(-60)) == 1, "one part finished"); check(Pipeline.done(pw, since: Date().addingTimeInterval(60)) == 0, "an earlier conversion's parts don't count")

// library
func LG(_ n: String, _ id: String) -> Game { Game(url: URL(fileURLWithPath: "/x/\(n).app"), name: n, titleID: id) }
let lgs = [LG("Zelda 10", "0100000000000000"), LG("Zelda 9", "0100000000002000"), LG("Bananza", "0400000000004000"), LG("Ánimal", "0100000000006000")]
var ld = LibraryData(); let d0 = Date(timeIntervalSince1970: 1_700_000_000); ld.meet(lgs, now: d0); ld.meet(lgs, now: Date()); check(ld.entries.count == 4 && ld.entry("0100000000000000").added == d0, "games met once")
check(ld.show(lgs, in: .all).map(\.name) == ["Ánimal", "Bananza", "Zelda 9", "Zelda 10"], "natural name order"); check(ld.show(lgs, in: .console("switch2")).map(\.name) == ["Bananza"] && ld.show(lgs, in: .console("switch")).count == 3, "systems separated")
check(ld.show(lgs, in: .all, search: " zelda ").count == 2 && ld.show(lgs, in: .all, search: "nothing").isEmpty, "search")
ld.edit("0100000000002000") { $0.favorite = true }; check(ld.show(lgs, in: .favorites).map(\.name) == ["Zelda 9"], "favorites")
ld.played("0400000000004000", from: d0, to: d0.addingTimeInterval(3600)); ld.played("0100000000000000", from: d0, to: d0.addingTimeInterval(60)); check(ld.entry("0400000000004000").seconds == 3600 && ld.entry("0400000000004000").status == .playing && ld.entry("0100000000000000").status == .none, "play time and started")
check(ld.show(lgs, in: .all, by: .recent).first?.name == "Bananza" && ld.show(lgs, in: .all, by: .played).first?.name == "Bananza", "recent and most played"); ld.played("0400000000004000", from: d0, to: d0.addingTimeInterval(-50)); ld.played("0400000000004000", from: d0, to: d0.addingTimeInterval(1e9)); check(ld.entry("0400000000004000").seconds == 3600, "a clock that jumps adds nothing")
check(ld.addCollection("  Co-op ") == "Co-op" && ld.addCollection("co-OP") == "Co-op" && ld.addCollection("   ") == nil && ld.collections == ["Co-op"], "collections"); ld.edit("0100000000002000") { $0.collections = ["Co-op"] }; check(ld.show(lgs, in: .collection("Co-op")).count == 1, "in a collection")
ld.renameCollection("Co-op", "Party"); check(ld.show(lgs, in: .collection("Party")).count == 1 && ld.collections == ["Party"], "renamed"); _ = ld.addCollection("Solo"); ld.renameCollection("Solo", "party"); check(ld.collections == ["Party", "Solo"], "no two alike")
let lf = tmp.appendingPathComponent("lib/library.json"); ld.save(lf); check(LibraryData.load(lf) == ld, "saved and read back"); ld.removeCollection("Party"); check(ld.show(lgs, in: .collection("Party")).isEmpty && ld.entry("0100000000002000").favorite, "removing a collection keeps its games")
try! Data("{broken".utf8).write(to: lf); check(LibraryData.load(lf) == LibraryData() && (try! fm.contentsOfDirectory(atPath: lf.deletingLastPathComponent().path)).contains { $0.hasPrefix("library-damaged") }, "a damaged file is set aside, not lost"); check(LibraryData.load(tmp.appendingPathComponent("none.json")) == LibraryData(), "no file yet")
check(playTimeText(30) == "Not played yet" && playTimeText(600) == "10 min played" && playTimeText(5400) == "1.5 hours played" && lastPlayedText(nil) == "Never played" && lastPlayedText(Date()) == "Played today" && lastPlayedText(Date().addingTimeInterval(-86400)) == "Played yesterday", "wording")

// consoles
let types = consoles.flatMap(\.types); check(Set(types).count == types.count && Set(consoles.map(\.id)).count == consoles.count, "a file type means one console"); check(consoles.allSatisfy { $0.native || !$0.types.isEmpty || !$0.shared.isEmpty } && consoles.filter { !$0.native }.allSatisfy { !$0.folder.isEmpty }, "every console can be given games"); check(Set(types).isDisjoint(with: packageTypes) && !types.contains("nup"), "Switch files are never emulated")
let sf = mk("rom/Legend of Game, The - Part 2 (USA) (Rev 1) [!].sfc", "snesgame"), gb = mk("rom/Puzzle_Box (Japan).GB", "gb"), isoF = mk("rom/Disc (E).iso", "iso"), odd = mk("rom/readme.pdf"), cue = mk("rom/Race.cue", "c"), bn = mk("rom/Race.bin", "b")
check(consolesFor(sf).map(\.id) == ["snes"] && consolesFor(gb).map(\.id) == ["gb"] && consolesFor(odd).isEmpty, "console known from the file"); check(Set(consolesFor(isoF).map(\.id)) == ["gc", "wii", "ps2", "psp"], "shared type asks")
check(cleanName(sf) == "The Legend of Game - Part 2" && cleanName(gb) == "Puzzle Box" && cleanName(URL(fileURLWithPath: "/x/(USA).nes")) == "(USA)" && cleanName(URL(fileURLWithPath: "/x/A Game.gba")) == "A Game", "readable names: \(cleanName(sf))")
let zu = URL(fileURLWithPath: "/x/a.zip"); check(consolesFor(zu, inside: { _ in ["a.nes", "__MACOSX/b.sfc", "notes.txt"] }).map(\.id) == ["nes"] && consolesFor(zu, inside: { _ in ["a.nes", "b.sfc"] }).isEmpty && consolesFor(zu, inside: { _ in ["a.iso"] }).isEmpty && consolesFor(zu, inside: { _ in [] }).isEmpty, "zips"); check(consolesFor(mk("rom/bad.zip", "not a zip")).isEmpty, "a broken zip is nothing")
run("/usr/bin/zip", ["-qj", tmp.appendingPathComponent("rom/real.zip").path, sf.path]); check(consolesFor(tmp.appendingPathComponent("rom/real.zip")).map(\.id) == ["snes"], "a real zip")
check(Set(pickRoms([cue, bn, sf]).map(\.lastPathComponent)) == ["Race.cue", sf.lastPathComponent], "a disc's parts are one game"); let setm3u = mk("rom2/Set.m3u", "One.cue\nTwo.cue\n"); _ = mk("rom2/One.cue"); _ = mk("rom2/Two.cue"); _ = mk("rom2/One.bin"); check(pickRoms([tmp.appendingPathComponent("rom2")]).map(\.lastPathComponent) == ["Set.m3u"], "a set of discs is one game: \(setm3u.lastPathComponent)")
let id1 = romID(sf, "snes"); let moved = mk("rom3/renamed.sfc", "snesgame"), diff = mk("rom3/other.sfc", "snesgamf"); check(id1 == romID(moved, "snes") && id1 != romID(diff, "snes") && id1 != romID(sf, "gb") && id1 == id1.uppercased(), "the same game wherever it is"); check(consoleOf(id1) == "snes" && consoleOf("0100000000010000") == "switch" && consoleOf("0400486024DEC000") == "switch2", "console of a game")
var rl = LibraryData(); rl.addRom(Rom(id: id1, name: "G", console: "snes", path: sf.path)); rl.addRom(Rom(id: id1, name: "Other", console: "snes", path: moved.path)); check(rl.roms.count == 1 && rl.roms[0].path == moved.path && rl.roms[0].name == "G", "added again: moved, not doubled")
let rg = rl.roms.map { Game(url: URL(fileURLWithPath: $0.path), name: $0.name, titleID: $0.id, rom: $0) } + lgs; check(rl.show(rg, in: .console("snes")).count == 1 && rl.show(rg, in: .console("switch")).count == 3 && rl.show(rg, in: .all).count == 5, "consoles separated"); rl.played(id1, from: d0, to: d0.addingTimeInterval(700)); rl.removeRom(id1); check(rl.roms.isEmpty && rl.entry(id1).seconds == 700 && fm.fileExists(atPath: moved.path), "removing keeps the file and the play time")
let of = mk("lib2/library.json", #"{"collections":["Mine"],"entries":{"0100":{"added":"2026-11-24T09:00:00Z","collections":[],"favorite":true,"seconds":60,"status":"Playing"}}}"#); let ol = LibraryData.load(of); check(ol.collections == ["Mine"] && ol.entry("0100").favorite && ol.roms.isEmpty && fm.fileExists(atPath: of.path), "an earlier library opens"); rl.addRom(Rom(id: id1, name: "G", console: "snes", path: "/x")); rl.save(of); let back = LibraryData.load(of); check(back.roms == rl.roms && back.entry(id1).seconds == 700 && abs(back.entry(id1).added.timeIntervalSince(rl.entry(id1).added)) < 1, "and the new one")
if let mine = ProcessInfo.processInfo.environment["MYLIB"] { let c = mk("lib3/library.json", (try? String(contentsOfFile: mine, encoding: .utf8)) ?? ""); let l = LibraryData.load(c); check(l.entries.count >= 5 && fm.fileExists(atPath: c.path), "the player's own library opens") }
// RetroArch, kept inside Docked
RetroArch.home = tmp.appendingPathComponent("RA"); RetroArch.support = RetroArch.home; RetroArch.app = RetroArch.home.appendingPathComponent("RetroArch.app"); RetroArch.old = tmp.appendingPathComponent("OldRA")
let sn = console("snes")!; check(RetroArch.core(sn) == nil && !RetroArch.ready(sn) && RetroArch.problem(sn, rom: sf.path) == nil, "a missing core is Docked's to fetch, not the player's"); _ = mk("RA/cores/snes9x_libretro.dylib"); check(RetroArch.core(sn)?.lastPathComponent == "snes9x_libretro.dylib", "next best core"); _ = mk("RA/cores/bsnes_libretro.dylib"); check(RetroArch.core(sn)?.lastPathComponent == "bsnes_libretro.dylib", "the most accurate core first"); check(RetroArch.problem(sn, rom: "/gone.sfc")?.contains("found") == true, "missing file explained")
let raArgs = RetroArch.arguments(core: URL(fileURLWithPath: "/c a.dylib"), rom: "/x/-f --config $(rm) \"q\".sfc"); check(raArgs.suffix(3) == ["-L", "/c a.dylib", "/x/-f --config $(rm) \"q\".sfc"] && raArgs.prefix(4) == ["--config", RetroArch.settings.path, "--appendconfig", RetroArch.docked.path], "its own settings; odd file names stay one argument")
try! RetroArch.prepare(); let dcfg = try! String(contentsOf: RetroArch.docked, encoding: .utf8); check(dcfg.contains("system_directory = \"\(RetroArch.system.path)\"") && dcfg.contains("libretro_directory = \"\(RetroArch.cores.path)\"") && fm.fileExists(atPath: RetroArch.settings.path) && fm.fileExists(atPath: tmp.path + "/RA/saves"), "Docked's folders, written for RetroArch"); try! "video_fullscreen = \"false\"\n".write(to: RetroArch.settings, atomically: true, encoding: .utf8); try! RetroArch.prepare(); check((try! String(contentsOf: RetroArch.settings, encoding: .utf8)) == "video_fullscreen = \"false\"\n", "the player's own RetroArch settings stay")
check(dcfg.contains("video_fullscreen = \"false\""), "RetroArch games never take a Space of their own")
let fillA = RetroArch.filling(CGRect(x: 0, y: 80, width: 1512, height: 860)); check(fillA.contains("video_fullscreen = \"false\"") && fillA.contains("video_window_save_positions = \"true\"") && fillA.contains("video_windowed_position_y = \"80\"") && fillA.contains("video_windowed_position_width = \"1512\"") && fillA.contains("video_windowed_position_height = \"860\""), "a RetroArch window as big as the screen")
check(RetroArch.filling(CGRect(x: -1920, y: 0, width: 1920, height: 1050)) == "video_fullscreen = \"false\"\n" && RetroArch.filling(nil) == "video_fullscreen = \"false\"\n", "a screen RetroArch can't place a window on: a plain window")
check(RetroArch.coreURL("snes9x").absoluteString == "https://buildbot.libretro.com/nightly/apple/osx/\(RetroArch.arch)/latest/snes9x_libretro.dylib.zip" && ["arm64", "x86_64"].contains(RetroArch.arch) && RetroArch.appURL.absoluteString.hasPrefix("https://buildbot.libretro.com/stable/\(RetroArch.version)/apple/osx/universal/"), "from libretro's own buildbot")
check(consoles.filter { !$0.native }.allSatisfy { c in !c.cores.isEmpty } && console("ps1")!.cores[0].file == "mednafen_psx_hw" && console("gb")!.cores[0].file == "sameboy", "accurate cores first")
let ar = Rom(id: id1, name: "G", console: "snes", path: sf.path); check(RetroArch.art(ar) == nil, "no art"); _ = mk("OldRA/thumbnails/Nintendo - Super Nintendo Entertainment System/Named_Boxarts/\(sf.deletingPathExtension().lastPathComponent).png"); check(RetroArch.art(ar)?.path.contains("OldRA") == true, "art an earlier RetroArch downloaded"); _ = mk("RA/thumbnails/Nintendo - Super Nintendo Entertainment System/Named_Boxarts/\(sf.deletingPathExtension().lastPathComponent).png"); check(RetroArch.art(ar)?.path.contains("/RA/") == true, "RetroArch's art"); _ = mk("Artwork/" + id1.replacingOccurrences(of: ":", with: "-") + ".png"); check(RetroArch.art(ar)?.path.contains("Artwork") == true, "the player's own art first")
// BIOS: only from the player, checked before it's kept
let ps1 = console("ps1")!, sat = console("saturn")!, ps2c = console("ps2")!, pce = console("pce")!
check(RetroArch.missingBios(sat, rom: "/a.cue")?.required == true && RetroArch.missingBios(ps1, rom: "/a.cue")?.required == false && RetroArch.missingBios(sn, rom: sf.path) == nil, "who needs a BIOS"); check(RetroArch.missingBios(pce, rom: "/a.pce") == nil && RetroArch.missingBios(pce, rom: "/a.cue") != nil, "a System Card only for CD games")
fails2("not a BIOS refused") { try RetroArch.addBios(mk("bios/random.bin", "nope"), for: sat) }; check(!RetroArch.hasBios(sat) && ((try? fm.contentsOfDirectory(atPath: RetroArch.system.path)) ?? []).isEmpty, "nothing kept")
let fakeBios = Data("pretend saturn bios".utf8), fakeMD5 = Insecure.MD5.hash(data: fakeBios).map { String(format: "%02x", $0) }.joined(); RetroArch.bios["saturn"]!.files.append(Firmware(file: "mpr-test.bin", md5: fakeMD5, label: "Test")); let fbios = tmp.appendingPathComponent("bios/My Dump.BIN"); try! fakeBios.write(to: fbios)
check((try? RetroArch.addBios(fbios, for: sat))?.contains("Test") == true && fm.fileExists(atPath: RetroArch.system.path + "/mpr-test.bin") && RetroArch.hasBios(sat) && RetroArch.missingBios(sat, rom: "/a.cue") == nil && fm.fileExists(atPath: fbios.path), "a known BIOS kept under the name its core looks for, the player's file left as it is")
fails2("a PS2 BIOS has its size") { try RetroArch.addBios(mk("bios/small.bin", "x"), for: ps2c) }; let p2 = tmp.appendingPathComponent("bios/SCPH-70012.bin"); try! Data(count: 4 << 20).write(to: p2); check((try? RetroArch.addBios(p2, for: ps2c)) != nil && fm.fileExists(atPath: RetroArch.system.path + "/pcsx2/bios/SCPH-70012.bin") && RetroArch.hasBios(ps2c), "a PS2 BIOS in its folder")
// Telling discs apart by what is inside them
func disc(_ name: String, _ bytes: [UInt8]) -> URL { let u = tmp.appendingPathComponent("disc/" + name); try! fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try! Data(bytes).write(to: u); return u }
func put(_ b: inout [UInt8], _ at: Int, _ v: [UInt8]) { if b.count < at + v.count { b += [UInt8](repeating: 0, count: at + v.count - b.count) }; b.replaceSubrange(at..<at + v.count, with: v) }
func le(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24 & 255)] }
func iso9660(system: String, files: [(String, String)], raw: Bool = false) -> [UInt8] {
    var sectors = [[UInt8]](repeating: [UInt8](repeating: 0, count: 2048), count: 20 + files.count)
    var pvd = sectors[16]; put(&pvd, 0, [1] + Array("CD001".utf8)); put(&pvd, 8, Array(system.padding(toLength: 32, withPad: " ", startingAt: 0).utf8)); put(&pvd, 156 + 2, le(18)); put(&pvd, 156 + 10, le(2048)); sectors[16] = pvd
    var dir: [UInt8] = [], at = 0
    for (k, f) in files.enumerated() { let n = Array((f.0 + ";1").utf8); var r = [UInt8](repeating: 0, count: 33 + n.count + (n.count % 2 == 0 ? 1 : 0)); r[0] = UInt8(r.count); put(&r, 2, le(20 + k)); put(&r, 10, le(f.1.utf8.count)); r[32] = UInt8(n.count); put(&r, 33, n); dir += r; var c = sectors[20 + k]; put(&c, 0, Array(f.1.utf8)); sectors[20 + k] = c; at += 1 }
    var d = sectors[18]; put(&d, 0, dir); sectors[18] = d
    guard raw else { return sectors.flatMap { $0 } }
    return sectors.flatMap { s -> [UInt8] in [0] + [UInt8](repeating: 0xFF, count: 10) + [0, 0, 2, 0, 2] + [0, 0, 0, 0, 0, 0, 0, 0] + s + [UInt8](repeating: 0, count: 280) }
}
var gcb = [UInt8](repeating: 0, count: 64); put(&gcb, 0x1C, [0xC2, 0x33, 0x9F, 0x3D]); var wib = [UInt8](repeating: 0, count: 64); put(&wib, 0x18, [0x5D, 0x1C, 0x9E, 0xA3])
check(consolesFor(disc("Cube.iso", gcb)).map(\.id) == ["gc"] && consolesFor(disc("Remote.iso", wib)).map(\.id) == ["wii"], "GameCube and Wii discs")
var rvz = Array("RVZ".utf8) + [1]; put(&rvz, 0x48, [0, 0, 0, 2]); var ciso = Array("CISO".utf8); put(&ciso, 0x8000 + 0x1C, [0xC2, 0x33, 0x9F, 0x3D]); check(consolesFor(disc("w.rvz", rvz)).map(\.id) == ["wii"] && consolesFor(disc("g.ciso", ciso)).map(\.id) == ["gc"], "RVZ and CISO")
check(consolesFor(disc("Two.iso", iso9660(system: "PLAYSTATION", files: [("SYSTEM.CNF", "BOOT2 = cdrom0:\\SLUS_200.00;1\n")]))).map(\.id) == ["ps2"] && consolesFor(disc("Pocket.iso", iso9660(system: "PSP GAME", files: [("UMD_DATA.BIN", "x")]))).map(\.id) == ["psp"], "PS2 and PSP discs")
let ps1bin = disc("One.bin", iso9660(system: "PLAYSTATION", files: [("SYSTEM.CNF", "BOOT = cdrom:\\SLUS_000.01;1\n")], raw: true)); let ps1cue = disc("One.cue", Array("FILE \"One.bin\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n".utf8)); _ = ps1bin
check(consolesFor(ps1cue).map(\.id) == ["ps1"], "a PlayStation disc from its cue sheet: \(consolesFor(ps1cue).map(\.id))")
var satb = [0] + [UInt8](repeating: 0xFF, count: 10) + [0, 0, 2, 0, 1]; put(&satb, 16, Array("SEGA SEGASATURN ".utf8)); put(&satb, 2352 * 17, [0]); _ = disc("Sat.bin", satb); check(consolesFor(disc("Sat.cue", Array("FILE \"Sat.bin\" BINARY\n  TRACK 01 MODE1/2352\n    INDEX 01 00:00:00\n".utf8))).map(\.id) == ["saturn"], "a Saturn disc")
check(consolesFor(disc("Turbo.cue", Array("FILE \"T1.bin\" BINARY\n TRACK 01 AUDIO\n  INDEX 01 00:00:00\nFILE \"T2.bin\" BINARY\n TRACK 02 MODE1/2352\n  INDEX 01 00:00:00\n".utf8))).map(\.id) == ["pce"], "a disc that starts with music is a PC Engine CD")
var chdb = Array("MComprHD".utf8) + [0, 0, 0, 124, 0, 0, 0, 5]; put(&chdb, 48, [0, 0, 0, 0, 0, 0, 0, 124]); put(&chdb, 124, Array("CHGD".utf8) + [1, 0, 0, 8] + [UInt8](repeating: 0, count: 8) + Array("TRACK:1 ".utf8)); check(consolesFor(disc("Dc.chd", chdb)).map(\.id) == ["dreamcast"], "a Dreamcast CHD")
var chdc = chdb; put(&chdc, 124, Array("CHT2".utf8)); let t1 = Array("TRACK:1 TYPE:MODE2_RAW SUBTYPE:NONE FRAMES:1000".utf8); put(&chdc, 125 + 4, [0, 0, UInt8(t1.count)]); put(&chdc, 140, t1); check(Set(consolesFor(disc("Cd.chd", chdc)).map(\.id)) == ["ps1", "ps2"], "a CHD's first track")
check(Set(consolesFor(disc("Unknown.iso", [UInt8](repeating: 7, count: 40000))).map(\.id)) == ["gc", "wii", "ps2", "psp"], "nothing to go on: the player says")
_ = disc("Set.m3u", Array("Sat.cue\n".utf8)); check(consolesFor(tmp.appendingPathComponent("disc/Set.m3u")).map(\.id) == ["saturn"], "a set of discs, from its first")
// A disc's serial, which game lists key disc games by
check(Disc.serial(ps1cue) == "SLUS-00001" && Disc.serial(disc("Two2.iso", iso9660(system: "PLAYSTATION", files: [("SYSTEM.CNF", "BOOT2 = cdrom0:\\SLUS_200.00;1\n")]))) == "SLUS-20000", "PlayStation serials from SYSTEM.CNF")
var gcid = gcb; put(&gcid, 0, Array("GM8E01".utf8)); check(Disc.serial(disc("Prime.iso", gcid)) == "GM8E01" && Disc.serial(disc("Cube.iso", gcb)) == nil, "a GameCube disc's ID, and none where it is blank")
var rvzid = rvz; put(&rvzid, 0x58, Array("RYWP01".utf8)); check(Disc.serial(disc("w2.rvz", rvzid)) == "RYWP01", "an RVZ's ID")
check(Disc.serial(disc("Pocket2.iso", iso9660(system: "PSP GAME", files: [("UMD_DATA.BIN", "ULUS-10041|0001|G")]))) == "ULUS-10041" && Disc.serial(disc("Pocket3.iso", iso9660(system: "PSP GAME", files: [("UMD_DATA.BIN", "x")]))) == nil, "a PSP's serial")
var satid = satb; put(&satid, 16 + 0x20, Array("T-12705H  ".utf8)); _ = disc("Sat2.bin", satid); check(Disc.serial(disc("Sat2.cue", Array("FILE \"Sat2.bin\" BINARY\n  TRACK 01 MODE1/2352\n    INDEX 01 00:00:00\n".utf8))) == "T-12705H", "a Saturn disc's product number")
check(Disc.serial(disc("Dc2.chd", chdb)) == nil && Disc.serial(mk("rom/none.sfc", "x")) == nil, "nothing to read: no serial")
// Setting up from a local copy of the buildbot: RetroArch once, then the best core it has for this Mac
if fm.isExecutableFile(atPath: "/usr/bin/hdiutil") {
    let bb = tmp.appendingPathComponent("bb"), src = tmp.appendingPathComponent("rasrc"), fake = src.appendingPathComponent("RetroArch.app/Contents")
    try! fm.createDirectory(at: fake.appendingPathComponent("MacOS"), withIntermediateDirectories: true); try! fm.copyItem(atPath: "/usr/bin/true", toPath: fake.path + "/MacOS/RetroArch")
    try! PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "RetroArch", "CFBundleIdentifier": "com.libretro.dist.RetroArch", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": RetroArch.version], format: .xml, options: 0).write(to: fake.appendingPathComponent("Info.plist"))
    run("/usr/bin/codesign", ["--force", "--sign", "-", src.path + "/RetroArch.app"])
    let dmgDir = bb.appendingPathComponent("stable/\(RetroArch.version)/apple/osx/universal"); try! fm.createDirectory(at: dmgDir, withIntermediateDirectories: true); let dmg = dmgDir.appendingPathComponent("RetroArch_Metal.dmg")
    check(run("/usr/bin/hdiutil", ["create", "-quiet", "-srcfolder", src.path, "-format", "UDZO", "-volname", "RetroArch", dmg.path], timeout: 120).code == 0, "a stand-in RetroArch")
    let coreDir = bb.appendingPathComponent("nightly/apple/osx/\(RetroArch.arch)/latest"); try! fm.createDirectory(at: coreDir, withIntermediateDirectories: true); _ = mk("coresrc/gambatte_libretro.dylib", "core")
    run("/usr/bin/zip", ["-qj", coreDir.appendingPathComponent("gambatte_libretro.dylib.zip").path, tmp.path + "/coresrc/gambatte_libretro.dylib"])
    RetroArch.buildbot = bb.absoluteString.hasSuffix("/") ? String(bb.absoluteString.dropLast()) : bb.absoluteString
    _ = mk("OldRA/saves/Puzzle Box.srm", "my save"); _ = mk("RA/saves/Kept.srm", "newer"); _ = mk("OldRA/saves/Kept.srm", "older")
    RetroArch.dmgSHA = "0000"; do { try RetroArch.setUp(console("gb")!); check(false, "a different RetroArch refused") } catch { check(!RetroArch.installed && (error as? RetroError)?.text.contains("reviewed") == true, "a different RetroArch refused") }
    RetroArch.dmgSHA = RetroArch.sha256(dmg); var said: [String] = []
    do { try RetroArch.setUp(console("gb")!) { w, _ in said.append(w) } } catch { check(false, "set up: \(error)") }
    check(RetroArch.installed && RetroArch.installedVersion == RetroArch.version && !RetroArch.app.path.hasPrefix("/Applications"), "RetroArch inside Docked")
    check(RetroArch.core(console("gb")!)?.lastPathComponent == "gambatte_libretro.dylib" && RetroArch.ready(console("gb")!), "the next core when the best isn't built: \(said)")
    check((try? String(contentsOfFile: tmp.path + "/RA/saves/Puzzle Box.srm", encoding: .utf8)) == "my save" && (try? String(contentsOfFile: tmp.path + "/RA/saves/Kept.srm", encoding: .utf8)) == "newer" && fm.fileExists(atPath: tmp.path + "/OldRA/saves/Puzzle Box.srm"), "saves from an earlier RetroArch copied, never over newer ones")
    do { try RetroArch.setUp(console("n64")!); check(false, "no core for this Mac") } catch { check((error as? RetroError)?.text.contains("doesn't have") == true, "no core for this Mac explained") }
    check(((try? fm.contentsOfDirectory(atPath: RetroArch.home.path)) ?? []).allSatisfy { !$0.hasPrefix(".setup-") } && ((try? fm.contentsOfDirectory(atPath: RetroArch.cores.path)) ?? []).allSatisfy { !$0.hasPrefix(".get-") }, "nothing left half-done")
}
// ---- what each Mac can do ----
let m = { (v: String, chip: Bool) in MacKind(version: v.split(separator: ".").map { Int($0)! }, appleChip: chip) }
for (v, n, want) in [("26.6", "26.6", true), ("26.6.1", "26.6", true), ("26.5.9", "26.6", false), ("27", "26.6", true), ("26.10", "26.6", true), ("13.0", "26.6", false), ("26.6", "26.6.0", true), ("26.6", "26.6.1", false), ("27.0", "27", true)] { check(m(v, true).atLeast(n) == want, "macOS \(v) against \(n)") }
check(cannotConvert(m("27.2", true), tools: "27.0") == nil, "this kind of Mac converts"); check(cannotConvert(m("26.6", true), tools: "26.0") == nil, "26.6 converts with tools made for it"); check(cannotConvert(m("26.6", true), tools: "27.0")?.contains("27.0") == true, "26.6 with tools made for 27: says 27"); check(cannotConvert(m("26.5", true), tools: "11.0")?.contains("26.6") == true, "26.5: says 26.6"); check(cannotConvert(m("15.6", true), tools: "26.0") != nil && cannotConvert(m("26.6", false), tools: "26.0")?.contains("Apple chip") == true, "old macOS, Intel: no converting")
check(cannotPlay(needs: "26.6", m("26.6", true)) == nil && cannotPlay(needs: "26.6", m("15.0", true)) == "Needs macOS 26.6 or later" && cannotPlay(needs: "26.6", m("26.6", false))?.contains("Apple chip") == true, "playing"); check(MacKind.this.appleChip && cannotConvert(tools: "26.0") == nil, "this Mac, read from the system")
do { var g = Game(url: URL(fileURLWithPath: "/x.app"), name: "x", titleID: "0", needs: "99.0"); check(g.cannot == "Needs macOS 99.0 or later", "a game too new for this Mac says so"); g.needs = "13.0"; check(g.cannot == nil, "one that is not, does not") }

// ---- the queue ----
func job(_ t: String, _ f: String? = nil, _ p: [String]? = nil) -> Job { Job(title: t, family: f, parts: p ?? ["/\(t).nsp"], place: "/g", quick: false, after: .ask, bytes: 1, needsKeys: true, sources: []) }
var q = Queue(); check(q.isEmpty && q.next { _ in .go } == nil, "empty"); check(q.add(job("A", "0100000000000001")) && q.add(job("B", "0100000000000002")) && q.add(job("C")), "added"); check(!q.add(job("A again", "0100000000000001", ["/x.nsp"])) && !q.add(job("C")), "the same game is not added twice")
check(q.next { _ in .go }?.title == "A" && q.current?.title == "A" && q.waiting.map(\.title) == ["B", "C"], "first in, first out"); check(q.next { _ in .go } == nil, "one at a time"); check(!q.add(job("A", "0100000000000001")), "nor while it converts")
q.up(q.waiting[1].id); check(q.waiting.map(\.title) == ["C", "B"], "moved up"); q.up(q.waiting[0].id); check(q.waiting.map(\.title) == ["C", "B"], "first stays first"); q.failed("broke"); check(q.problems.map(\.title) == ["A"] && q.current == nil, "a failure is kept")
check(q.next { $0.title == "C" ? .wait : .go }?.title == "B" && q.waiting.map(\.title) == ["C"], "one that must wait lets others go"); q.done(); check(q.next { _ in .no("gone") } == nil && q.waiting.isEmpty && q.problems.last == Problem(id: q.problems.last!.id, title: "C", reason: "gone"), "one that cannot start is set aside")
_ = q.add(job("D")); _ = q.add(job("E")); _ = q.next { _ in .go }; q.stopped(); check(q.paused && q.next { _ in .go } == nil && q.waiting.map(\.title) == ["E"], "stopping pauses the rest"); q.paused = false; check(q.next { _ in .go }?.title == "E", "continues"); q.stopped(); check(!q.paused, "nothing left, nothing paused"); var lone = Queue(); _ = lone.add(job("L")); _ = lone.next { _ in .go }; lone.failed("x"); check(lone.problems.isEmpty, "a lone failure is shown by the conversion itself")
let qf = tmp.appendingPathComponent("queue/queue.json"); var qs = Queue(); _ = qs.add(job("F")); _ = qs.add(job("G")); _ = qs.next { _ in .go }; qs.save(qf); let ql = Queue.load(qf); check(ql.current == nil && ql.waiting.map(\.title) == ["F", "G"] && ql.paused, "after a crash: back in the queue, paused"); Queue().save(qf); check(!fm.fileExists(atPath: qf.path) && Queue.load(qf) == Queue(), "an empty queue leaves no file"); try! "broken".write(to: qf, atomically: true, encoding: .utf8); check(Queue.load(qf) == Queue(), "a damaged file is not a crash")

// ---- cleaning up ----
let cg = tmp.appendingPathComponent("cg"), ci = tmp.appendingPathComponent("ci")
func app(_ n: String, _ id: String) -> Game { let a = cg.appendingPathComponent(n + ".app"); _ = mk("cg/\(n).app/Contents/MacOS/dmhost", "x"); try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: a.path + "/Contents/MacOS/dmhost"); _ = mk("cg/\(n).app/Contents/PlugIns/d/romfs.img", "data"); try? fm.createSymbolicLink(atPath: a.path + "/Contents/romfs.img", withDestinationPath: "PlugIns/d/romfs.img"); NSDictionary(dictionary: ["DMTitleID": id]).write(to: a.appendingPathComponent("Contents/Info.plist"), atomically: true); return Game(url: a, name: n, titleID: id) }
let ga = app("Alpha", "0100AAAAAAAAA000"), gb2 = app("Beta", "0100BBBBBBBBB000"); check(selfContained(ga.url, titleID: "0100aaaaaaaaa000"), "a finished game stands on its own"); check(!selfContained(ga.url, titleID: "0100BBBBBBBBB000"), "not under another title")
try! fm.createSymbolicLink(atPath: gb2.url.path + "/Contents/msl", withDestinationPath: cg.path + "/0100BBBBBBBBB000_build/msl"); _ = mk("cg/0100BBBBBBBBB000_build/msl/a"); check(!selfContained(gb2.url, titleID: gb2.titleID), "one that links to its leftovers does not"); try! fm.removeItem(atPath: gb2.url.path + "/Contents/msl"); try! fm.createSymbolicLink(atPath: gb2.url.path + "/Contents/msl", withDestinationPath: "/nowhere"); check(!selfContained(gb2.url, titleID: gb2.titleID), "nor one with a broken link"); try! fm.removeItem(atPath: gb2.url.path + "/Contents/msl")
try! fm.createSymbolicLink(at: cg.appendingPathComponent("L.app"), withDestinationURL: ga.url); check(!selfContained(cg.appendingPathComponent("L.app"), titleID: ga.titleID), "nor a shortcut to one")
_ = mk("cg/0100AAAAAAAAA000_build/extract/x", "12345"); _ = mk("cg/AlphaOld-12ab_build/profile/0100AAAAAAAAA000/p"); _ = mk("cg/Gone-99_build/y"); _ = mk("cg/notes.txt"); _ = mk("cg/My Photos_builds/z"); let target = tmp.appendingPathComponent("precious"); _ = mk("precious/file"); try! fm.createSymbolicLink(at: cg.appendingPathComponent("Evil_build"), withDestinationURL: target)
var lo = findLeftovers(games: cg, library: [ga, gb2]); check(lo.map(\.name) == ["A game no longer in Docked", "Alpha", "Beta"] && lo[1].folders.count == 2, "found, by game, old folders too"); check(!lo.flatMap(\.folders).contains { $0.lastPathComponent == "Evil_build" || $0.lastPathComponent == "My Photos_builds" }, "nothing that only looks like one"); check(!findLeftovers(games: cg, library: [ga], busy: ["0100AAAAAAAAA000_build"]).flatMap(\.folders).contains { $0.lastPathComponent == "0100AAAAAAAAA000_build" }, "not one in use")
let refused = [cg.appendingPathComponent("Evil_build"), target, cg.appendingPathComponent("notes.txt"), ga.url, cg, cg.appendingPathComponent("0100AAAAAAAAA000_build/extract"), cg.appendingPathComponent("_build"), tmp.appendingPathComponent("cg/../precious"), URL(fileURLWithPath: "/")]; check(removeLeftovers(refused, games: cg).count == refused.count && fm.fileExists(atPath: target.path + "/file") && fm.fileExists(atPath: ga.url.path), "refuses everything else"); check(removeLeftovers([cg.appendingPathComponent("0100AAAAAAAAA000_build")], games: cg, busy: ["0100AAAAAAAAA000_build"]).count == 1 && fm.fileExists(atPath: cg.path + "/0100AAAAAAAAA000_build/extract/x"), "refuses one in use")
_ = mk("cg/Alpha.app.key", "k"); check(removeLeftovers(lo[1].folders, games: cg).isEmpty && !fm.fileExists(atPath: cg.path + "/0100AAAAAAAAA000_build") && !fm.fileExists(atPath: cg.path + "/AlphaOld-12ab_build"), "removed"); check(selfContained(ga.url, titleID: ga.titleID) && fm.fileExists(atPath: cg.path + "/0100BBBBBBBBB000_build"), "the game and the others stay")
_ = mk("ci/0100AAAAAAAAA000/.DS_Store"); _ = mk("ci/0100BBBBBBBBB000/b.nsp"); removeNotes(for: ga.url, title: ga.titleID, games: cg, inputs: ci); removeNotes(for: gb2.url, title: gb2.titleID, games: cg, inputs: ci); check(!fm.fileExists(atPath: cg.path + "/Alpha.app.key") && !fm.fileExists(atPath: ci.path + "/0100AAAAAAAAA000") && fm.fileExists(atPath: ci.path + "/0100BBBBBBBBB000/b.nsp"), "notes go, kept originals stay")
_ = mk("cg/.removing-\(UUID().uuidString)/half"); _ = mk("cg/.removing-mine/keep"); finishRemovals(games: cg); let left = try! fm.contentsOfDirectory(atPath: cg.path).filter { $0.hasPrefix(".removing") }; check(left == [".removing-mine"], "a removal cut short is finished, and only that")
var gone: [URL] = []; let kf = mk("my/prod.keys", "k = 1"); check(trashKeys(kf.path) { gone.append($0) } && gone == [kf], "keys to the Trash"); let nk = mk("my/notes.doc"); check(!trashKeys(nk.path) { gone.append($0) } && !trashKeys(tmp.appendingPathComponent("my").path) { gone.append($0) } && !trashKeys("/gone/prod.keys") { gone.append($0) } && gone.count == 1, "and only a keys file")

// ---- space, reports, updates, notices ----
func sj(_ gb: Int64, _ a: After) -> Job { var j = job("s\(gb)\(a)"); j.bytes = gb * 1_000_000_000; j.after = a; return j }
check(spaceForQueue([]) == 0 && spaceForQueue([sj(10, .ask)]) == 30_000_000_000, "one game"); check(spaceForQueue([sj(10, .ask), sj(5, .ask)]) == 40_000_000_000 && spaceForQueue([sj(10, .leftovers), sj(5, .ask)]) == 30_000_000_000, "what earlier ones leave counts"); check(spaceText(need: 10_000_000_000, free: 50_000_000_000).short == false && spaceText(need: 50_000_000_000, free: 10_000_000_000).text.contains("Free up about 40 GB"), "said plainly")
let rd = redact("at /Users/jo/Games/x.nsp and /Users/other/y on /Volumes/My Disk/z by Jo Smith (jo) jo@mail.example.com 192.168.1.20 key 0123456789abcdef0123456789abcdef ghp_abcdefghijkl1234 title 0100AAAAAAAAA000 joke", home: "/Users/jo", user: "jo", full: "Jo Smith"); check(!rd.contains("/Users") && !rd.contains("My Disk") && !rd.contains("mail.example") && !rd.contains("192.168") && !rd.contains("0123456789abcdef0") && !rd.contains("ghp_") && !rd.contains("Smith"), "who and where are taken out: " + rd); check(rd.contains("0100AAAAAAAAA000") && rd.contains("joke") && rd.contains("x.nsp"), "what helps stays")
check(redact("user sam ran", home: "/Users/sam", user: "sam", full: "Sam Lee") == "user (name) ran" && redact("sample", home: "/Users/sam", user: "sam", full: "Sam Lee") == "sample", "names, not parts of words")
let rp = makeReport(title: "G [0100]", step: "step 3", error: "broke in \(NSHomeDirectory())/x", log: (0..<200).map { "line \($0)" }, version: "1.1", os: "27.2", chip: "Apple M9", space: 5_000_000_000); check(rp.contains("Docked 1.1") && rp.contains("line 199") && !rp.contains("line 100\n") && rp.contains("broke in ~/x"), "report")
for (x, y, w) in [("v1.1", "1.0", true), ("1.0", "1.0", false), ("1.0.1", "1.0", true), ("1.10", "1.9", true), ("1.0", "1.0.0", false), ("0.9", "1.0", false), ("junk", "1.0", false), ("1.", "1.0", false), ("2", "1.9.9", true)] { check(newer(x, than: y) == w, "\(x) against \(y)") }
func rel(_ s: String) -> Data { Data(s.utf8) }
check(readRelease(rel(#"{"tag_name":"v1.2"}"#), 200, current: "1.1") == .available("1.2") && readRelease(rel(#"{"tag_name":"v1.1"}"#), 200, current: "1.1") == .newest, "an answer"); check(readRelease(rel(#"{"tag_name":"v9<script>"}"#), 200, current: "1.1") == .unknown && readRelease(rel(#"{"tag_name":"v2"}"#), 404, current: "1.1") == .unknown && readRelease(nil, 0) == .unknown && readRelease(rel("no"), 200) == .unknown, "no answer, or a strange one")

// ---- notes ----
let nmd = "# G\n\n## Open\n\n- The sound has not been listened to on later levels.\n- `game.tsv` says one thing and `x` another.\n- **Two shaders** do not translate.\n- Text\n  carried on to the next line of the file, with [a link](../x.md).\n- Short.\n\n## What it needs\n- Not this one at all, please.\n"
check(GameNotes.read(nmd) == ["The sound has not been listened to on later levels.", "Text carried on to the next line of the file, with a link."], "only what a player can use"); check(GameNotes.read("") == [] && GameNotes.of("../../etc/passwd") == [] && GameNotes.of("0100") == [], "nothing, or not a title"); check(GameNotes.plain(String(repeating: "word ", count: 90))!.count <= 202, "cut short")
// ---- smart collections ----
let now0 = Date(timeIntervalSince1970: 1_800_000_000); func ent(_ f: (inout Entry) -> Void) -> Entry { var e = Entry(added: now0.addingTimeInterval(-10 * 86400)); f(&e); return e }; let sg = Game(url: URL(fileURLWithPath: "/x"), name: "G", titleID: "0100000000006000")
func sm(_ f: (inout SmartCollection) -> Void) -> SmartCollection { var s = SmartCollection(name: "S"); f(&s); return s }
for (s, e, w, n) in [(sm { $0.status = .playing }, ent { $0.status = .playing }, true, "progress"), (sm { $0.status = .playing }, ent { _ in }, false, "other progress"), (sm { $0.favorite = true }, ent { _ in }, false, "not a favorite"), (sm { $0.neverPlayed = true }, ent { _ in }, true, "never played"), (sm { $0.neverPlayed = true }, ent { $0.lastPlayed = now0 }, false, "played"), (sm { $0.playedWithin = 30 }, ent { $0.lastPlayed = now0.addingTimeInterval(-29 * 86400) }, true, "lately"), (sm { $0.playedWithin = 30 }, ent { $0.lastPlayed = now0.addingTimeInterval(-31 * 86400) }, false, "long ago"), (sm { $0.playedWithin = 30 }, ent { _ in }, false, "never, so not lately"), (sm { $0.notPlayedFor = 30 }, ent { $0.lastPlayed = now0.addingTimeInterval(-31 * 86400) }, true, "left alone"), (sm { $0.notPlayedFor = 30 }, ent { _ in }, false, "never, so not left alone"), (sm { $0.moreThanHours = 5 }, ent { $0.seconds = 5 * 3600 }, true, "hours"), (sm { $0.moreThanHours = 5 }, ent { $0.seconds = 5 * 3600 - 1 }, false, "a second short"), (sm { $0.addedWithin = 7 }, ent { _ in }, false, "added before"), (sm { $0.console = "switch" }, ent { _ in }, true, "console"), (sm { $0.console = "nes" }, ent { _ in }, false, "other console"), (sm { $0.status = .playing; $0.favorite = true }, ent { $0.status = .playing }, false, "all rules must hold")] { check(s.holds(sg, e, now: now0) == w, "smart: " + n) }
var smartLib = LibraryData(); check(!smartLib.keepSmart(SmartCollection(name: "Empty")) && !smartLib.keepSmart(sm { $0.name = "  "; $0.favorite = true }), "no rules, or no name"); let k1 = sm { $0.name = "Best"; $0.favorite = true }; check(smartLib.keepSmart(k1) && !smartLib.keepSmart(sm { $0.name = "best"; $0.favorite = true }), "a name once"); var k2 = k1; k2.name = "Best of all"; check(smartLib.keepSmart(k2) && smartLib.smart.count == 1 && smartLib.smart[0].name == "Best of all", "edited in place")
let slf = tmp.appendingPathComponent("sl/library.json"); smartLib.save(slf); check(LibraryData.load(slf).smart == smartLib.smart, "kept"); try! #"{"entries":{},"collections":["A"]}"#.write(to: slf, atomically: true, encoding: .utf8); check(LibraryData.load(slf).smart.isEmpty && LibraryData.load(slf).collections == ["A"], "an older library still opens"); try! #"{"entries":{},"collections":["A"],"smart":[{"name":5}]}"#.write(to: slf, atomically: true, encoding: .utf8); check(LibraryData.load(slf).collections == ["A"], "odd rules do not cost the library"); check(SmartCollection.ready.allSatisfy { !$0.empty }, "the ready ones have rules")
// ---- moving around ----
let gr: [(id: String, games: [String])] = [("grid", (0..<11).map(String.init))]; func c(_ i: Int) -> Cursor { Cursor(row: "grid", game: "\(i)") }
for (from, mv, to) in [(0, Move.right, 1), (0, .left, 0), (10, .right, 10), (1, .down, 5), (5, .up, 1), (2, .up, 2), (7, .down, 10), (9, .down, 9), (4, .left, 3)] { check(step(c(from), mv, rows: gr, columns: 4) == c(to), "grid \(from) \(mv)") }
let hr: [(id: String, games: [String])] = [("recent", ["a", "b", "c"]), ("Favorites", []), ("Switch", ["a", "b"])]; check(step(nil, .down, rows: hr, columns: nil) == Cursor(row: "recent", game: "a") && step(Cursor(row: "recent", game: "c"), .down, rows: hr, columns: nil) == Cursor(row: "Switch", game: "b") && step(Cursor(row: "Switch", game: "a"), .up, rows: hr, columns: nil) == Cursor(row: "recent", game: "a"), "rows, past an empty one"); check(step(Cursor(row: "gone", game: "z"), .left, rows: hr, columns: nil) == Cursor(row: "recent", game: "a") && step(nil, .left, rows: [], columns: 4) == nil, "lost, or nothing there")
// ---- updates ----
let uk = Curve25519.Signing.PrivateKey(), upub = uk.publicKey.rawRepresentation.base64EncodedString(), ud = tmp.appendingPathComponent("upd"), ub = ud.appendingPathComponent("Backups")
func sh(_ a: [String]) { let p = Process(); p.executableURL = URL(fileURLWithPath: a[0]); p.arguments = Array(a.dropFirst()); p.standardError = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; try! p.run(); p.waitUntilExit() }
func fake(_ at: URL, _ v: String, id: String = "local.dockside", tools: String? = nil, sign: Bool = true, extra: (URL) -> Void = { _ in }) { try? fm.removeItem(at: at); let c = at.appendingPathComponent("Contents"); try! fm.createDirectory(at: c.appendingPathComponent("MacOS"), withIntermediateDirectories: true); try! fm.createDirectory(at: c.appendingPathComponent("Resources"), withIntermediateDirectories: true); try! fm.copyItem(atPath: "/usr/bin/true", toPath: c.path + "/MacOS/Docked"); var i: [String: Any] = ["CFBundleExecutable": "Docked", "CFBundleIdentifier": id, "CFBundlePackageType": "APPL", "CFBundleShortVersionString": v]; if let t = tools { try! t.write(to: c.appendingPathComponent("Resources/tools.tar.xz"), atomically: true, encoding: .utf8); i["DSPayloadSHA256"] = SHA256.hash(data: Data(t.utf8)).map { String(format: "%02x", $0) }.joined(); i["DSToolsMinimum"] = "26.0" }; try! PropertyListSerialization.data(fromPropertyList: i, format: .xml, options: 0).write(to: c.appendingPathComponent("Info.plist")); extra(at); if sign { sh(["/usr/bin/codesign", "--force", "--sign", "-", at.path]) } }
func zipped(_ v: String, named: String = "Docked.app", id: String = "local.dockside", inside: String? = nil, sign: Bool = true, extra: @escaping (URL) -> Void = { _ in }) -> Data { let d = ud.appendingPathComponent("z\(UUID().uuidString)"); try! fm.createDirectory(at: d, withIntermediateDirectories: true); fake(d.appendingPathComponent(named), inside ?? v, id: id, sign: sign, extra: extra); let z = d.appendingPathExtension("zip"); sh(["/usr/bin/ditto", "-c", "-k", "--norsrc", "--keepParent", d.appendingPathComponent(named).path, z.path]); return try! Data(contentsOf: z) }
func sig(_ z: Data, _ v: String, _ k: Curve25519.Signing.PrivateKey = uk) -> Data { try! k.signature(for: Update.said(v, z)) }
let mine = ud.appendingPathComponent("Apps/Docked.app"); try! fm.createDirectory(at: mine.deletingLastPathComponent(), withIntermediateDirectories: true); fake(mine, "1.0", tools: "the tools"); func ver() -> String? { (NSDictionary(contentsOf: mine.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"]) as? String }
func refuse(_ n: String, _ z: Data, _ s: Data, _ v: String = "2.0", current: String = "1.0") { do { try Update.install(z, s, version: v, over: mine, backups: ub, current: current, key: upub); check(false, "went through: " + n) } catch { check(ver() == "1.0" && (try? fm.contentsOfDirectory(atPath: mine.deletingLastPathComponent().path)) == ["Docked.app"], "refused, nothing changed: " + n) } }
let good = zipped("2.0"); refuse("another key", good, sig(good, "2.0", Curve25519.Signing.PrivateKey())); refuse("no signature", good, Data()); refuse("a zero signature", good, Data(count: 64)); var bent = good; bent[bent.count / 2] ^= 1; refuse("one bit changed", bent, sig(good, "2.0")); refuse("signed for another version", good, sig(good, "1.5")); refuse("an old one offered as new", zipped("0.9"), sig(zipped("0.9"), "0.9"), "0.9"); refuse("the same version", good, sig(good, "2.0"), "2.0", current: "2.0"); refuse("an odd version", good, sig(good, "2.0;rm"), "2.0;rm"); refuse("random bytes", Data((0..<5000).map { _ in UInt8.random(in: 0...255) }), Data((0..<64).map { _ in UInt8.random(in: 0...255) }))
func signed(_ n: String, _ z: Data) { refuse(n + ", though signed", z, sig(z, "2.0")) }
signed("another app", zipped("2.0", id: "com.example.other")); signed("another name", zipped("2.0", named: "Other.app")); signed("another version inside", zipped("2.0", inside: "3.0")); signed("a link inside", zipped("2.0") { try! fm.createSymbolicLink(atPath: $0.path + "/Contents/Resources/l", withDestinationPath: "/etc") }); signed("a broken seal", zipped("2.0", sign: true, extra: { _ in }).isEmpty ? good : { let z = ud.appendingPathComponent("brk"); try! fm.createDirectory(at: z, withIntermediateDirectories: true); fake(z.appendingPathComponent("Docked.app"), "2.0"); try! "more".write(toFile: z.path + "/Docked.app/Contents/Resources/late", atomically: true, encoding: .utf8); sh(["/usr/bin/ditto", "-c", "-k", "--norsrc", "--keepParent", z.path + "/Docked.app", z.path + ".zip"]); return try! Data(contentsOf: URL(fileURLWithPath: z.path + ".zip")) }()); signed("not a zip", Data("hello".utf8))
try! "changed".write(to: mine.appendingPathComponent("Contents/Resources/tools.tar.xz"), atomically: true, encoding: .utf8); signed("damaged tools of its own", good); fake(mine, "1.0", tools: "the tools")
try! fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: mine.deletingLastPathComponent().path); signed("a locked folder", good); try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mine.deletingLastPathComponent().path)
let keptAt = try? Update.install(good, sig(good, "2.0"), version: "2.0", over: mine, backups: ub, current: "1.0", key: upub); check(ver() == "2.0" && keptAt != nil, "a genuine one goes in"); check((try? String(contentsOf: mine.appendingPathComponent("Contents/Resources/tools.tar.xz"), encoding: .utf8)) == "the tools", "the tools are carried over"); let mi = NSDictionary(contentsOf: mine.appendingPathComponent("Contents/Info.plist"))!; check(mi["DSToolsMinimum"] as? String == "26.0" && (mi["DSPayloadSHA256"] as? String)?.count == 64, "with what is known about them"); let cv0 = Process(); cv0.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); cv0.arguments = ["--verify", "--strict", mine.path]; try! cv0.run(); cv0.waitUntilExit(); check(cv0.terminationStatus == 0, "sealed again"); check((NSDictionary(contentsOf: keptAt!.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"]) as? String == "1.0", "the old one is kept"); check((try! fm.contentsOfDirectory(atPath: mine.deletingLastPathComponent().path)) == ["Docked.app"], "nothing left beside it")
check(Data(base64Encoded: Update.publicKey)?.count == 32 && !Update.genuine(good, sig(good, "2.0"), version: "2.0"), "the real key is set, and the test's is not it")

// ---- installing with Xcode ----
do {
    check(es.whole(quick: false, phone: true, xcode: true) == 653 && es.remaining(step: "prepare Xcode", elapsed: 5, engineETA: nil, phone: true, xcode: true) == 10 && es.remaining(step: "iOS shaders", elapsed: 70, engineETA: nil, phone: true, xcode: true) == 545, "Xcode: the project, no app or package")
    let w = URL(fileURLWithPath: "/w/Docked.xcworkspace"), xa = buildArguments(n, keys: "/k", xcode: XcodeBuild(workspace: w, bundle: "a.b")), xb = buildArguments(n, keys: "/k", quick: true, xcode: XcodeBuild(workspace: w, bundle: nil))
    check(xa[xa.firstIndex(of: "--platform")! + 1] == "ios" && xa.contains("--prepare-xcode") && xa[xa.firstIndex(of: "--xcode-workspace")! + 1] == w.path && xa[xa.firstIndex(of: "--bundle-id")! + 1] == "a.b" && !xa.contains("-o") && !xa.contains("--no-prebake"), "Xcode project"); check(!xb.contains("--bundle-id") && xb.contains("none") && !xb.contains("--no-prebake"), "an ID that is there already is kept")
    check(bundleID("0100152000022000", mark: "ab12cd34") == "local.docked.mab12cd34.g0100152000022000" && bundleID("A-b_é.1", mark: "x") == "local.docked.mx.gab1", "app IDs"); let ud = UserDefaults(suiteName: "docked-mark-\(UUID())")!; let mk1 = macMark(ud); check(mk1.count == 8 && macMark(ud) == mk1, "the same each time"); ud.set("../../x", forKey: "macMark"); check(macMark(ud) != "../../x" && macMark(ud).count == 8, "nothing odd")
    let g = tmp.appendingPathComponent("xg"), ws = tmp.appendingPathComponent("xg/Docked & Co.xcworkspace"); check(xcodeGames(ws).isEmpty && xcodeBuild(for: "K", games: g, workspace: ws, mark: "m").bundle == "local.docked.mm.gk", "none yet")
    _ = mk("xg/A_build/xcode/DmIOS.xcodeproj/project.pbxproj"); check(hasXcodeProject(g.appendingPathComponent("A_build")) && !hasXcodeProject(g.appendingPathComponent("B_build")) && xcodeBuild(for: "A", games: g, workspace: ws).bundle == nil, "a project is there")
    func data(_ l: [String]) -> String { "<?xml version='1.0' encoding='utf-8'?>\n<Workspace version=\"1.0\">" + l.map { "<Group location=\"container:\" name=\"\($0) &amp; more\"><FileRef location=\"absolute:\(xcodeProject(in: g.appendingPathComponent($0 + "_build")).path)\" /></Group>" }.joined() + "</Workspace>" }
    _ = mk("xg/Docked & Co.xcworkspace/contents.xcworkspacedata", data(["A", "B"])); check(xcodeGames(ws).map(\.name) == ["A & more"], "only what is still there"); tidyWorkspace(ws); let after = try! String(contentsOf: ws.appendingPathComponent("contents.xcworkspacedata"), encoding: .utf8); check(after.contains("A_build") && !after.contains("B_build") && xcodeGames(ws).count == 1, "the rest is taken out")
    _ = mk("xg/Docked & Co.xcworkspace/contents.xcworkspacedata", "<broken"); tidyWorkspace(ws); check(xcodeGames(ws).isEmpty && (try! String(contentsOf: ws.appendingPathComponent("contents.xcworkspacedata"), encoding: .utf8)) == "<broken", "a damaged one is left alone")
    var xq = Queue(); var xj = job("P", "0100000000000009"); xj.target = .phone; var xk = xj; xk.viaXcode = true; check(xq.add(xj) && xq.add(xk) && !xq.add(xk) && !xj.xcode && xk.xcode, "an .ipa and a project of one game, each once"); xk.target = .mac; check(!xk.xcode, "only for iPhone"); let back = try! JSONDecoder().decode(Job.self, from: JSONEncoder().encode(xj)); check(back == xj && !back.xcode, "kept in the queue's file")
}

// ---- a download opened beside an installed one ----
do {
    let d = tmp.appendingPathComponent("arrive"), dl = d.appendingPathComponent("Downloads/Docked.app"), ap = d.appendingPathComponent("Applications"), up = d.appendingPathComponent("UserApps"), old = ap.appendingPathComponent("Docked.app", isDirectory: true), bk = d.appendingPathComponent("Backups")
    for u in [dl.deletingLastPathComponent(), ap, up] { try! fm.createDirectory(at: u, withIntermediateDirectories: true) }
    func sgn(_ u: URL) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); p.arguments = ["--force", "--sign", "-", u.path]; p.standardError = FileHandle.nullDevice; try! p.run(); p.waitUntilExit() }
    func put(_ u: URL, _ v: String, id: String = "local.dockside", tools: Bool = true) { try? fm.removeItem(at: u); try! fm.createDirectory(at: u.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true); try! fm.createDirectory(at: u.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true); try! fm.copyItem(atPath: "/usr/bin/true", toPath: u.path + "/Contents/MacOS/Docked"); try! PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundleShortVersionString": v, "CFBundleExecutable": "Docked", "CFBundlePackageType": "APPL"], format: .xml, options: 0).write(to: u.appendingPathComponent("Contents/Info.plist")); if tools { try! Data(v.utf8).write(to: u.appendingPathComponent("Contents/Resources/tools.tar.xz")) }; sgn(u) }
    func ask() -> Arrive.Offer? { Arrive.offer(me: dl, places: [ap, up]) }
    put(dl, "2.0"); check(ask() == .move(to: old), "none installed: moves"); put(old, "1.9"); check(ask() == .update(app: old, has: "1.9"), "an older one: updates"); for v in ["2.0", "2.0.1", "10.0"] { put(old, v); check(ask() == nil, "never over \(v)") }
    put(old, "1.0", id: "other.app"); check(ask() == .move(to: up.appendingPathComponent("Docked.app", isDirectory: true)), "never over another app"); try! fm.removeItem(at: old); try! fm.createSymbolicLink(at: old, withDestinationURL: dl); check(ask() == .move(to: up.appendingPathComponent("Docked.app", isDirectory: true)), "nor through a link"); try! fm.removeItem(at: old)
    put(old, "1.0"); check(Arrive.offer(me: old, places: [ap, up]) == nil, "the installed one asks nothing"); put(dl, "2.0", tools: false); check(ask() == nil, "nor does one without its tools take the place of one with"); put(dl, "2.0"); put(up.appendingPathComponent("Docked.app", isDirectory: true), "1.0"); check(ask()?.app == old, "the main one first")
    setxattr(dl.path, "com.apple.quarantine", "0081;0;x;", 9, 0, 0); setxattr(dl.path + "/Contents/Info.plist", "com.apple.quarantine", "0081;0;x;", 9, 0, 0); let o = ask()!
    try! Data("x".utf8).write(to: dl.appendingPathComponent("Contents/Resources/extra")); check((try? Arrive.go(dl, o, backups: bk)) == nil && Arrive.version(old) == "1.0" && (try! fm.contentsOfDirectory(atPath: ap.path)) == ["Docked.app"] && !fm.fileExists(atPath: bk.path), "a damaged download changes nothing"); try! fm.removeItem(at: dl.appendingPathComponent("Contents/Resources/extra"))
    put(old, "3.0"); check((try? Arrive.go(dl, o, backups: bk)) == nil && Arrive.version(old) == "3.0", "updated meanwhile: left alone"); put(old, "1.0")
    chmod(ap.path, 0o555); check((try? Arrive.go(dl, o, backups: bk)) == nil && Arrive.version(old) == "1.0", "not allowed: nothing happens"); chmod(ap.path, 0o755)
    check((try? Arrive.go(dl, o, backups: bk)) != nil && Arrive.version(old) == "2.0" && (try! fm.contentsOfDirectory(atPath: ap.path)) == ["Docked.app"], "in place, nothing else left"); let kept = (try? fm.contentsOfDirectory(atPath: bk.path)) ?? []; check(kept.count == 1 && kept[0].hasPrefix("Docked 1.0 before") && Arrive.version(bk.appendingPathComponent(kept[0])) == "1.0", "the old one is kept"); check(getxattr(old.path, "com.apple.quarantine", nil, 0, 0, 0) < 0 && getxattr(old.path + "/Contents/Info.plist", "com.apple.quarantine", nil, 0, 0, 0) < 0 && Arrive.version(dl) == "2.0" && getxattr(dl.path, "com.apple.quarantine", nil, 0, 0, 0) > 0, "not asked about twice; the download is untouched"); check(ask() == nil, "and then nothing to ask")
    try! fm.removeItem(at: old); try! fm.removeItem(at: up.appendingPathComponent("Docked.app", isDirectory: true)); let mv = ask()!; check((try? Arrive.go(dl, mv, backups: bk)) != nil && Arrive.version(old) == "2.0", "moved in")
}

// ---- keys, iPhone, the guide ----
let hexv = String(repeating: "a1", count: 16), okk = mk("k/prod.keys", "; note\nheader_key = \(hexv)\(hexv)\nmaster_key_00 = \(hexv)\nmaster_key_14 = \(hexv)\n"); check(readKeys(okk.path) == .good(newest: 20) && readKeys(okk.path).usable, "a keys file, and its newest"); check(!readKeys(okk.path).text.contains(hexv), "no value is shown")
check(readKeys(mk("k/a.keys", "master_key_00 = \(hexv)\n").path) == .incomplete && readKeys(mk("k/b.keys", "header_key = \(hexv)\(hexv)\n").path) == .incomplete, "parts missing"); check(readKeys(mk("k/c.keys", "hello\nname = value\n").path) == .notKeys && readKeys("/gone").self == .notKeys && readKeys(tmp.path) == .notKeys && readKeys(mk("k/d.keys", "").path) == .notKeys && readKeys(mk("k/e.keys", "master_key_00 = 1234\nheader_key = zz\n").path) == .notKeys, "not keys")
let pa = buildArguments(n, keys: "/k", phone: URL(fileURLWithPath: "/o/x.ipa")); check(pa.contains("ios") && !pa.contains("mac-app") && pa.contains("/o/x.ipa") && !pa.contains("--no-prebake"), "iPhone build"); check(buildArguments(n, keys: "/k").contains("mac-app") && !buildArguments(n, keys: "/k").contains("-o"), "Mac build as before")
let pd = tmp.appendingPathComponent("ph"); try! fm.createDirectory(at: pd, withIntermediateDirectories: true); check(phoneFile("A: B/C\\..", in: pd).lastPathComponent == "A BC.ipa" && phoneFile("../../x", in: pd).deletingLastPathComponent().path == pd.path && phoneFile("", in: pd).lastPathComponent == "Game.ipa", "file names"); _ = mk("ph/Z.ipa"); check(phoneFile("Z", in: pd).lastPathComponent == "Z 2.ipa", "never over another")
check(!looksLikeIPA(mk("ph/empty.ipa", "")) && !looksLikeIPA(mk("ph/text.ipa", String(repeating: "x", count: 5000))) && !looksLikeIPA(pd.appendingPathComponent("gone.ipa")), "not an app file"); let ipa = pd.appendingPathComponent("r.ipa"); try! (Data([0x50, 0x4B, 3, 4]) + Data(count: 5000)).write(to: ipa); check(looksLikeIPA(ipa), "an app file")
var tq = Queue(); var pj = job("P", "0100000000000009"); pj.target = .phone; check(tq.add(job("P", "0100000000000009")) && tq.add(pj) && !tq.add(pj), "the same game for Mac and iPhone, each once"); let oldQ = try! JSONDecoder().decode(Job.self, from: Data(#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"t","parts":["/a"],"place":"/g","quick":false,"after":"ask","bytes":1,"needsKeys":true,"sources":[]}"#.utf8)); check(!oldQ.phone, "a queue from before")
check(nextCheck([Check(title: "a", ok: true, detail: "", fix: ""), Check(title: "b", ok: false, detail: "", fix: ""), Check(title: "c", ok: false, detail: "", fix: "")])?.title == "b" && nextCheck([]) == nil, "one step at a time")

// ---- engine updates: only a signed engine, checked file by file, swapped in whole, and the one before kept ----
check(EngineEvent.parse(#"{"ev":"stage_end","k":6,"name":"Pipeline archive","ok":true,"warn":true,"summary":"failed, the app is packed without one"}"#) == .stageEnd(ok: true, warn: true, name: "Pipeline archive", summary: "failed, the app is packed without one"), "a step that finished without what it makes")
b = drive(#"echo '{"ev":"stage","k":1,"n":2,"name":"Pipeline archive"}'; echo '{"ev":"stage_end","k":1,"name":"Pipeline archive","ok":true,"warn":true,"summary":"failed"}'; echo '{"ev":"stage_end","k":2,"name":"Mac app","ok":true}'"#)
check(b.stage == "Done" && b.warnings == ["Pipeline archive: failed"], "warnings kept on a finished build")
let ek = Curve25519.Signing.PrivateKey(), epub = ek.publicKey.rawRepresentation.base64EncodedString(), eg = tmp.appendingPathComponent("eg")
func eput(_ p: String, _ s: String, x: Bool = false) { let u = eg.appendingPathComponent(p); try! fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try! Data(s.utf8).write(to: u); if x { chmod(u.path, 0o755) } }
eput("tools/.dockside-pin", pinnedEngine + "\n"); eput("tools/bin/python3", "py", x: true); eput("tools/engine/a.py", "old a"); eput("tools/engine/gone.txt", "bye"); eput("tools/engine/dm/games/X/game.tsv", "old")
eput("tools/engine/__pycache__/a.cpython.pyc", "cache"); eput("tools/engine/.DS_Store", "finder")
let tools0 = Engine.tree(eg.appendingPathComponent("tools/engine"))!
// the new engine, whole and as a difference
eput("new/engine/a.py", "new a"); eput("new/engine/dm/games/X/game.tsv", "old"); eput("new/engine/dm/games/Y/game.tsv", "new game"); eput("new/engine/bin/tool", "t", x: true)
let newTree = Engine.tree(eg.appendingPathComponent("new/engine"))!
let pyTree = run("/usr/bin/python3", ["-I", URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Bundle/engine_tree.py").path, "tree", eg.appendingPathComponent("new/engine").path]).out
check(pyTree.hasPrefix(newTree + " 4"), "the release script takes the same fingerprint: \(pyTree)")
check(tools0 != newTree && Engine.tree(eg.appendingPathComponent("tools/engine")) == tools0, "a fingerprint, the same each time")
eput("delta/engine/a.py", "new a"); eput("delta/engine/dm/games/Y/game.tsv", "new game"); eput("delta/engine/bin/tool", "t", x: true); eput("delta/engine.removed", "gone.txt\n")
func xz(_ dir: String, _ name: String) -> EngineInfo.Pack { let f = eg.appendingPathComponent("pub/" + name); try? fm.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true); let items = (try! fm.contentsOfDirectory(atPath: eg.appendingPathComponent(dir).path)).sorted(); run("/usr/bin/tar", ["-cJf", f.path, "-C", eg.appendingPathComponent(dir).path] + items); return EngineInfo.Pack(name: name, sha256: sha256(f)!, bytes: Int(folderSize(f))) }
let fullP = xz("new", "engine-full.tar.xz"); var deltaP = xz("delta", "engine-delta.tar.xz"); deltaP.from = pinnedEngine; deltaP.fromTree = tools0
let newCommit = String(repeating: "b", count: 40)
func manifest(_ c: String = newCommit, date: String = "2030-01-02T03:04:05Z", minApp: String = "1.0", tree: String = newTree, deltas: [EngineInfo.Pack]? = nil) -> Data { try! JSONEncoder().encode(EngineInfo(format: 1, commit: c, date: date, minApp: minApp, tree: tree, summary: "2 new game profiles", full: fullP, deltas: deltas ?? [deltaP])) }
func esig(_ m: Data, _ k: Curve25519.Signing.PrivateKey = ek) -> Data { try! k.signature(for: Engine.said(m)) }
let em = manifest()
check(Engine.read(em, esig(em), key: epub)?.commit == newCommit, "a signed engine is read"); check(Engine.read(em, esig(em, Curve25519.Signing.PrivateKey()), key: epub) == nil && Engine.read(em, Data(count: 64), key: epub) == nil, "another key's is not")
var bentM = em; bentM[bentM.count / 2] ^= 1; check(Engine.read(bentM, esig(em), key: epub) == nil, "nor one changed after signing"); check(Engine.read(em, try! ek.signature(for: em), key: epub) == nil, "nor a signature made for something else")
var badName = EngineInfo(format: 1, commit: newCommit, date: "2030-01-02T03:04:05Z", minApp: "1.0", tree: newTree, summary: "", full: fullP, deltas: []); badName.full.name = "../../x"; let bm = try! JSONEncoder().encode(badName); check(Engine.read(bm, esig(bm), key: epub) == nil, "a file name that leaves the release is refused")
let sigText = Data(esig(em).base64EncodedString().utf8), here = Engine.installed(eg.appendingPathComponent("tools"), key: epub)
check(here?.commit == pinnedEngine && here?.info == nil, "the engine Docked was built with is used")
check(Engine.answer(em, sigText, active: here, app: "2.0", key: epub) == .available(Engine.read(em, esig(em), key: epub)!), "a newer one is offered")
let old = manifest(date: "2001-01-01T00:00:00Z"); check(Engine.answer(old, Data(esig(old).base64EncodedString().utf8), active: here, key: epub) == .newest, "an older one is not")
let laterEngine = manifest(minApp: "99.0"); check(Engine.answer(laterEngine, Data(esig(laterEngine).base64EncodedString().utf8), active: here, key: epub) == .needsApp("99.0"), "one for a newer Docked waits for it")
check(Engine.answer(em, Data("junk".utf8), active: here, key: epub) == .unknown && Engine.answer(nil, nil, active: here, key: epub) == .unknown, "no answer, no offer")
// putting it in place
func fetchFrom(_ p: EngineInfo.Pack, _ dir: URL) -> URL? { let to = dir.appendingPathComponent(".engine-\(UUID().uuidString).download"); try? fm.copyItem(at: eg.appendingPathComponent("pub/" + p.name), to: to); return to }
var fetched: [String] = []
func prep(_ m: Data, works: Bool = true, free: Int64 = 1 << 40) throws -> URL { try Engine.prepare(manifest: m, sig: esig(m), root: eg, key: epub, app: "2.0", free: free, fetch: { fetched.append($0.name); return fetchFrom($0, $1) }, works: { _ in works }) }
func untouched(_ what: String) { check(Engine.tree(eg.appendingPathComponent("tools/engine")) == tools0 && !fm.fileExists(atPath: eg.path + "/tools.next") && !fm.fileExists(atPath: eg.path + "/engine.partial") && ((try? fm.contentsOfDirectory(atPath: eg.path)) ?? []).filter { $0.hasSuffix(".download") }.isEmpty, "nothing changed, nothing left: " + what) }
func prefuses(_ what: String, _ f: () throws -> URL) { do { _ = try f(); check(false, "went through: " + what) } catch { untouched(what) } }
prefuses("another key") { try Engine.prepare(manifest: em, sig: esig(em, Curve25519.Signing.PrivateKey()), root: eg, key: epub, app: "2.0", free: 1 << 40, fetch: fetchFrom, works: { _ in true }) }
prefuses("files that are not what was signed") { try prep(manifest(tree: String(repeating: "0", count: 64))) }
prefuses("an engine that does not start") { try prep(em, works: false) }
prefuses("no space") { try prep(em, free: 1000) }
prefuses("a download that is not the one signed") { var f = fullP; f.sha256 = String(repeating: "1", count: 64); var d = deltaP; d.sha256 = f.sha256; let m = try! JSONEncoder().encode(EngineInfo(format: 1, commit: newCommit, date: "2030-01-02T03:04:05Z", minApp: "1.0", tree: newTree, summary: "", full: f, deltas: [d])); return try prep(m) }
prefuses("one for a newer Docked") { try prep(manifest(minApp: "3.0")) }
fetched = []; let next = try? prep(em)
check(next != nil && fetched == ["engine-delta.tar.xz"] && Engine.tree(eg.appendingPathComponent("tools.next/engine")) == newTree, "only the difference is downloaded, and it comes out exactly as signed")
check(Engine.tree(eg.appendingPathComponent("tools/engine")) == tools0 && Engine.installed(eg.appendingPathComponent("tools"), key: epub)?.commit == pinnedEngine, "the tools in use are not touched while it is made")
check(Engine.installed(eg.appendingPathComponent("tools.next"), key: epub, app: "2.0")?.commit == newCommit && Engine.installed(eg.appendingPathComponent("tools.next"), key: epub, app: "0.9") == nil, "the new one is used only by a Docked recent enough")
try! Engine.swapIn(next!, root: eg)
check(Engine.installed(eg.appendingPathComponent("tools"), key: epub, app: "2.0")?.commit == newCommit && Engine.installed(eg.appendingPathComponent("tools.previous"), key: epub)?.commit == pinnedEngine && !fm.fileExists(atPath: eg.path + "/tools.next"), "swapped in, the old one kept")
check((try? String(contentsOf: eg.appendingPathComponent("tools/bin/python3"), encoding: .utf8)) == "py", "the rest of the tools carried over")
try! Engine.goBack(root: eg, key: epub, app: "2.0"); check(Engine.installed(eg.appendingPathComponent("tools"), key: epub)?.commit == pinnedEngine && Engine.installed(eg.appendingPathComponent("tools.previous"), key: epub, app: "2.0")?.commit == newCommit, "back to the one before, and forward again is possible")
try! Engine.goBack(root: eg, key: epub, app: "2.0"); Engine.forget()
// the whole engine when the one here is not the one the difference was made from
eput("tools.previous/engine/extra", "x"); try! Engine.goBack(root: eg, key: epub, app: "2.0"); fetched = []
let next2 = try? prep(manifest(String(repeating: "c", count: 40), date: "2031-01-01T00:00:00Z")); check(next2 != nil && fetched == ["engine-full.tar.xz"] && Engine.tree(eg.appendingPathComponent("tools.next/engine")) == newTree, "a changed engine here gets the whole engine")
try? fm.removeItem(at: eg.appendingPathComponent("tools.next"))
// an older signed engine than the one this Docked carries is not used
eput("old/.dockside-pin", String(repeating: "d", count: 40)); let om = manifest(String(repeating: "d", count: 40), date: "2001-01-01T00:00:00Z"); try! om.write(to: eg.appendingPathComponent("old/.dockside-engine.json")); eput("old/.dockside-engine.sig", esig(om).base64EncodedString())
check(Engine.installed(eg.appendingPathComponent("old"), key: epub) == nil, "an engine older than Docked's own is not used")
// a difference cannot reach outside the engine
eput("bad/engine/x", "x"); eput("bad/engine.removed", "../../../victim\n"); eput("victim", "safe"); eput("tgt/engine/keep", "k")
check((try? Engine.apply(eg.appendingPathComponent("bad/engine"), removed: eg.appendingPathComponent("bad/engine.removed"), to: eg.appendingPathComponent("tgt/engine"))) == nil && (try? String(contentsOf: eg.appendingPathComponent("victim"), encoding: .utf8)) == "safe", "a removal outside the engine is refused")
eput("leftover/tools.next/x", "x"); eput("leftover/engine.partial/y", "y"); eput("leftover/.engine-1.download", "z"); eput("leftover/tools/keep", "k"); Engine.tidy(root: eg.appendingPathComponent("leftover"))
check((try? fm.contentsOfDirectory(atPath: eg.appendingPathComponent("leftover").path)) == ["tools"], "what an update cut short is cleared")
check(Engine.isCommit(pinnedEngine) && Engine.pinnedDate > Date(timeIntervalSince1970: 1_700_000_000), "the pin and its date are read")

// ---- each converted game is checked ----
func fakeGame(_ name: String, pso: [String: String]? = nil) -> URL {
    let a = tmp.appendingPathComponent("vg/\(name).app"); try? fm.removeItem(at: a)
    try! fm.createDirectory(at: a.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true); try! Data("x".utf8).write(to: a.appendingPathComponent("Contents/MacOS/dmhost")); chmod(a.path + "/Contents/MacOS/dmhost", 0o755)
    NSDictionary(dictionary: ["DMTitleID": "0100000000010000", "CFBundleName": name]).write(to: a.appendingPathComponent("Contents/Info.plist"), atomically: true)
    if let pso { let d = a.appendingPathComponent("Contents/PlugIns/PipelineArchive.bundle/Contents/Resources/pso"); try! fm.createDirectory(at: d, withIntermediateDirectories: true); for (k, v) in pso { try! Data(v.utf8).write(to: d.appendingPathComponent(k)) } }
    return a
}
let whole = ["applegpu_g14s.mtl4a": "a", "prebuilt.tsv": "p", "archive.tsv": "arch\tapplegpu_g14s\nbases\t100\nfailed\t0 bases, 0 compute pipelines (metal-tt could not compile them: left to the device)\n"]
func gc(_ a: URL, quick: Bool = false, warned: [String] = [], signed: Bool? = true) -> GameCheck { checkGame(a, titleID: "0100000000010000", quick: quick, warned: warned, verify: { _ in signed }) }
check(gc(fakeGame("Fine", pso: whole)).ok && gc(fakeGame("NoGraphics")).ok, "a whole game passes, with or without graphics to prepare")
check(gc(fakeGame("Fine", pso: whole), signed: nil).ok, "a signature check that could not tell is not held against it")
check(!gc(fakeGame("Unsigned", pso: whole), signed: false).problems.isEmpty, "a signature that does not hold is a problem")
check(!checkGame(fakeGame("Other"), titleID: "0100000000020000", quick: false, warned: [], verify: { _ in true }).problems.isEmpty, "another game's app is a problem")
let half = whole.filter { $0.key != "prebuilt.tsv" }; check(gc(fakeGame("Half", pso: half)).problems.isEmpty && gc(fakeGame("Half", pso: half)).notes.contains { $0.contains("incomplete") }, "a partly built archive is noticed")
var some = whole; some["archive.tsv"] = "failed\t12 bases, 3 compute pipelines (x)\n"; check(gc(fakeGame("Some", pso: some)).notes.contains { $0.hasPrefix("15 of") }, "pipelines the compiler left out are counted")
check(gc(fakeGame("Warned"), warned: ["Pipeline archive: failed"]).notes.count == 1 && gc(fakeGame("Quick"), quick: true).ok, "a step that warned is noticed; a quick conversion has no archive to check")
check(gc(fakeGame("Half", pso: half)).text().contains("leftovers were kept") && gc(fakeGame("Unsigned"), signed: false).text().hasPrefix("Converted, but") && gc(fakeGame("Unsigned"), signed: false).text(again: true).contains("second time"), "said plainly")
check(gc(fakeGame("Half", pso: half)).mendable && gc(fakeGame("Unsigned"), signed: false).mendable && !checkGame(fakeGame("Other"), titleID: "0100000000020000", quick: false, warned: [], verify: { _ in true }).mendable, "converting again is tried only where it can help")
let realApp = fakeGame("Real"); let cs = run("/usr/bin/codesign", ["--force", "--sign", "-", realApp.path]); check(cs.code != 0 || signatureHolds(realApp) == true, "codesign agrees with a signed app")

// ---- finding covers and details ----
check(Lookup.crc32(mk("lk/check.bin", "123456789")) == 0xCBF43926, "CRC-32 check value")
func mps(_ t: String) -> [UInt8] { let b = Array(t.utf8); return (b.count < 32 ? [0xA0 | UInt8(b.count)] : [0xD9, UInt8(b.count)]) + b }
func rec(_ f: [(String, [UInt8])]) -> [UInt8] { [0x80 | UInt8(f.count)] + f.flatMap { mps($0.0) + $0.1 } }
func bin(_ c: UInt32) -> [UInt8] { [0xC4, 4, UInt8(c >> 24), UInt8(c >> 16 & 0xFF), UInt8(c >> 8 & 0xFF), UInt8(c & 0xFF)] }
let gbCRC = Lookup.crc32(gb)!
let rdb: [UInt8] = Array("RARCHDB".utf8) + [0] + [UInt8](repeating: 0, count: 8)
    + rec([("name", mps("Puzzle Box (Japan)")), ("crc", bin(gbCRC)), ("releaseyear", [0xCD, 0x07, 0xC6]), ("publisher", mps("Box Co")), ("users", [0x92, 0x01, 0xFF]), ("rumble", [0xC0])])
    + rec([("name", mps("Legend of Game, The - Part 2 (USA)")), ("serial", [0xC4, 10] + Array("SLUS-00001".utf8)), ("crc", bin(1)), ("releaseyear", [0xCD, 0x07, 0xCA]), ("publisher", mps("Maker")), ("genre", mps("Adventure"))])
    + rec([("name", mps("Legend of Game, The - Part 2 (Europe)")), ("crc", bin(2)), ("developer", mps("Dev")), ("description", mps("A long story about a game that is told across a whole box back."))])
    + rec([("name", mps("Legend of Gamer (USA)")), ("crc", bin(3))])
    + rec([("name", mps("Space Race (USA) [h1]")), ("crc", bin(4))]) + rec([("name", mps("Space Race (USA)")), ("crc", bin(5)), ("size", [0xCE, 0, 1, 0, 0])])
    + [0xC0] + [0x81, 0xA1, 0x78, 0x01]
let parsed = RDB.parse(Data(rdb)); check(parsed?.count == 6 && parsed?[0].year == 1990 && parsed?[0].crc == gbCRC && parsed?[1].serial == "SLUS-00001" && parsed?[2].about?.hasPrefix("A long") == true, "a RetroArch database read, nil and arrays skipped, its index left alone")
check(RDB.parse(Data("RARCHDB".utf8)) == nil && RDB.parse(Data(Array(rdb.prefix(40)))) == nil && RDB.parse(Data([UInt8](repeating: 0, count: 64))) == nil, "a cut or foreign file is refused")
check(Lookup.titleKey("Final Fantasy III, The (USA) (Rev 1)") == "final fantasy 3" && Lookup.titleKey("Pokémon - Red Version") == "pokemon red version" && Lookup.titleKey("Mario & Luigi") == "mario and luigi" && Lookup.titleKey("X (Japan)") == "x", "one key for a title however it is written")
check(!Set(Lookup.serialKeys("SLUS-00001GH-2")).isDisjoint(with: Lookup.serialKeys("SLUS-00001")) && !Set(Lookup.serialKeys("RVL-RYWP-EUR")).isDisjoint(with: Lookup.serialKeys("RYWP01")) && Set(Lookup.serialKeys("SLUS-00002")).isDisjoint(with: Lookup.serialKeys("SLUS-00001")), "serials meet however a list writes them")
let gl = GameList(parsed ?? [])
let lg = gl.candidate(Lookup.titleKey("Legend of Game, The - Part 2"), how: "name"); check(lg?.info.year == 1994 && lg?.info.developer == "Dev" && lg?.info.publisher == "Maker" && lg?.info.about?.hasPrefix("A long") == true && lg?.names.first == "Legend of Game, The - Part 2 (USA)" && lg?.info.name == "The Legend of Game - Part 2", "one title's versions give their details together, its USA name first")
check(gl.candidate(Lookup.titleKey("Legend of Game - Part 2"), how: "name", region: ["europe"])?.names.first?.contains("Europe") == true, "the player's own region first")
check(gl.candidate("space race", how: "name")?.names == ["Space Race (USA)"], "hacks and bad dumps aren't used for the cover")
if case .found(let c) = Lookup.byName("Legend of Game, The - Part 2", in: gl) { check(c.key == "legend of game part 2", "found by name") } else { check(false, "found by name") }
if case .choose(let cs) = Lookup.byName("Legend of Game", in: gl) { check(cs.first?.key == "legend of game part 2" && cs.contains { $0.key == "legend of gamer" }, "close names: the player chooses") } else { check(false, "close names: the player chooses") }
check(Lookup.byName("Something Else Entirely", in: gl) == .none, "nothing like it: nothing")
// The list comes from a fixed commit and must match its SHA-256
let lkRoot = tmp.appendingPathComponent("lk/src"); Lookup.source = lkRoot.absoluteString.hasSuffix("/") ? String(lkRoot.absoluteString.dropLast()) : lkRoot.absoluteString; Lookup.wikipedia = nil
func listAt(_ folder: String) -> URL { lkRoot.appendingPathComponent("libretro/libretro-database/\(Lookup.database)/rdb/\(folder).rdb") }
for f in ["Nintendo - Game Boy", "Sony - PlayStation", "Nintendo - Super Nintendo Entertainment System"] { try! fm.createDirectory(at: listAt(f).deletingLastPathComponent(), withIntermediateDirectories: true); try! Data(rdb).write(to: listAt(f)) }
let rdbSHA = SHA256.hash(data: Data(rdb)).map { String(format: "%02x", $0) }.joined()
Lookup.lists["Nintendo - Game Boy"] = "0000"; Lookup.forget(); check((try? Lookup.match(Rom(id: "ROM:GB:1", name: "Puzzle Box", console: "gb", path: gb.path))) == nil && !fm.fileExists(atPath: Lookup.home.path + "/Lists/Nintendo - Game Boy.rdb"), "a list that isn't the reviewed one is refused")
for f in ["Nintendo - Game Boy", "Sony - PlayStation", "Nintendo - Super Nintendo Entertainment System"] { Lookup.lists[f] = rdbSHA }
let gbRom = Rom(id: romID(gb, "gb"), name: "Puzzle Box", console: "gb", path: gb.path)
if case .found(let c)? = try? Lookup.match(gbRom) { check(c.info.how == "checksum" && c.info.year == 1990 && fm.fileExists(atPath: Lookup.home.path + "/Lists/Nintendo - Game Boy.rdb"), "found by checksum, the list kept") } else { check(false, "found by checksum") }
let ps1Rom = Rom(id: "ROM:PS1:1", name: "One", console: "ps1", path: ps1cue.path)
if case .found(let c)? = try? Lookup.match(ps1Rom) { check(c.info.how == "serial" && c.key == "legend of game part 2", "found by disc serial") } else { check(false, "found by disc serial") }
check((try? Lookup.search("legend", console("gb")!))?.count == 2, "searching the list by hand")
// Checksums the way the list keeps them: in a zip, without a copier header, in N64 byte order
check(Lookup.crcs(tmp.appendingPathComponent("rom/real.zip"), "snes") == [Lookup.crc32(sf)!], "a zip's own CRC, nothing unpacked")
let nes = mk("lk/Game.nes", "NES\u{1A}" + String(repeating: "\0", count: 12) + "body"), body = mk("lk/body.bin", "body"); check(Set(Lookup.crcs(nes, "nes")) == [Lookup.crc32(nes)!, Lookup.crc32(body)!], "with and without the iNES header")
let v64 = tmp.appendingPathComponent("lk/Game.v64"), z64 = tmp.appendingPathComponent("lk/Game.z64"); try! Data([0x37, 0x80, 0x40, 0x12, 1, 2, 3, 4]).write(to: v64); try! Data([0x80, 0x37, 0x12, 0x40, 2, 1, 4, 3]).write(to: z64); check(Lookup.crcs(v64, "n64").contains(Lookup.crc32(z64)!), "an N64 game in its list's byte order")
check(Lookup.crcs(ps1cue, "ps1").isEmpty, "a disc isn't read whole")
// The cover: only a real picture, drawn again before it is kept
func png(_ w: Int, _ h: Int) -> Data { let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!; c.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: w, height: h)); let d = NSMutableData(); let dst = CGImageDestinationCreateWithData(d, "public.png" as CFString, 1, nil)!; CGImageDestinationAddImage(dst, c.makeImage()!, nil); CGImageDestinationFinalize(dst); return d as Data }
let keptCover = tmp.appendingPathComponent("lk/kept.png"); check(Lookup.keep(png(1000, 800), at: keptCover) && fm.fileExists(atPath: keptCover.path) && !Lookup.keep(Data("<html>not a picture</html>".utf8), at: tmp.appendingPathComponent("lk/no.png")) && !Lookup.keep(png(4, 4), at: tmp.appendingPathComponent("lk/tiny.png")), "a picture kept, anything else refused")
if let src = CGImageSourceCreateWithURL(keptCover as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] { check((p[kCGImagePropertyPixelWidth] as? Int) == 720, "made small") } else { check(false, "made small") }
let thumbs = lkRoot.appendingPathComponent("libretro-thumbnails/Nintendo_-_Game_Boy/\(Lookup.covers["Nintendo - Game Boy"]!)/Named_Boxarts"); try! fm.createDirectory(at: thumbs, withIntermediateDirectories: true); try! png(300, 300).write(to: thumbs.appendingPathComponent("Puzzle_Box (Japan).png"))
check(Lookup.fetchCover(gbRom, names: ["Not There (USA)", "Puzzle/Box (Japan)"]) == Lookup.artFile(gbRom.id) && RetroArch.art(gbRom) == Lookup.artFile(gbRom.id), "the cover from the fixed commit, by its list name, shown for the game")
check(Lookup.url("a b/c&d#e.png").absoluteString.hasSuffix("/a%20b/c%26d%23e.png"), "names are escaped in the address")
do { _ = try Lookup.get(URL(string: "http://example.com/x")!, limit: 10); check(false, "plain http refused") } catch { check(true, "plain http refused") }
// Kept with the game, and read by an earlier library too
var il = LibraryData(); var withInfo = gbRom; withInfo.info = GameInfo(title: "Puzzle Box (Japan)", year: 1990, publisher: "Box Co", how: "checksum"); il.addRom(withInfo); let ilf = tmp.appendingPathComponent("lk/library.json"); il.save(ilf); check(LibraryData.load(ilf).roms.first?.info == withInfo.info, "details saved with the game")
check(GameInfo(title: "Legend of Game, The (USA)", year: 1994, publisher: "Maker", how: "name").line == "1994 · Maker", "a short line of details")

// ---- the organized library (Organize.swift) ----
let olib = tmp.appendingPathComponent("org/Library"), osrc = tmp.appendingPathComponent("org/src")
check(Organize.folder("gba", in: olib).lastPathComponent == "Game Boy Advance" && Organize.folder("switch2", in: olib).lastPathComponent == "Switch 2", "a folder per console, by its name")
check(Organize.safe("../Zelda: A/B") == "-Zelda - A-B" && Organize.safe("  ") == "Game" && Organize.safe(String(repeating: "x", count: 300)).count == 120, "safe file names")
check(Organize.words(#"FILE "Track 01.bin" BINARY"#) == ["FILE", "Track 01.bin", "BINARY"], "quoted words")
let ocue = mk("org/src/Disc Game (USA).cue", "FILE \"Disc Game (USA) (Track 1).bin\" BINARY\n  TRACK 01 MODE2/2352\nFILE \"Disc Game (USA) (Track 2).bin\" BINARY\nFILE \"../escape.bin\" BINARY\n"); _ = mk("org/src/Disc Game (USA) (Track 1).bin"); _ = mk("org/src/Disc Game (USA) (Track 2).bin"); _ = mk("org/escape.bin")
check(Organize.companions(ocue).map(\.lastPathComponent) == ["Disc Game (USA) (Track 1).bin", "Disc Game (USA) (Track 2).bin"], "a cue's tracks, and nothing outside its folder")
let gdi = mk("org/src/dc/game.gdi", "3\n1 0 4 2352 track01.bin 0\n2 600 0 2352 \"track 02.raw\" 0\n"); _ = mk("org/src/dc/track01.bin"); _ = mk("org/src/dc/track 02.raw")
check(Organize.companions(gdi).count == 2, "a gdi's tracks")
let m3u = mk("org/src/multi/Game.m3u", "#EXTM3U\nGame (Disc 1).cue\nGame (Disc 2).cue\n"); _ = mk("org/src/multi/Game (Disc 1).cue", "FILE \"d1.bin\" BINARY\n"); _ = mk("org/src/multi/d1.bin"); _ = mk("org/src/multi/Game (Disc 2).cue", "FILE \"d2.bin\" BINARY\n"); _ = mk("org/src/multi/d2.bin")
check(Set(Organize.companions(m3u).map(\.lastPathComponent)) == ["Game (Disc 1).cue", "d1.bin", "Game (Disc 2).cue", "d2.bin"], "an m3u's discs and their tracks")
let sfc = mk("org/src/Legend of Game, The (USA).sfc", "rom")
check(Organize.place(sfc, console: "snes", name: "The Legend of Game", naming: .game, in: olib).path == olib.path + "/SNES/The Legend of Game.sfc", "one file: named after the game")
check(Organize.place(sfc, console: "snes", name: "x", naming: .original, in: olib).lastPathComponent == sfc.lastPathComponent, "or keeps its name")
check(Organize.place(ocue, console: "ps1", name: "Disc Game", naming: .game, in: olib).path == olib.path + "/PlayStation/Disc Game/Disc Game (USA).cue", "files that belong together: a folder, their own names")
check(Organize.place(sfc, console: "snes", name: "G", naming: .game, organized: false, in: olib).path == olib.path + "/" + sfc.lastPathComponent, "not organized: straight into the library folder")
let copied = try! Organize.file(sfc, console: "snes", name: "The Legend of Game", mode: .copy, naming: .game, in: olib)
check(copied.lastPathComponent == "The Legend of Game.sfc" && fm.fileExists(atPath: sfc.path) && (try? String(contentsOf: copied, encoding: .utf8)) == "rom", "copied, the original stays")
let second = try! Organize.file(sfc, console: "snes", name: "The Legend of Game", mode: .copy, naming: .game, in: olib)
check(second.lastPathComponent == "The Legend of Game 2.sfc", "a name that is taken gets a number; nothing is replaced")
check(Organize.isPlaced(second, Organize.place(sfc, console: "snes", name: "The Legend of Game", naming: .game, in: olib)) && !Organize.isPlaced(sfc, copied), "a numbered copy is in its place")
check(try! Organize.file(copied, console: "snes", name: "The Legend of Game", mode: .move, naming: .game, in: olib) == copied, "already in its place: left alone")
check(try! Organize.file(sfc, console: "snes", name: "x", mode: .leave, naming: .game, in: olib) == sfc, "leave: left alone")
let movedCue = try! Organize.file(ocue, console: "ps1", name: "Disc Game", mode: .move, naming: .game, in: olib)
check(movedCue.path == olib.path + "/PlayStation/Disc Game/Disc Game (USA).cue" && fm.fileExists(atPath: movedCue.deletingLastPathComponent().appendingPathComponent("Disc Game (USA) (Track 2).bin").path) && !fm.fileExists(atPath: ocue.path) && !fm.fileExists(atPath: osrc.appendingPathComponent("Disc Game (USA) (Track 1).bin").path), "moved with its tracks")
check(fm.fileExists(atPath: tmp.appendingPathComponent("org/escape.bin").path), "a file outside the game's folder is never taken")
let copiedM3u = try! Organize.file(m3u, console: "ps1", name: "Game", mode: .copy, naming: .game, in: olib)
check(fm.fileExists(atPath: copiedM3u.deletingLastPathComponent().appendingPathComponent("d2.bin").path) && fm.fileExists(atPath: m3u.path) && !((try? fm.contentsOfDirectory(atPath: olib.appendingPathComponent("PlayStation").path)) ?? []).contains { $0.hasSuffix(".partial") }, "a copied set is whole, with nothing half-made left")
// an app
let oapp = mk("org/apps/Foo Game.app/Contents/Info.plist", #"<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleName</key><string>Foo Game</string><key>DMTitleID</key><string>0100000000020000</string></dict></plist>"#).deletingLastPathComponent().deletingLastPathComponent()
let filedApp = try! Organize.fileApp(oapp, mode: .move, in: olib)
check(filedApp.path == olib.path + "/Switch/Foo Game.app" && !fm.fileExists(atPath: oapp.path) && gameAt(filedApp)?.titleID == "0100000000020000", "a converted game moves into the Switch folder")
check(libraryFolders(olib).map(\.lastPathComponent).sorted() == ["Library", "PlayStation", "SNES", "Switch"], "the library folder and its console folders")
// saves follow a renamed game
let osaves = tmp.appendingPathComponent("org/saves"); _ = mk("org/saves/Legend of Game, The (USA).srm", "save"); _ = mk("org/saves/Other.srm")
Organize.carrySaves(from: sfc, to: copied, in: [osaves], move: false)
check(fm.fileExists(atPath: osaves.appendingPathComponent("The Legend of Game.srm").path) && fm.fileExists(atPath: osaves.appendingPathComponent("Legend of Game, The (USA).srm").path) && !fm.fileExists(atPath: osaves.appendingPathComponent("The Legend of Game.srm.srm").path), "saves follow the game's new name")
// what Organize Library would move
let looseRom = mk("org/Library/loose.gba"), outside = mk("org/elsewhere/away.gba")
let pg = [Game(url: looseRom, name: "Loose", titleID: "ROM:GBA:1", rom: Rom(id: "ROM:GBA:1", name: "Loose", console: "gba", path: looseRom.path)), Game(url: outside, name: "Away", titleID: "ROM:GBA:2", rom: Rom(id: "ROM:GBA:2", name: "Away", console: "gba", path: outside.path)), Game(url: copied, name: "The Legend of Game", titleID: "ROM:SNES:3", rom: Rom(id: "ROM:SNES:3", name: "The Legend of Game", console: "snes", path: copied.path)), Game(url: movedCue, name: "Disc Game", titleID: "ROM:PS1:4", rom: Rom(id: "ROM:PS1:4", name: "Disc Game", console: "ps1", path: movedCue.path)), gameAt(filedApp)!]
let plan = Organize.plan(pg, owned: [olib], lib: olib, naming: .game)
check(plan.map(\.game.name) == ["Loose"] && plan[0].to.path == olib.path + "/Game Boy Advance/Loose.gba", "only what is out of place in Docked's own folders")
// games that go missing, and ones that move
var oldata = LibraryData(); let gA = gameAt(filedApp)!
var shown = oldata.settle(found: [gA]); check(shown.isEmpty && oldata.apps[filedApp.path] == "0100000000020000", "a converted game is remembered")
shown = oldata.settle(found: [], exists: { _ in false }); check(shown.count == 1 && shown[0].missing && shown[0].titleID == "0100000000020000", "gone: still shown, as missing")
var omoved = gA; omoved.url = tmp.appendingPathComponent("org/other/Foo Game.app")
shown = oldata.settle(found: [omoved], exists: { _ in false }); check(shown.isEmpty && oldata.apps.count == 1 && oldata.apps[omoved.url.path] != nil, "found somewhere else: it omoved, the old place is dropped")
oldata.removeApp(omoved.url.path); check(oldata.apps.isEmpty && oldata.removed == [omoved.url.path], "removed by hand, and remembered as removed")
oldata.addApp(omoved.url.path, "0100000000020000"); check(oldata.removed.isEmpty, "added again")
let olf = tmp.appendingPathComponent("org/library.json"); oldata.save(olf); check(LibraryData.load(olf).apps == oldata.apps, "places saved")
check(drive(of: "/Volumes/NoSuchDriveHere/Games/x.sfc")?.name == "NoSuchDriveHere" && drive(of: "/Volumes/NoSuchDriveHere/x")?.connected == false && drive(of: "/Users/me/x") == nil, "a drive that isn't connected")
check(whereMissing("/Volumes/NoSuchDriveHere/x.sfc") == "On NoSuchDriveHere, which isn't connected" && whereMissing("/nope/x") == "Can't be found", "said in words")
// finding games
_ = mk("org/find/Nintendo - Game Boy/Puzzle.gb"); _ = mk("org/find/deep/a/b/c/d/e/f/Too Deep.gb"); _ = mk("org/find/x_build/Hidden.gb"); _ = mk("org/find/Disc.cue", "FILE \"Disc.bin\" BINARY\n"); _ = mk("org/find/Disc.bin"); _ = mk("org/find/Game.nsp")
let fapp = mk("org/find/Bar.app/Contents/Info.plist", #"<?xml version="1.0"?><plist version="1.0"><dict><key>DMTitleID</key><string>0400000000030000</string></dict></plist>"#)
let files = Discover.files(in: [tmp.appendingPathComponent("org/find")])
check(files.contains { $0.lastPathComponent == "Puzzle.gb" } && !files.contains { $0.lastPathComponent == "Too Deep.gb" || $0.lastPathComponent == "Hidden.gb" || $0.lastPathComponent == "Info.plist" } && files.contains { $0.lastPathComponent == "Bar.app" }, "folders a few levels down; not inside apps or build folders")
let fl = Discover.look(files, source: "Test", known: [], switchFiles: true)
check(fl.contains { $0.name == "Puzzle" && $0.kind == .rom("gb") } && fl.contains { $0.kind == .app("0400000000030000") && $0.console == "switch2" } && fl.contains { $0.kind == .switchFile }, "games, converted games and Switch files told apart")
check(fl.contains { $0.url.lastPathComponent == "Disc.cue" && { if case .choose = $0.kind { return true }; return false }($0) } && !fl.contains { $0.url.lastPathComponent == "Disc.bin" }, "a disc several consoles use is asked about; its tracks are not games")
check(Discover.look(files, source: "Test", known: [fapp.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path]).allSatisfy { if case .app = $0.kind { return false }; return true }, "games already in the library are left out")
check(pickRoms([tmp.appendingPathComponent("org/find")]).contains { $0.lastPathComponent == "Puzzle.gb" }, "a dropped folder is looked through, folders inside it too")
let lpl = mk("org/ra/playlists/Nintendo - Game Boy.lpl", "{\"version\":\"1.5\",\"items\":[{\"path\":\"\(tmp.path)/org/find/Nintendo - Game Boy/Puzzle.gb\"},{\"path\":\"\(tmp.path)/org/gone.gb\"},{\"path\":\"\(tmp.path)/org/find/Disc.cue#inside\"}]}")
check(Discover.retroArchGames(lpl.deletingLastPathComponent()).map(\.lastPathComponent) == ["Puzzle.gb", "Disc.cue"], "games RetroArch knows, from its playlists")
let ryu = mk("org/ryu/Config.json", "{\"game_dirs\":[\"/Volumes/SSD/Switch\"]}"); check(Discover.ryujinxFolders(ryu).map(\.path) == ["/Volumes/SSD/Switch"], "Ryujinx's game folders")

print("\(passed) passed, \(failed) failed"); exit(failed == 0 ? 0 : 1)
