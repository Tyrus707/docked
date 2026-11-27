import Foundation

// A preview is drawn from the course's own bytes, never from a guess. Super
// Mario Maker 2 stores its ground tiles, objects and start/goal in a fixed
// layout inside the decrypted course; this reads only those small fields.
// Published format: nintendo-formats.com/games/smm2/level.html and
// liamadvance/smm2-documentation (Course Format).
struct SMM2CourseMap: Equatable {
    struct Tile: Equatable { let x: Int, y: Int, kind: UInt8 }
    struct Object: Equatable { let x: Int, y: Int, width: Int, height: Int, kind: UInt16 }
    struct Bounds: Equatable { let left: Int, right: Int, top: Int, bottom: Int }

    let startX: Int, startY: Int, goalX: Int, goalY: Int
    let theme: Int
    let bounds: Bounds
    let tiles: [Tile]
    let objects: [Object]

    var isUsable: Bool { !tiles.isEmpty || !objects.isEmpty }
    var start: (x: Int, y: Int) { (startX, startY) }
    var goal: (x: Int, y: Int) { (goalX, goalY) }

    static func parse(_ d: Data) -> SMM2CourseMap {
        let area = 0x200
        let startY = Int(byte(d, 0) ?? 0)
        let goalY = Int(byte(d, 1) ?? 0)
        let goalX = Int(u16(d, 2) ?? 0)
        let theme = Int(byte(d, area) ?? 0)
        let bounds = Bounds(left: Int(u32(d, area + 0x10) ?? 0), right: Int(u32(d, area + 0x08) ?? 0),
                            top: Int(u32(d, area + 0x0C) ?? 0), bottom: Int(u32(d, area + 0x14) ?? 0))
        var tiles: [Tile] = []
        let ground = area + 0x247A4
        let groundCount = min(Int(u32(d, area + 0x3C) ?? 0), 4000)   // the file itself holds exactly 4000
        for i in 0..<groundCount {
            let at = ground + i * 4
            guard at + 2 < d.count else { break }
            tiles.append(Tile(x: Int(d[at]), y: Int(d[at + 1]), kind: d[at + 2]))
        }
        var objects: [Object] = []
        let obj = area + 0x48
        let objectCount = min(Int(u32(d, area + 0x1C) ?? 0), 2600)   // the file itself holds exactly 2600
        for i in 0..<objectCount {
            let at = obj + i * 0x20
            guard at + 0x19 < d.count, let x = u32(d, at), let y = u32(d, at + 4), let kind = u16(d, at + 0x18) else { break }
            objects.append(Object(x: Int(x), y: Int(y), width: Int(d[at + 0x0A]), height: Int(d[at + 0x0B]), kind: kind))
        }
        return SMM2CourseMap(startX: 0, startY: startY, goalX: goalX, goalY: goalY,
                             theme: theme, bounds: bounds, tiles: tiles, objects: objects)
    }

    private static func byte(_ d: Data, _ at: Int) -> UInt8? { at >= 0 && at < d.count ? d[at] : nil }
    private static func u16(_ d: Data, _ at: Int) -> UInt16? {
        guard let a = byte(d, at), let b = byte(d, at + 1) else { return nil }
        return UInt16(a) | UInt16(b) << 8
    }
    private static func u32(_ d: Data, _ at: Int) -> UInt32? {
        guard let a = u16(d, at), let b = u16(d, at + 2) else { return nil }
        return UInt32(a) | UInt32(b) << 16
    }
}

enum SMM2CoursePreview {
    // Archive rows hold a compressed, decrypted course. The live server sends
    // the finished .bcd instead. Both become the same plain bytes for drawing.
    static func plainData(for course: SMM2Course) throws -> Data {
        guard let data = course.levelData, !data.isEmpty else { throw SMM2Error.missingData }
        return course.isBcdFile ? try SMM2Crypto.decrypt(data) : try SMM2Gzip.decompress(data)
    }

    static func map(for course: SMM2Course) -> SMM2CourseMap? {
        guard let plain = try? plainData(for: course) else { return nil }
        return SMM2CourseMap.parse(plain)
    }

    // A thumbnail is shown only if the source really sent a JPEG or PNG.
    static func isRealImage(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8, 0xFF]) || data.starts(with: [0x89, 0x50, 0x4E, 0x47])
    }
}

// What the player picked while the game was open. Nothing is written until the
// game has closed; the slot and the game are checked again at that moment.
struct SMM2Queue: Equatable {
    let course: SMM2Course
    let slot: Int
    let titleID: String
    let at: Date

    init(course: SMM2Course, slot: Int, titleID: String, at: Date = Date()) {
        self.course = course; self.slot = slot; self.titleID = titleID; self.at = at
    }

    var isValid: Bool { SMM2Slots.downloaded.contains(slot) }
    func matches(_ id: String) -> Bool { titleID.uppercased() == id.uppercased() }

    // Checked again at the moment the game closes; a slot can disappear and the
    // game can be reopened while the player is deciding.
    func canApply(gameRunning: Bool, gameOpen: Bool, populatedSlots: Set<Int>) -> Bool {
        isValid && !gameRunning && !gameOpen && populatedSlots.contains(slot)
    }
}

// Keep the panel over the game window, without spilling off the screen.
enum SMM2OverlayLayout {
    static func frame(game: CGRect, panel: CGSize, screen: CGRect) -> CGRect {
        let maxW = max(320, min(game.width - 48, screen.width - 16))
        let maxH = max(240, min(game.height - 48, screen.height - 16))
        let width = min(panel.width, maxW), height = min(panel.height, maxH)
        let x = min(max(game.midX - width / 2, screen.minX + 8), max(screen.minX + 8, screen.maxX - width - 8))
        let y = min(max(game.midY - height / 2, screen.minY + 8), max(screen.minY + 8, screen.maxY - height - 8))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
