// Dockside's own build code against the real installed engine, with junk input in a temporary folder.
import Foundation
var passed = 0, failed = 0
func check(_ ok: Bool, _ what: String) { if ok { passed += 1 } else { failed += 1; print("FAIL:", what) } }
let root = Paths.root
func mk(_ p: String, _ d: Data) -> URL { let u = root.appendingPathComponent(p); try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try! d.write(to: u); return u }
func build(_ urls: [URL], keys: String?) -> Builder {
    let b = Builder(); var done = false; b.onFinish = { done = true }
    b.start(try! resolveInput(urls), keys: keys)
    let end = Date().addingTimeInterval(90); while !done && b.error == nil && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    let e2 = Date().addingTimeInterval(5); while !done && Date() < e2 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    check(done, "engine run ended"); return b
}
for c in runChecks() { check(c.ok, "setup: \(c.title) (\(c.detail))") }
check(isTested("0100000000010000"), "real profile found"); check(!isTested("0100000000000001"), "missing profile not found")
let keys = mk("k/prod.keys", Data("header_key = 00\n".utf8))
var b = build([mk("dl/My Fake Game [0100000000010000][v0].nsp", Data(repeating: 7, count: 4096))], keys: keys.path)
check(b.stage == "Failed" && b.error?.contains("no game package") == true, "junk package refused: \(b.error ?? "nil")")
for f in ["main", "main.npdm", "sdk", "rtld"] { _ = mk("dump dir/base/exefs/" + f, Data(repeating: 9, count: 512)) }
_ = mk("dump dir/base/romfs/a", Data("x".utf8))
b = build([root.appendingPathComponent("dump dir")], keys: nil)
check(b.stage == "Failed" && b.error?.contains("not an NPDM") == true, "junk dump refused: \(b.error ?? "nil")")
print("real engine: \(passed) passed, \(failed) failed"); exit(failed == 0 ? 0 : 1)
