// Signs with Docked's private key, which never goes in the repository. The key is read from DOCKED_SIGNING_KEY: the 32 raw bytes, in base64.
//   swift Bundle/sign.swift --public               prints the public key, to compare with Update.publicKey
//   swift Bundle/sign.swift <prefix> <file>         prints the signature of prefix + the file's bytes, in base64
//   swift Bundle/sign.swift --check <prefix> <file> <signature file>   checks one with the public key in Sources/Update.swift's place (DOCKED_PUBLIC_KEY)
//   swift Bundle/sign.swift --update <version> <Docked-Update.zip>     signs an app update exactly as Update.said reads it: "docked-update-v1|<version>|" + the zip's SHA-256
//   swift Bundle/sign.swift --check-update <version> <zip> <signature file>   checks one the way the app does (DOCKED_PUBLIC_KEY)
// An app update must use --update. Signing the zip's raw bytes (the <prefix> <file> form) uploads fine but every Docked says it can't be verified: 1.12.0 shipped that way.
import CryptoKit
import Foundation

let a = Array(CommandLine.arguments.dropFirst()), env = ProcessInfo.processInfo.environment
func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }
func bytes(_ p: String) -> Data { guard let d = FileManager.default.contents(atPath: p) else { fail("cannot read \(p)") }; return d }
func updateSaid(_ version: String, _ zip: String) -> Data {
    guard version.range(of: #"^\d+(\.\d+){0,3}$"#, options: .regularExpression) != nil else { fail("\(version) is not a version like 1.12.1") }
    return Data("docked-update-v1|\(version)|".utf8) + Data(SHA256.hash(data: bytes(zip)))
}
if a.first == "--check-update" {
    guard a.count == 4, let k = env["DOCKED_PUBLIC_KEY"].flatMap({ Data(base64Encoded: $0) }), let p = try? Curve25519.Signing.PublicKey(rawRepresentation: k),
          let s = Data(base64Encoded: String(decoding: bytes(a[3]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else { fail("usage: --check-update <version> <zip> <signature file>, with DOCKED_PUBLIC_KEY") }
    if !p.isValidSignature(s, for: updateSaid(a[1], a[2])) { fail("the update signature does not check out: Docked \(a[1]) would refuse this zip") }
    exit(0)
}
if a.first == "--check" {
    guard a.count == 4, let k = env["DOCKED_PUBLIC_KEY"].flatMap({ Data(base64Encoded: $0) }), let p = try? Curve25519.Signing.PublicKey(rawRepresentation: k),
          let s = Data(base64Encoded: String(decoding: bytes(a[3]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else { fail("usage: --check <prefix> <file> <signature file>, with DOCKED_PUBLIC_KEY") }
    if !p.isValidSignature(s, for: Data(a[1].utf8) + bytes(a[2])) { fail("the signature does not check out") }
    exit(0)
}
guard let k = env["DOCKED_SIGNING_KEY"].flatMap({ Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: k) else { fail("DOCKED_SIGNING_KEY is not set, or is not a key") }
if a == ["--public"] { print(key.publicKey.rawRepresentation.base64EncodedString()); exit(0) }
if a.first == "--update" { guard a.count == 3 else { fail("usage: --update <version> <Docked-Update.zip>") }; print(try! key.signature(for: updateSaid(a[1], a[2])).base64EncodedString()); exit(0) }
guard a.count == 2 else { fail("usage: sign.swift <prefix> <file> | --update <version> <zip> | --public") }
if a[0].hasPrefix("docked-update") || a[1].hasSuffix("Docked-Update.zip") { fail("an app update is signed with --update <version> <zip>, which signs the zip's SHA-256 as the app expects") }
print(try! key.signature(for: Data(a[0].utf8) + bytes(a[1])).base64EncodedString())
