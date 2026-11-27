import AppKit
import CoreGraphics
import SwiftUI

// Public courses, in plain language. The panel floats over the game window. No
// account, no Nintendo servers, no upload, and no write while the game is open:
// a course chosen during play waits until the game has closed.
struct CourseBrowserView: View {
    @EnvironmentObject var model: Model
    let game: Game
    let close: () -> Void

    @State private var mode = 0
    @State private var query = ""
    @State private var code = ""
    @State private var courses: [SMM2Course] = []
    @State private var selected: SMM2Course?
    @State private var slots: [Int] = []
    @State private var slot: Int?
    @State private var tryLive = true
    @State private var busy = false
    @State private var note = ""
    @State private var confirming = false
    @State private var preview: CoursePreview?

    private var save: GameData { GameData(game.titleID) }
    private var gamePlaying: Bool { model.isRunning(game) || model.isOpen(game) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Course Browser").font(.title2.weight(.semibold))
                    Text("Find a public Super Mario Maker 2 course and put it into a Coursebot slot on this Mac. Docked never signs in or sends your save.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { close() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Close Course Browser")
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(style.warn).accessibilityHidden(true)
                Text("This changes only the course itself. The thumbnail, title, maker and play stats shown in Coursebot stay as they were in that slot.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Picker("Find by", selection: $mode) {
                Text("Archive search").tag(0)
                Text("Course ID").tag(1)
            }.pickerStyle(.segmented).disabled(busy)

            if mode == 0 {
                HStack(spacing: 8) {
                    TextField("Course name, style or theme", text: $query).textFieldStyle(.roundedBorder).onSubmit { search() }
                    Button("Search") { search() }.disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                HStack(spacing: 8) {
                    TextField("XXX-XXX-XXX or data ID", text: $code).textFieldStyle(.roundedBorder).onSubmit { lookUp() }
                    Button("Look Up") { lookUp() }.disabled(busy || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Toggle("Try the live course server if the archive has no level data (it may be down)", isOn: $tryLive).font(.caption).disabled(busy)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Courses").font(.callout.weight(.semibold))
                    if busy {
                        HStack { ProgressView(); Text("Looking for courses…").font(.callout).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if courses.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                            Text(note.isEmpty ? "Search the archive, or enter a course ID." : note).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 5) {
                                ForEach(courses) { course in
                                    Button { selected = course } label: {
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: selected?.dataID == course.dataID ? "checkmark.circle.fill" : "circle").foregroundStyle(selected?.dataID == course.dataID ? style.accent : Color.secondary).accessibilityHidden(true)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(course.name.isEmpty ? "Untitled course" : course.name).font(.callout.weight(.medium)).foregroundStyle(style.text).lineLimit(1)
                                                Text("\(course.courseID) · \(course.author.isEmpty ? "Unknown maker" : course.author)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                                Text(details(course)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.vertical, 5).padding(.horizontal, 7)
                                        .background(selected?.dataID == course.dataID ? style.tile.opacity(0.9) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview").font(.callout.weight(.semibold))
                    ZStack {
                        if let image = preview?.image {
                            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 10))
                        } else if let map = preview?.map, map.isUsable {
                            SMM2CourseMapView(map: map).clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "photo").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                                Text(preview?.detail ?? "Choose a course to see its real preview.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: 330, height: 210)
                    .background(style.bottom.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(preview?.detail ?? "No course chosen.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(width: 330, alignment: .leading)
                }
            }.frame(height: 254)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Coursebot destination").font(.callout.weight(.semibold))
                if slots.isEmpty {
                    Label("No downloaded course slot is ready. Put a course in a Downloaded Course slot, save and quit, then come back.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Menu(slot.map { "Downloaded course \(SMM2Slots.name($0))" } ?? "Choose a slot") {
                        ForEach(slots, id: \.self) { n in Button("Downloaded course \(SMM2Slots.name(n))") { slot = n } }
                    }.disabled(busy)
                    Text("Docked replaces only that course. Empty slots aren't used because the game may ignore them.").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let queued = model.smm2Queue {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock.badge.checkmark").foregroundStyle(style.warn).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Queued: \(queued.course.name.isEmpty ? queued.course.courseID : queued.course.name) → Downloaded Course \(SMM2Slots.name(queued.slot))").font(.caption.weight(.medium))
                        Text("Save and quit \(game.name). Docked checks again that the game is closed before writing.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Cancel") { model.cancelSMM2Queue(); note = model.smm2QueueNote }.font(.caption).disabled(busy)
                }
            }

            if !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Show Saves in Finder") { model.reveal(save.save) }
                Spacer()
                Button("Close") { close() }.keyboardShortcut(.escape).tint(style.button)
                Button(gamePlaying ? "Queue for When the Game Closes…" : "Put in Coursebot…") { confirming = true }
                    .disabled(busy || selected == nil || slot == nil)
                    .tint(style.button)
            }
        }
        .padding(18)
        .frame(width: 860, height: 640)
        .background(AllowQuit())
        .background(Backdrop())
        .onAppear {
            slots = Array(SMM2Slots.populated(in: save.save)).sorted()
            slot = slots.first
            if !model.smm2QueueNote.isEmpty { note = model.smm2QueueNote }
        }
        .onChange(of: selected) { course in loadPreview(course) }
        .onChange(of: model.smm2QueueNote) { text in note = text }
        .confirmationDialog(gamePlaying ? "Queue for Downloaded Course \(slot.map(SMM2Slots.name) ?? "")?" : "Replace Coursebot slot \(slot.map(SMM2Slots.name) ?? "")?", isPresented: $confirming) {
            Button(gamePlaying ? "Queue Course" : "Put Course Here") { if let selected, let slot { put(selected, in: slot) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if gamePlaying {
                Text("Nothing is written while \(game.name) is open. After you save and quit, Docked checks the game is closed, backs up the save, and replaces only that course file. Coursebot will still show the old thumbnail, title, maker and stats.")
            } else {
                Text("The course in this downloaded slot is replaced. Docked makes a dated backup of your save first. Coursebot will still show the old thumbnail, title, maker and stats.")
            }
        }
    }

    private func details(_ c: SMM2Course) -> String {
        var parts = [c.style, c.theme, c.difficulty].filter { !$0.isEmpty }
        if let likes = c.likes { parts.append("\(likes) likes") }
        if let plays = c.plays { parts.append("\(plays) plays") }
        return parts.joined(separator: " · ")
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        busy = true; note = ""; selected = nil; preview = nil
        model.smm2Search(text) { result in
            busy = false
            switch result {
            case .failure(let e): courses = []; note = e.localizedDescription; model.message = e.localizedDescription
            case .success(let found):
                courses = found.courses
                selected = found.courses.first
                note = found.courses.isEmpty ? (found.partial ? "The archive couldn't finish that search. Try a shorter name or a course ID." : "No courses matched. Try a shorter name or a course ID.") : "\(found.courses.count) course\(found.courses.count == 1 ? "" : "s") found."
            }
        }
    }

    private func lookUp() {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        busy = true; note = ""; selected = nil; preview = nil
        model.smm2Course(code: text, tryLive: tryLive) { result in
            busy = false
            switch result {
            case .failure(let e): courses = []; note = e.localizedDescription; model.message = e.localizedDescription
            case .success(let found):
                if let found { courses = [found]; selected = found; note = "Course found." }
                else { courses = []; note = "That course isn't in the archive. Try the live server or another ID." }
            }
        }
    }

    // The public picture server has real thumbnails when it is up. When it is
    // down, the course's own level data is drawn instead; if neither exists, the
    // panel says so rather than showing a made-up picture.
    private func loadPreview(_ course: SMM2Course?) {
        guard let course else { preview = nil; return }
        let id = course.dataID
        preview = CoursePreview(image: nil, map: nil, detail: "Loading preview…")
        DispatchQueue.global(qos: .userInitiated).async {
            var found: CoursePreview
            if let thumbnail = SMM2Archive.thumbnail(dataID: id), let image = NSImage(data: thumbnail) {
                found = CoursePreview(image: image, map: nil, detail: "Real course thumbnail from the public course server.")
            } else {
                var available = course
                if available.levelData == nil, let bcd = try? SMM2Archive.liveData(available.courseID) {
                    available.levelData = bcd; available.isBcdFile = true
                }
                if let map = SMM2CoursePreview.map(for: available), map.isUsable {
                    found = CoursePreview(image: nil, map: map, detail: "Drawn from this course's own level data — not a screenshot.")
                } else {
                    found = CoursePreview(image: nil, map: nil, detail: "No preview available: the archive has no image and this course has no readable level data. Only its details are shown.")
                }
            }
            DispatchQueue.main.async { if selected?.dataID == id { preview = found } }
        }
    }

    private func put(_ course: SMM2Course, in slot: Int) {
        busy = true
        if gamePlaying {
            model.queueSMM2Course(course, in: slot, for: game)
            busy = false
        } else {
            model.smm2Inject(course, into: game, slot: slot, tryLive: tryLive) { result in
                busy = false
                switch result {
                case .failure(let e): note = e.localizedDescription; model.message = e.localizedDescription
                case .success: note = "Done. The course is in Downloaded Course \(SMM2Slots.name(slot))."
                }
            }
        }
    }
}

private struct CoursePreview {
    let image: NSImage?
    let map: SMM2CourseMap?
    let detail: String
}

// A small, honest map of the course: ground tiles, objects, start and goal come
// from the course bytes. It is a diagram of the level, not a game screenshot.
struct SMM2CourseMapView: View {
    let map: SMM2CourseMap

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 10
            let box = CGRect(x: inset, y: inset, width: max(1, size.width - inset * 2), height: max(1, size.height - inset * 2))
            context.fill(Path(roundedRect: box, cornerRadius: 10), with: .color(style.bottom.opacity(0.75)))

            let xs = [map.bounds.left, map.bounds.right, map.start.x, map.goal.x] + map.tiles.map(\.x) + map.objects.map(\.x)
            let ys = [map.bounds.top, map.bounds.bottom, map.start.y, map.goal.y] + map.tiles.map(\.y) + map.objects.map(\.y)
            let minX = xs.min() ?? 0, maxX = max(xs.max() ?? 1, minX + 1)
            let minY = ys.min() ?? 0, maxY = max(ys.max() ?? 1, minY + 1)
            let scale = min(box.width / CGFloat(maxX - minX), box.height / CGFloat(maxY - minY))
            func point(_ x: Int, _ y: Int) -> CGPoint {
                CGPoint(x: box.midX + (CGFloat(x) - CGFloat(minX) - CGFloat(maxX - minX) / 2) * scale,
                        y: box.midY - (CGFloat(y) - CGFloat(minY) - CGFloat(maxY - minY) / 2) * scale)
            }

            let unit = max(2, min(12, scale))
            for tile in map.tiles {
                let p = point(tile.x, tile.y)
                context.fill(Path(CGRect(x: p.x - unit / 2, y: p.y - unit / 2, width: unit, height: unit)), with: .color(groundColor))
            }
            for object in map.objects {
                let p = point(object.x, object.y)
                let w = max(unit, CGFloat(max(1, object.width)) * scale), h = max(unit, CGFloat(max(1, object.height)) * scale)
                let hue = Double(object.kind % 11) / 11
                context.fill(Path(roundedRect: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), cornerRadius: 2),
                             with: .color(Color(hue: hue, saturation: 0.55, brightness: 0.78)))
            }
            let start = point(map.start.x, map.start.y), goal = point(map.goal.x, map.goal.y)
            context.fill(Path(ellipseIn: CGRect(x: start.x - 6, y: start.y - 6, width: 12, height: 12)), with: .color(Color.green))
            context.draw(Text("S").font(.caption2.bold()), at: CGPoint(x: start.x, y: start.y - 1))
            context.fill(Path(ellipseIn: CGRect(x: goal.x - 6, y: goal.y - 6, width: 12, height: 12)), with: .color(Color.red))
            context.draw(Text("G").font(.caption2.bold()), at: CGPoint(x: goal.x, y: goal.y - 1))
        }
        .accessibilityLabel("Course map with \(map.tiles.count) ground tiles and \(map.objects.count) objects")
    }

    private var groundColor: Color {
        switch map.theme {
        case 0, 7: return Color(hex: 0xC49A5B)   // overworld, desert
        case 1, 5: return Color(hex: 0x7C7B9C)   // underground, ghost house
        case 2: return Color(hex: 0x777780)      // castle
        case 3: return Color(hex: 0x9A6560)      // airship
        case 4: return Color(hex: 0x4E94B8)      // underwater
        case 6: return Color(hex: 0xE8F1F7)      // snow
        case 8: return Color(hex: 0x87C3E7)      // sky
        case 9: return Color(hex: 0x62A46E)      // forest
        default: return style.accent
        }
    }
}

// The panel owns no game state. It only hosts the SwiftUI view and sits above
// the game's own window, including when that window is on a full-screen Space.
final class CourseBrowserPanel {
    static let shared = CourseBrowserPanel()
    private var panel: NSPanel?
    private weak var model: Model?

    func show(game: Game, model: Model) {
        close()
        self.model = model
        let size = NSSize(width: 860, height: 640)
        let root = CourseBrowserView(game: game) { self.close() }.environmentObject(model)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = hosting
        p.title = "Course Browser — \(game.name)"
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true
        p.setFrame(Self.frame(game: game, size: size), display: true)
        panel = p
        if NSApp.isHidden { NSApp.unhide(nil) }
        p.orderFrontRegardless()
        p.makeKey()
    }

    func close() {
        panel?.close()
        panel = nil
        model?.courseBrowserGame = nil
    }

    private static func frame(game: Game, size: NSSize) -> NSRect {
        let window = gameWindow(game) ?? NSApp.windows.first { $0.canBecomeMain }?.frame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screen = NSScreen.screens.first { $0.frame.intersects(window) } ?? NSScreen.main
        return SMM2OverlayLayout.frame(game: window, panel: size, screen: screen?.frame ?? window)
    }

    // The converted game is its own Mac app. Core Graphics reports the real
    // window bounds without reaching into the game or changing it.
    private static func gameWindow(_ game: Game) -> NSRect? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.standardizedFileURL == game.url.standardizedFileURL }) else { return nil }
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        for info in list {
            guard let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.intValue, owner == Int(app.processIdentifier),
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else { continue }
            func number(_ key: String) -> CGFloat? { (bounds[key] as? NSNumber).map { CGFloat($0.doubleValue) } }
            guard let x = number("X"), let y = number("Y"), let w = number("Width"), let h = number("Height"), w > 200, h > 200 else { continue }
            let cg = CGRect(x: x, y: y, width: w, height: h)
            let mainHeight = NSScreen.screens.first?.frame.height ?? 0
            let centre = NSPoint(x: cg.midX, y: mainHeight - cg.midY)
            let top = (NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.main)?.frame.maxY ?? mainHeight
            return NSRect(x: cg.minX, y: top - cg.maxY, width: w, height: h)
        }
        return nil
    }
}

extension Model {
    func openCourseBrowser(_ g: Game) {
        guard g.rom == nil, g.titleID.uppercased() == smm2TitleID, !g.missing else {
            message = "Course Browser works with converted Super Mario Maker 2 games only."; return
        }
        guard GameData(g.titleID).hasSave else { message = SMM2Error.noSave.errorDescription ?? ""; return }
        smm2QueueNote = ""
        CourseBrowserPanel.shared.show(game: g, model: self)
        courseBrowserGame = g
    }

    func openCourseBrowserForSMM2() {
        guard let g = games.first(where: { $0.rom == nil && $0.titleID.uppercased() == smm2TitleID && !$0.missing && GameData($0.titleID).hasSave }) else {
            message = "Add a converted Super Mario Maker 2 game with a save first."; return
        }
        openCourseBrowser(g)
    }

    func smm2Search(_ text: String, then: @escaping (Result<SMM2Search, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let answer = Result { () throws -> SMM2Search in
                if text.count <= 10, text.allSatisfy(\.isNumber), let id = UInt32(text), id > 0 {
                    return try SMM2Archive.course(dataID: id)
                }
                return try SMM2Archive.search(text)
            }
            DispatchQueue.main.async { then(answer) }
        }
    }

    func smm2Course(code: String, tryLive: Bool, then: @escaping (Result<SMM2Course?, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let answer = Result { () throws -> SMM2Course? in
                if code.count <= 10, code.allSatisfy(\.isNumber), let id = UInt32(code), id > 0 {
                    let found = try SMM2Archive.course(dataID: id)
                    if let course = found.courses.first { return course }
                    if tryLive, let bcd = try SMM2Archive.liveData(id.description) {
                        return SMM2Course(dataID: id, name: id.description, levelData: bcd, isBcdFile: true)
                    }
                    if found.partial { throw SMM2Error.custom("The archive couldn't finish checking that course. Try again, or switch on the live course server.") }
                    return nil
                }
                return try SMM2Archive.course(code: code, tryLive: tryLive)
            }
            DispatchQueue.main.async { then(answer) }
        }
    }

    // Queueing never touches the save. The course is written later, by the
    // same path as a direct write, with every check made again at that moment.
    func queueSMM2Course(_ course: SMM2Course, in slot: Int, for g: Game) {
        guard g.titleID.uppercased() == smm2TitleID, SMM2Slots.downloaded.contains(slot) else {
            smm2QueueNote = "That slot can't be used. Nothing was queued."; return
        }
        smm2Queue = SMM2Queue(course: course, slot: slot, titleID: g.titleID)
        smm2QueueNote = "Queued \(course.name.isEmpty ? course.courseID : course.name) for Downloaded Course \(SMM2Slots.name(slot)). Save and quit \(g.name); Docked will check the game is closed before writing."
        logActivity("Queued a course for Coursebot", detail: "Waiting for \(g.name) to close before replacing course_data_\(SMM2Slots.name(slot)).bcd.")
    }

    func cancelSMM2Queue() {
        guard let queued = smm2Queue else { smm2QueueNote = "There is no queued course."; return }
        smm2Queue = nil
        smm2QueueNote = "Cancelled the queued course for slot \(SMM2Slots.name(queued.slot)). Nothing was written."
    }

    func applySMM2QueueIfReady() {
        guard let queued = smm2Queue else { return }
        guard let g = games.first(where: { $0.titleID.uppercased() == queued.titleID.uppercased() }) else {
            smm2Queue = nil; smm2QueueNote = "That game is no longer in the library, so the queued course wasn't used."; return
        }
        guard queued.matches(g.titleID) else {
            smm2Queue = nil; smm2QueueNote = "The queued course didn't match the game, so nothing was written."; return
        }
        let running = isRunning(g), open = isOpen(g)
        let slots = SMM2Slots.populated(in: GameData(g.titleID).save)
        guard queued.canApply(gameRunning: running, gameOpen: open, populatedSlots: slots) else {
            if running || open { return }   // still playing: wait for the next close
            smm2Queue = nil; smm2QueueNote = "Downloaded Course \(SMM2Slots.name(queued.slot)) is no longer populated, so the queued course wasn't used."; return
        }
        smm2Queue = nil
        smm2Inject(queued.course, into: g, slot: queued.slot, tryLive: true) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e): smm2QueueNote = "The queued course wasn't added. \(e.localizedDescription)"
            case .success: smm2QueueNote = "Done. The queued course is in Downloaded Course \(SMM2Slots.name(queued.slot)). Coursebot still shows that slot's old thumbnail and title."
            }
        }
    }

    func smm2Inject(_ course: SMM2Course, into g: Game, slot: Int, tryLive: Bool, then: @escaping (Result<Void, Error>) -> Void) {
        let data = GameData(g.titleID)
        func refuse(_ e: Error) { then(.failure(e)) }
        guard g.rom == nil, g.titleID.uppercased() == smm2TitleID else {
            refuse(SMM2Error.custom("Course Browser works with converted Super Mario Maker 2 games only.")); return
        }
        guard !isOpen(g), !isRunning(g) else { refuse(SMM2Error.gameOpen); return }
        guard data.hasSave else { refuse(SMM2Error.noSave); return }
        guard SMM2Slots.populated(in: data.save).contains(slot) else {
            refuse(SMM2Error.custom("Choose a Coursebot slot that already has a course in it. Empty slots may be ignored by the game.")); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let prepared = Result { () throws -> Data in
                var course = course
                if course.levelData == nil, tryLive, let bcd = try SMM2Archive.liveData(course.courseID) {
                    course.levelData = bcd
                    course.isBcdFile = true
                }
                return try SMM2Injector.prepare(course)
            }
            DispatchQueue.main.async {
                switch prepared {
                case .failure(let e): refuse(e)
                case .success(let file):
                    // The lookup could take a while. Check again, on the main
                    // queue, that nothing has opened the game in the meantime.
                    guard g.rom == nil, g.titleID.uppercased() == smm2TitleID else {
                        refuse(SMM2Error.custom("Course Browser works with converted Super Mario Maker 2 games only.")); return
                    }
                    guard !self.isOpen(g), !self.isRunning(g) else { refuse(SMM2Error.gameOpen); return }
                    guard data.hasSave else { refuse(SMM2Error.noSave); return }
                    guard SMM2Slots.populated(in: data.save).contains(slot) else {
                        refuse(SMM2Error.custom("Choose a Coursebot slot that already has a course in it. Empty slots may be ignored by the game.")); return
                    }
                    // The backup is a dated copy of the player's save, made only
                    // once there is a course ready to put in.
                    guard self.snapshotSave(g, "before SMM2 course injection", quiet: true) != nil else {
                        refuse(SMM2Error.custom("Docked couldn't back up the save, so nothing was changed.")); return
                    }
                    do {
                        try SMM2Injector.write(file, to: data.save, slot: slot)
                        self.tell("The course is now in Coursebot slot \(SMM2Slots.name(slot)). The slot's thumbnail and title are unchanged.")
                        self.logActivity("Added a course to Coursebot", detail: "Replaced only course_data_\(SMM2Slots.name(slot)).bcd. The old thumbnail, title, maker and stats remain in that slot.")
                        then(.success(()))
                    } catch { refuse(error) }
                }
            }
        }
    }
}
