// Signs with Docked's private key, which never goes in the repository. The key is read from DOCKED_SIGNING_KEY: the 32 raw bytes, in base64.
//   swift Bundle/sign.swift --public               prints the public key, to compare with Update.publicKey
//   swift Bundle/sign.swift <prefix> <file>         prints the signature of prefix + the file's bytes, in base64
//   swift Bundle/sign.swift --check <prefix> <file> <signature file>   checks one with the public key in Sources/Update.swift's place (DOCKED_PUBLIC_KEY)
import CryptoKit
import Foundation

let a = Array(CommandLine.arguments.dropFirst()), env = ProcessInfo.processInfo.environment
func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }
func bytes(_ p: String) -> Data { guard let d = FileManager.default.contents(atPath: p) else { fail("cannot read \(p)") }; return d }
if a.first == "--check" {
    guard a.count == 4, let k = env["DOCKED_PUBLIC_KEY"].flatMap({ Data(base64Encoded: $0) }), let p = try? Curve25519.Signing.PublicKey(rawRepresentation: k),
          let s = Data(base64Encoded: String(decoding: bytes(a[3]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else { fail("usage: --check <prefix> <file> <signature file>, with DOCKED_PUBLIC_KEY") }
    if !p.isValidSignature(s, for: Data(a[1].utf8) + bytes(a[2])) { fail("the signature does not check out") }
    exit(0)
}
guard let k = env["DOCKED_SIGNING_KEY"].flatMap({ Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: k) else { fail("DOCKED_SIGNING_KEY is not set, or is not a key") }
if a == ["--public"] { print(key.publicKey.rawRepresentation.base64EncodedString()); exit(0) }
guard a.count == 2 else { fail("usage: sign.swift <prefix> <file> | --public") }
print(try! key.signature(for: Data(a[0].utf8) + bytes(a[1])).base64EncodedString())
