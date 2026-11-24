import Foundation
var passed = 0, failed = 0
func check(_ ok: Bool, _ what: String) { if ok { passed += 1 } else { failed += 1; print("FAIL:", what) } }
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
// RetroArch
RetroArch.support = tmp.appendingPathComponent("RA"); let sn = console("snes")!; check(RetroArch.core(sn) == nil && RetroArch.problem(sn, rom: sf.path)?.contains("Snes9x") == true, "missing core explained"); _ = mk("RA/cores/bsnes_libretro.dylib"); check(RetroArch.core(sn)?.lastPathComponent == "bsnes_libretro.dylib", "next best core"); _ = mk("RA/cores/snes9x_libretro.dylib"); check(RetroArch.core(sn)?.lastPathComponent == "snes9x_libretro.dylib", "best core"); check(RetroArch.problem(sn, rom: "/gone.sfc")?.contains("found") == true, "missing file explained")
check(RetroArch.arguments(core: URL(fileURLWithPath: "/c a.dylib"), rom: "/x/-f --config $(rm) \"q\".sfc") == ["-L", "/c a.dylib", "/x/-f --config $(rm) \"q\".sfc"], "odd file names stay one argument"); RetroArch.app = tmp.appendingPathComponent("No.app"); check(RetroArch.problem(sn, rom: sf.path)?.contains("need RetroArch") == true, "no RetroArch explained")
let ar = Rom(id: id1, name: "G", console: "snes", path: sf.path); check(RetroArch.art(ar) == nil, "no art"); _ = mk("RA/thumbnails/Nintendo - Super Nintendo Entertainment System/Named_Boxarts/\(sf.deletingPathExtension().lastPathComponent).png"); check(RetroArch.art(ar)?.path.contains("Named_Boxarts") == true, "RetroArch's art"); _ = mk("Artwork/" + id1.replacingOccurrences(of: ":", with: "-") + ".png"); check(RetroArch.art(ar)?.path.contains("Artwork") == true, "the player's own art first")
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

print("\(passed) passed, \(failed) failed"); exit(failed == 0 ? 0 : 1)
