import Foundation
import zlib

// Public Super Mario Maker 2 courses, without touching Nintendo's servers.
// The archive is TheGreatRambler's mirror of uploaded courses; tgrcode is only a
// convenience when it happens to be up. Docked never signs in or sends a save.

let smm2TitleID = "01009B90006DC000"

private let courseChars = Array("0123456789BCDFGHJKLMNPQRSTVWXY")
private let courseXOR: UInt64 = 0b00010110100000001110000001111100

enum SMM2Error: LocalizedError, Equatable {
    case badCourseID
    case badDataID
    case badCourseFile
    case offline
    case missingData
    case noSave
    case gameOpen
    case slotTaken(Int)
    case badArchive
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .badCourseID: return "That isn't a Super Mario Maker 2 course ID. Use nine characters like 2J5-3K2-Y9G."
        case .badDataID: return "That course isn't in the archive."
        case .badCourseFile: return "That isn't a complete Super Mario Maker 2 course file."
        case .offline: return "The course archive couldn't be reached. Check your connection and try again."
        case .missingData: return "The archive has the course's details, but not its level data."
        case .noSave: return "Super Mario Maker 2 has no save yet. Start the game once, save, quit, then try again."
        case .gameOpen: return "Save and quit Super Mario Maker 2 first. Docked won't change a save while the game is open."
        case let .slotTaken(n): return "Coursebot slot \(n) already has a course. Choose another slot."
        case .badArchive: return "The course archive answered in a way Docked doesn't understand."
        case let .custom(s): return s
        }
    }
}

// MARK: - Course IDs

// A course ID is a nine-character base-30 number with one XOR fold. The public
// archive is keyed by the data ID that falls out of it.
enum SMM2CourseID {
    static func isValid(_ id: String) -> Bool { dataID(id) != nil }

    static func tidy(_ id: String) -> String {
        let chars = Array(id.uppercased().filter { $0 != "-" && !$0.isWhitespace })
        guard chars.count == 9 else { return id.uppercased() }
        return String(chars[0...2]) + "-" + String(chars[3...5]) + "-" + String(chars[6...8])
    }

    static func dataID(_ id: String) -> UInt32? {
        let chars = Array(id.uppercased().filter { $0 != "-" && !$0.isWhitespace })
        guard chars.count == 9 else { return nil }
        var number: UInt64 = 0
        for ch in chars.reversed() {
            guard let digit = courseChars.firstIndex(of: ch) else { return nil }
            number = number * 30 + UInt64(digit)
        }
        let folded = ((number & 0xFFF) << 20 | ((number >> 14) & 0xFFFFF)) ^ courseXOR
        guard number >> 40 == 8,                       // course, not a maker or a different code
              (number >> 12) & 1 == 1,                 // published level
              (number >> 13) & 1 == 0,                 // not a maker ID
              (number >> 34) & 0x3F == (folded &- 31) % 64 else { return nil }
        return folded <= UInt64(UInt32.max) ? UInt32(folded) : nil
    }

    static func courseID(_ dataID: UInt32) -> String {
        let exed = UInt64(dataID) ^ courseXOR
        let checksum = (UInt64(dataID) &- 31) % 64
        let number = (UInt64(8) << 40) + (checksum << 34) + ((exed & 0xFFFFF) << 14) + (UInt64(1) << 12) + (exed >> 20)
        var n = number, body = ""
        while n > 0 {
            body.append(courseChars[Int(n % 30)])   // least significant digit is written first
            n /= 30
        }
        while body.count < 9 { body.append("0") }
        return tidy(body)
    }
}

// MARK: - A course in the browser

struct SMM2Course: Identifiable, Equatable {
    let dataID: UInt32
    var courseID: String { SMM2CourseID.courseID(dataID) }
    var name: String
    var author: String
    var description: String
    var style: String
    var theme: String
    var difficulty: String
    var likes: Int?
    var plays: Int?
    // Archive level data is a compressed course. A live server can return the
    // finished .bcd instead; `isBcdFile` tells the injector which one it has.
    var levelData: Data?
    var isBcdFile = false

    var id: UInt32 { dataID }

    init(dataID: UInt32, name: String = "", levelData: Data? = nil, isBcdFile: Bool = false) {
        self.dataID = dataID
        self.name = name
        author = ""
        description = ""
        style = ""
        theme = ""
        difficulty = ""
        likes = nil
        plays = nil
        self.levelData = levelData
        self.isBcdFile = isBcdFile
    }

    // Archive rows vary a little by endpoint. Read the fields we understand and
    // leave the rest blank rather than throw away an otherwise useful course.
    init?(row: [String: Any]) {
        guard let id = Self.dataID(from: row["data_id"]), id != 0 else { return nil }
        dataID = id
        name = Self.string(row["name"])
        // The archive's `uploaded` field is a timestamp, not a maker name.
        author = Self.string(row["uploaded_name"]).nonempty ?? Self.string(row["uploader_name"]).nonempty ?? Self.string(row["author"]).nonempty ?? Self.string(row["creator"]).nonempty ?? Self.string(row["uploader_pid"]).nonempty ?? ""
        description = Self.string(row["description"])
        style = Self.string(row["gamestyle_name"]).nonempty ?? Self.name(for: row["gamestyle"], table: Self.styles)
        theme = Self.string(row["theme_name"]).nonempty ?? Self.name(for: row["theme"], table: Self.themes)
        difficulty = Self.string(row["difficulty_name"]).nonempty ?? Self.name(for: row["difficulty"], table: Self.difficulties)
        likes = Self.number(row["likes"]) ?? Self.number(row["num_likes"])
        plays = Self.number(row["plays"]) ?? Self.number(row["num_plays"])
        levelData = Self.levelData(from: row["level_data"])
        isBcdFile = false
    }

    private static func dataID(from v: Any?) -> UInt32? {
        if let n = number(v), n > 0, n <= Int(UInt32.max) { return UInt32(n) }
        if let s = string(v).nonempty, let n = UInt32(s), n > 0 { return n }
        if let s = string(v).nonempty { return SMM2CourseID.dataID(s) }
        return nil
    }

    private static func levelData(from v: Any?) -> Data? {
        if let s = v as? String { return Data(base64Encoded: s) }
        if let bytes = v as? [Int] { return Data(bytes.map(UInt8.init(truncatingIfNeeded:))) }
        if let bytes = v as? [UInt8] { return Data(bytes) }
        return nil
    }

    private static func string(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    private static func number(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func name(for v: Any?, table: [String]) -> String {
        guard let i = number(v), i >= 0, i < table.count else { return "" }
        return table[i]
    }

    static let styles = ["Super Mario Bros.", "Super Mario Bros. 3", "Super Mario World", "New Super Mario Bros. U", "Super Mario 3D World"]
    static let themes = ["Overworld", "Underground", "Castle", "Airship", "Underwater", "Ghost house", "Snow", "Desert", "Sky", "Forest"]
    static let difficulties = ["Easy", "Normal", "Expert", "Super expert"]
    static let tags = ["None", "Standard", "Puzzle solving", "Speedrun", "Autoscroll", "Auto Mario", "Short and sweet", "Multiplayer versus", "Themed", "Music", "Art", "Technical", "Shooter", "Boss battle", "Single player", "Link"]
}

private extension String {
    var nonempty: String? { isEmpty ? nil : self }
}

// MARK: - The public archive

struct SMM2Search {
    var courses: [SMM2Course]
    var partial: Bool
    var total: Int?
}

enum SMM2Archive {
    static let base = "https://datasets-server.huggingface.co"
    static let liveBase = "https://tgrcode.com/mm2"

    static func search(_ text: String) throws -> SMM2Search {
        try fetch(path: "/search", extra: [URLQueryItem(name: "query", value: text), URLQueryItem(name: "length", value: "12")])
    }

    static func course(dataID id: UInt32) throws -> SMM2Search {
        try fetch(path: "/filter", extra: [URLQueryItem(name: "where", value: "\"data_id\"=\(id)"), URLQueryItem(name: "length", value: "1")])
    }

    // One course by its printed ID. The live server is a fallback only; if it
    // is down, the archive is still the source of truth.
    static func course(code: String, tryLive: Bool) throws -> SMM2Course? {
        let code = SMM2CourseID.tidy(code)
        guard let id = SMM2CourseID.dataID(code) else { throw SMM2Error.badCourseID }
        let found = try course(dataID: id)
        if let course = found.courses.first { return course }
        if tryLive, let bcd = try liveData(code) {
            return SMM2Course(dataID: id, name: code, levelData: bcd, isBcdFile: true)
        }
        if found.partial { throw SMM2Error.custom("The archive couldn't finish checking \(code). Try again, or switch on the live course server.") }
        return nil
    }

    static func liveData(_ code: String) throws -> Data? {
        let compact = code.filter { $0 != "-" && !$0.isWhitespace }
        guard let url = URL(string: "\(liveBase)/level_data/\(compact)") else { throw SMM2Error.badCourseID }
        guard let data = try get(url) else { return nil }
        guard SMM2Crypto.looksLikeCourseFile(data) else { throw SMM2Error.custom("The live course server didn't return a course file. It may be down.") }
        return data
    }

    // The archive has no pictures (the thumbnails were dropped because of their
    // size). The public image server has them when it is up; a failure here is
    // never an error for the player — the drawn course map takes its place.
    static func thumbnail(dataID id: UInt32) -> Data? {
        let code = SMM2CourseID.courseID(id).filter { $0 != "-" }
        guard let url = URL(string: "\(liveBase)/level_thumbnail/\(code)"),
              let data = try? get(url), SMM2CoursePreview.isRealImage(data) else { return nil }
        return data
    }

    private static func fetch(path: String, extra: [URLQueryItem]) throws -> SMM2Search {
        guard var parts = URLComponents(string: base + path) else { throw SMM2Error.badArchive }
        parts.queryItems = [
            URLQueryItem(name: "dataset", value: "TheGreatRambler/mm2_level"),
            URLQueryItem(name: "config", value: "default"),
            URLQueryItem(name: "split", value: "train"),
            URLQueryItem(name: "offset", value: "0")
        ] + extra
        guard let url = parts.url, let data = try get(url) else { throw SMM2Error.badArchive }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> SMM2Search {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw SMM2Error.badArchive }
        let rows = (json["rows"] as? [[String: Any]]) ?? []
        let courses = rows.compactMap { $0["row"] as? [String: Any] }.compactMap(SMM2Course.init(row:))
        // A partial answer means "we can't say there are none"; an empty page
        // from one is not proof the course is missing.
        let partial = (json["partial"] as? Bool) ?? false
        let total = (json["num_rows_total"] as? NSNumber)?.intValue
        return SMM2Search(courses: courses, partial: partial, total: total)
    }

    private static func get(_ url: URL) throws -> Data? {
        do { return try Lookup.get(url, limit: 20_000_000) }
        catch { throw SMM2Error.offline }
    }
}

// MARK: - Course compression

// The archive stores the decrypted course compressed. Hugging Face sends zlib
// (78 9c); gzip and bare deflate are accepted as well.
enum SMM2Gzip {
    static func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw SMM2Error.missingData }
        for window in [Int32(15), Int32(15 + 16), Int32(-15)] {
            if let out = try? inflate(data, windowBits: window), !out.isEmpty { return out }
        }
        throw SMM2Error.custom("This course is damaged and can't be opened.")
    }

    private static func inflate(_ data: Data, windowBits: Int32) throws -> Data {
        var stream = z_stream()
        let started = inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard started == Z_OK else { throw SMM2Error.custom("Docked couldn't read this course's compression.") }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw SMM2Error.missingData }
            stream.next_in = UnsafeMutablePointer(mutating: base.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(data.count)
            var out = Data()
            let chunk = 64 * 1024
            while true {
                let before = out.count
                out.count = before + chunk
                let status: Int32 = out.withUnsafeMutableBytes { buf in
                    stream.next_out = buf.baseAddress!.assumingMemoryBound(to: Bytef.self).advanced(by: before)
                    stream.avail_out = uInt(chunk)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                out.count = before + Int(chunk - Int(stream.avail_out))
                if status == Z_STREAM_END { return out }
                if status == Z_OK || status == Z_BUF_ERROR {
                    if stream.avail_in == 0 && stream.avail_out > 0 { break }
                    continue
                }
                break
            }
            throw SMM2Error.custom("This course is damaged and can't be opened.")
        }
    }
}

// MARK: - Coursebot slots

// 0..119 are My Courses, 120..179 are Downloaded Courses. New courses go in
// the downloaded half, where the game already knows how to show them.
enum SMM2Slots {
    static let downloaded = 120..<180
    static let mine = 0..<120

    static func name(_ slot: Int) -> String { String(format: "%03d", slot) }

    static func dataFile(_ slot: Int, in save: URL) -> URL {
        save.appendingPathComponent("course_data_\(name(slot)).bcd")
    }
    static func replayFile(_ slot: Int, in save: URL) -> URL {
        save.appendingPathComponent("course_replay_\(name(slot)).dat")
    }
    static func thumbFile(_ slot: Int, in save: URL) -> URL {
        save.appendingPathComponent("course_thumb_\(name(slot)).btl")
    }

    // Slots with a BCD already in them are the ones the game will show. Empty
    // slots are avoided: the game can ignore a course file written into one.
    static func populated(in save: URL, range: Range<Int> = downloaded) -> Set<Int> {
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: save.path)) ?? [])
        return Set(range.filter { names.contains("course_data_\(name($0)).bcd") })
    }

}

// MARK: - Writing a course into a save

enum SMM2Injector {
    // Turns either archive form into the exact file Coursebot reads.
    static func prepare(_ course: SMM2Course) throws -> Data {
        guard let data = course.levelData, !data.isEmpty else { throw SMM2Error.missingData }
        if course.isBcdFile {
            guard SMM2Crypto.looksLikeCourseFile(data) else { throw SMM2Error.badCourseFile }
            return data
        }
        let plain = try SMM2Gzip.decompress(data)
        guard plain.count == SMM2Crypto.decryptedSize else {
            throw SMM2Error.custom("This course is \(plain.count) bytes, but Super Mario Maker 2 needs \(SMM2Crypto.decryptedSize).")
        }
        return try SMM2Crypto.encrypt(plain)
    }

    // Only the one course file changes. The player's other progress, the rest
    // of the save and all the replay/thumbnail files are left as they are.
    static func write(_ file: Data, to save: URL, slot: Int) throws {
        guard SMM2Slots.downloaded.contains(slot) else { throw SMM2Error.custom("Choose a Downloaded Course slot.") }
        guard SMM2Crypto.looksLikeCourseFile(file) else { throw SMM2Error.badCourseFile }
        let fm = FileManager.default
        let destination = SMM2Slots.dataFile(slot, in: save)
        guard fm.fileExists(atPath: destination.path) else { throw SMM2Error.custom("Choose a Coursebot slot that already has a course in it. Empty slots may be ignored by the game.") }
        let temp = save.appendingPathComponent("course_data_\(SMM2Slots.name(slot)).bcd.\(UUID().uuidString).tmp")
        do {
            try file.write(to: temp, options: .atomic)
            _ = try fm.replaceItemAt(destination, withItemAt: temp, backupItemName: nil, options: .usingNewMetadataOnly)
            if fm.fileExists(atPath: temp.path) { try? fm.removeItem(at: temp) }
        } catch {
            try? fm.removeItem(at: temp)
            throw SMM2Error.custom("Docked couldn't put that course in Coursebot. Your save was left as it was. \(error.localizedDescription)")
        }
    }
}
