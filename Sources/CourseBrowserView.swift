import SwiftUI

// Public courses, in plain language. The game stays closed; only one downloaded
// course file in its save changes. No account, no Nintendo servers, no upload.
struct CourseBrowserView: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss
    let game: Game

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

    private var save: GameData { GameData(game.titleID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Course Browser").font(.title2.weight(.semibold))
                Text("Find a public Super Mario Maker 2 course and put it into a Coursebot slot on this Mac. Docked never signs in or sends your save.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

            if busy {
                HStack { ProgressView(); Text("Looking for courses…").font(.callout).foregroundStyle(.secondary) }.frame(height: 120)
            } else if courses.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(note.isEmpty ? "Search the archive, or enter a course ID." : note).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(courses) { course in
                            Button { selected = course } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: selected?.dataID == course.dataID ? "checkmark.circle.fill" : "circle").foregroundStyle(selected?.dataID == course.dataID ? style.accent : Color.secondary).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(course.name.isEmpty ? "Untitled course" : course.name).font(.callout.weight(.medium)).foregroundStyle(style.text).lineLimit(1)
                                        Text("\(course.courseID) · \(course.author.isEmpty ? "Unknown maker" : course.author)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Text(details(course)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 8)
                                .background(selected?.dataID == course.dataID ? style.tile.opacity(0.9) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }.frame(maxHeight: 280)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Coursebot destination").font(.callout.weight(.semibold))
                if slots.isEmpty {
                    Label("No downloaded course slot is ready. Start the game, put a course in a Downloaded Course slot, save and quit, then come back.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Menu(slot.map { "Downloaded course \(SMM2Slots.name($0))" } ?? "Choose a slot") {
                        ForEach(slots, id: \.self) { n in Button("Downloaded course \(SMM2Slots.name(n))") { slot = n } }
                    }.disabled(busy)
                    Text("Docked replaces only that course. Empty slots aren't used because the game may ignore them.").font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Show Saves in Finder") { model.reveal(save.save) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.escape).tint(style.button)
                Button("Put in Coursebot…") { confirming = true }
                    .disabled(busy || selected == nil || slot == nil)
                    .tint(style.button)
            }
        }
        .padding(24).frame(width: 620).background(AllowQuit()).background(Backdrop())
        .onAppear {
            slots = Array(SMM2Slots.populated(in: save.save)).sorted()
            slot = slots.first
        }
        .confirmationDialog("Replace Coursebot slot \(slot.map(SMM2Slots.name) ?? "")?", isPresented: $confirming) {
            Button("Put Course Here") { if let selected, let slot { put(selected, in: slot) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The course in this downloaded slot is replaced. Docked makes a dated backup of your save first. Coursebot will still show the old thumbnail, title, maker and stats.")
        }
    }

    private func details(_ c: SMM2Course) -> String {
        [c.style, c.theme, c.difficulty].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        busy = true; note = ""; selected = nil
        model.smm2Search(text) { result in
            busy = false
            switch result {
            case .failure(let e): courses = []; note = e.localizedDescription; model.message = e.localizedDescription
            case .success(let found):
                courses = found.courses
                note = found.courses.isEmpty ? (found.partial ? "The archive couldn't finish that search. Try a shorter name or a course ID." : "No courses matched. Try a shorter name or a course ID.") : "\(found.courses.count) course\(found.courses.count == 1 ? "" : "s") found."
            }
        }
    }

    private func lookUp() {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        busy = true; note = ""; selected = nil
        model.smm2Course(code: text, tryLive: tryLive) { result in
            busy = false
            switch result {
            case .failure(let e): courses = []; note = e.localizedDescription; model.message = e.localizedDescription
            case .success(let found):
                if let found { courses = [found]; note = "Course found." }
                else { courses = []; note = "That course isn't in the archive. Try the live server or another ID." }
            }
        }
    }

    private func put(_ course: SMM2Course, in slot: Int) {
        busy = true
        model.smm2Inject(course, into: game, slot: slot, tryLive: tryLive) { result in
            busy = false
            switch result {
            case .failure(let e): note = e.localizedDescription; model.message = e.localizedDescription
            case .success: note = "Done. The course is in Downloaded Course \(SMM2Slots.name(slot))."
            }
        }
    }
}

extension Model {
    func openCourseBrowser(_ g: Game) {
        guard g.rom == nil, g.titleID.uppercased() == smm2TitleID, !g.missing else {
            message = "Course Browser works with converted Super Mario Maker 2 games only."; return
        }
        guard !isOpen(g), !isRunning(g) else { message = SMM2Error.gameOpen.errorDescription ?? ""; return }
        guard GameData(g.titleID).hasSave else { message = SMM2Error.noSave.errorDescription ?? ""; return }
        courseBrowserGame = g
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
