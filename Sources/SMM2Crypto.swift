import Foundation
import CommonCrypto
import Security
import zlib

// Super Mario Maker 2's course files (course_data_XXX.bcd). Based on the
// published SMM2 format and MariOver's MIT-licensed reference implementation.
// Nothing here contacts Nintendo; it only turns course bytes into the file the
// converted game reads from its save.

enum SMM2Crypto {
    static let decryptedSize = 0x5BFC0          // 376,768
    static let headerSize = 0x10
    static let footerSize = 0x30
    static let fileSize = headerSize + decryptedSize + footerSize  // 376,832

    // Archive data is decrypted and zlib-compressed. Live level data is already
    // a .bcd file. This makes the archive form into the file Coursebot expects.
    static func encrypt(_ decrypted: Data) throws -> Data {
        guard decrypted.count == decryptedSize else { throw SMM2Error.custom("A course is \(decryptedSize) bytes, but this one is \(decrypted.count).") }
        let seed = randomBytes(16)
        let iv = randomBytes(16)
        var rng = SeadRandom(seed: seed)
        let aesKey = createKey(&rng)
        let cmacKey = createKey(&rng)

        let body = try crypt(CCOperation(kCCEncrypt), key: aesKey, iv: iv, input: decrypted)
        let checksum = decrypted.withUnsafeBytes { UInt32(truncatingIfNeeded: zlib.crc32(0, $0.baseAddress, UInt32(decrypted.count))) }

        var file = Data(count: fileSize)
        file[0] = 1                              // format version
        file[4] = 0x10                           // header size
        file[6] = 1
        for i in 0..<4 { file[8 + i] = UInt8(truncatingIfNeeded: checksum >> UInt32(8 * i)) }
        "SCDL".utf8.enumerated().forEach { file[12 + $0.offset] = $0.element }
        let bodyStart = headerSize
        let footerStart = bodyStart + decryptedSize
        file.replaceSubrange(bodyStart..<footerStart, with: body)
        file.replaceSubrange(footerStart..<(footerStart + 16), with: iv)
        file.replaceSubrange((footerStart + 16)..<(footerStart + 32), with: seed)
        file.replaceSubrange((footerStart + 32)..<(footerStart + 48), with: try cmac(cmacKey, decrypted))
        return file
    }

    // Used by tests and by the optional check before writing a live file.
    static func decrypt(_ file: Data) throws -> Data {
        guard file.count == fileSize else { throw SMM2Error.badCourseFile }
        let footer = headerSize + decryptedSize
        let iv = file.subdata(in: footer..<(footer + 16))
        var rng = SeadRandom(seed: file.subdata(in: (footer + 16)..<(footer + 32)))
        let aesKey = createKey(&rng)
        let cmacKey = createKey(&rng)
        let body = file.subdata(in: headerSize..<footer)
        let plain = try crypt(CCOperation(kCCDecrypt), key: aesKey, iv: iv, input: body)
        let expected = try cmac(cmacKey, plain)
        guard expected == file.subdata(in: (footer + 32)..<(footer + 48)) else { throw SMM2Error.badCourseFile }
        return plain
    }

    static func looksLikeCourseFile(_ data: Data) -> Bool {
        guard data.count == fileSize, data.count > 16 else { return false }
        return String(data: data.subdata(in: 12..<16), encoding: .ascii) == "SCDL"
    }

    // MARK: - AES

    // CBC with no padding: a course body is always a whole number of blocks.
    private static func crypt(_ op: CCOperation, key: Data, iv: Data, input: Data, ecb: Bool = false) throws -> Data {
        guard key.count == 16, iv.count == 16 else { throw SMM2Error.custom("Bad course key.") }
        let keyBytes = [UInt8](key), ivBytes = [UInt8](iv), inBytes = [UInt8](input)
        var out = [UInt8](repeating: 0, count: inBytes.count)
        let outCount = out.count
        let options: CCOptions = ecb ? CCOptions(kCCOptionECBMode) : 0
        let status: CCCryptorStatus = keyBytes.withUnsafeBytes { k in
            ivBytes.withUnsafeBytes { i in
                inBytes.withUnsafeBytes { src in
                    out.withUnsafeMutableBytes { dst in
                        CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), options, k.baseAddress, 16, i.baseAddress, src.baseAddress, inBytes.count, dst.baseAddress, outCount, nil)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw SMM2Error.custom("Docked couldn't encode this course (\(status)).") }
        return Data(out)
    }

    // AES-CMAC for a whole-block message, the form a course always has.
    private static func cmac(_ key: Data, _ data: Data) throws -> Data {
        guard !data.isEmpty, data.count % 16 == 0 else { throw SMM2Error.custom("A course must be made of whole blocks.") }
        let zero = Data(repeating: 0, count: 16)
        let k1 = shiftLeftXor([UInt8](try crypt(CCOperation(kCCEncrypt), key: key, iv: zero, input: zero, ecb: true)))
        var message = [UInt8](data)
        for i in 0..<16 { message[message.count - 16 + i] ^= k1[i] }
        let encrypted = try crypt(CCOperation(kCCEncrypt), key: key, iv: zero, input: Data(message))
        return encrypted.subdata(in: (encrypted.count - 16)..<encrypted.count)
    }

    private static func shiftLeftXor(_ block: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 16), carry: UInt8 = 0
        for i in stride(from: 15, through: 0, by: -1) {
            let b = block[i]
            out[i] = (b << 1) | carry
            carry = b >> 7
        }
        if block[0] & 0x80 != 0 { out[15] ^= 0x87 }
        return out
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    // MARK: - sead::Random key derivation

    private static let keyTable: [UInt32] = [
        0x7AB1C9D2, 0xCA750936, 0x3003E59C, 0xF261014B, 0x2E25160A, 0xED614811, 0xF1AC6240,
        0xD59272CD, 0xF38549BF, 0x6CF5B327, 0xDA4DB82A, 0x820C435A, 0xC95609BA, 0x19BE08B0,
        0x738E2B81, 0xED3C349A, 0x045275D1, 0xE0A73635, 0x1DEBF4DA, 0x9924B0DE, 0x6A1FC367,
        0x71970467, 0xFC55ABEB, 0x368D7489, 0x0CC97D1D, 0x17CC441E, 0x3528D152, 0xD0129B53,
        0xE12A69E9, 0x13D1BDB7, 0x32EAA9ED, 0x42F41D1B, 0xAEA5F51F, 0x42C5D23C, 0x7CC742ED,
        0x723BA5F9, 0xDE5B99E3, 0x2C0055A4, 0xC38807B4, 0x4C099B61, 0xC4E4568E, 0x8C29C901,
        0xE13B34AC, 0xE7C3F212, 0xB67EF941, 0x08038965, 0x8AFD1E6A, 0x8E5341A3, 0xA4C61107,
        0xFBAF1418, 0x9B05EF64, 0x3C91734E, 0x82EC6646, 0xFB19F33E, 0x3BDE6FE2, 0x17A84CCA,
        0xCCDF0CE9, 0x50E4135C, 0xFF2658B2, 0x3780F156, 0x7D8F5D68, 0x517CBED1, 0x1FCDDF0D,
        0x77A58C94,
    ]

    private static func createKey(_ rng: inout SeadRandom) -> Data {
        var key = [UInt8](repeating: 0, count: 16)
        for word in 0..<4 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                let index = Int(rng.next() >> 26)
                let shift = Int((rng.next() >> 27) & 0x18)
                let byte = UInt32(truncatingIfNeeded: (keyTable[index] >> UInt32(shift)) & 0xFF)
                value = (value << 8) | byte
            }
            for byte in 0..<4 { key[word * 4 + byte] = UInt8(truncatingIfNeeded: value >> UInt32(8 * byte)) }
        }
        return Data(key)
    }

    private struct SeadRandom {
        private var s: [UInt32]

        init(seed: Data) {
            s = (0..<4).map { i in
                let p = i * 4
                return UInt32(seed[p]) | (UInt32(seed[p + 1]) << 8) | (UInt32(seed[p + 2]) << 16) | (UInt32(seed[p + 3]) << 24)
            }
            if s.allSatisfy({ $0 == 0 }) { s = [1, 0x6C078967, 0x714ACB41, 0x48077044] }
        }

        mutating func next() -> UInt32 {
            var t = s[0] ^ (s[0] << 11)
            t = t ^ (t >> 8) ^ s[3] ^ (s[3] >> 19)
            s[0] = s[1]; s[1] = s[2]; s[2] = s[3]; s[3] = t
            return t
        }
    }
}
