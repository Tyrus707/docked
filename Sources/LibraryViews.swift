import SwiftUI

private func short(_ u: URL) -> String { u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
private func kindTitle(_ f: Found) -> String {
    switch f.kind {
    case .app: return "Converted games"
    case .rom(let c): return consoleName(c)
    case .choose: return "Choose a console"
    case .switchFile: return "Switch games to convert"
    }
}

// Games found on this Mac and its drives, to tick and bring in
struct ImportView: View {
    @EnvironmentObject var model: Model
    var st: Importing { model.importing ?? Importing() }
    var groups: [(String, [Found])] {
        var order: [String] = [], by: [String: [Found]] = [:]
        for f in st.found.sorted(by: { ($0.name.localizedStandardCompare($1.name)) == .orderedAscending }) { let k = kindTitle(f); if by[k] == nil { order.append(k) }; by[k, default: []].append(f) }
        let first = ["Converted games"], last = ["Choose a console", "Switch games to convert"]
        return (first.filter { by[$0] != nil } + order.filter { !first.contains($0) && !last.contains($0) }.sorted() + last.filter { by[$0] != nil }).map { ($0, by[$0]!) }
    }
    var body: some View {
        let n = st.chosen.count
        VStack(alignment: .leading, spacing: 14) {
            Text("Find Games on This Mac").font(.title2.weight(.semibold))
            Text("Docked looked in Applications, its own folder, OpenEmu, RetroArch, Ryujinx and folders called ROMs or Games. Games on a drive or anywhere else: Look in Another Folder.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if st.found.isEmpty {
                VStack(spacing: 8) {
                    if st.looking { ProgressView().controlSize(.small); Text("Looking…").foregroundStyle(.secondary) }
                    else { Image(systemName: "checkmark.circle").font(.title).foregroundStyle(style.accent).accessibilityHidden(true); Text("Every game Docked found is already in your library.").foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity).frame(height: 160)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.0) { g in
                            HStack { Text(g.0).font(.headline); Text("\(g.1.count)").foregroundStyle(.secondary).monospacedDigit(); Spacer()
                                if g.0 != "Switch games to convert" { Button(g.1.allSatisfy { st.picked.contains($0.id) } ? "None" : "All") { let all = g.1.allSatisfy { st.picked.contains($0.id) }; for f in g.1 { if all { model.importing?.picked.remove(f.id) } else { model.importing?.picked.insert(f.id) } } }.buttonStyle(.plain).foregroundStyle(style.accent).font(.callout) }
                            }.padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
                            ForEach(g.1) { f in row(f); Divider().padding(.leading, 10) }
                        }
                    }
                }.frame(height: 340).background(style.tile).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if st.looking && !st.found.isEmpty { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Still looking…").font(.callout).foregroundStyle(.secondary) } }
            HStack {
                Button("Look in Another Folder…") { model.findIn() }.disabled(st.looking)
                Spacer()
                Button("Cancel") { model.importing = nil }.keyboardShortcut(.cancelAction)
                Button(n == 1 ? "Add 1 Game" : "Add \(n) Games") { model.addFound() }.keyboardShortcut(.defaultAction).disabled(n == 0).tint(style.button)
            }
        }.padding(24).frame(width: 620).background(AllowQuit()).background(Backdrop())
    }
    @ViewBuilder func row(_ f: Found) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if case .switchFile = f.kind { Image(systemName: "wand.and.stars").foregroundStyle(style.accent).frame(width: 18).accessibilityHidden(true) }
            else { Toggle(f.name, isOn: .init(get: { st.picked.contains(f.id) }, set: { v in if v { model.importing?.picked.insert(f.id) } else { model.importing?.picked.remove(f.id) } })).labelsHidden().toggleStyle(.checkbox).disabled({ if case .choose = f.kind { return st.console[f.id] == nil }; return false }()) }
            VStack(alignment: .leading, spacing: 1) {
                Text(f.name).lineLimit(1)
                Text("\(f.source) · \(short(f.url.deletingLastPathComponent()))" + (model.games.contains { g in if case let .app(t) = f.kind { return g.titleID.uppercased() == t.uppercased() }; return false } ? " · another copy of a game you have" : "")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            switch f.kind {
            case .choose(let cs): Picker("Console", selection: .init(get: { st.console[f.id] ?? "" }, set: { model.importing?.console[f.id] = $0; model.importing?.picked.insert(f.id) })) { Text("Choose…").tag(""); ForEach(cs, id: \.self) { Text(consoleName($0)).tag($0) } }.labelsHidden().fixedSize()
            case .switchFile: Button("Convert…") { model.convertFound(f) }.controlSize(.small)
            default: EmptyView()
            }
        }.padding(.horizontal, 10).padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}

// Asked when games come from somewhere else: what to do with their files
struct AddModeView: View {
    @EnvironmentObject var model: Model
    let pending: PendingAdd
    @State private var mode = AddMode.copy
    @State private var remember = false
    var body: some View {
        let n = pending.found.count
        VStack(alignment: .leading, spacing: 14) {
            Text(n == 1 ? "Add \(pending.found[0].name)" : "Add \(n) Games").font(.title2.weight(.semibold))
            Text("What should Docked do with \(n == 1 ? "its file" : "their files")? Your library folder is \(short(model.libraryFolder)).").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(AddMode.allCases, id: \.self) { m in
                    Button { mode = m } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: mode == m ? "largecircle.fill.circle" : "circle").foregroundStyle(mode == m ? style.accent : .secondary).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) { Text(m.label).foregroundStyle(style.text); Text(m.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(mode == m ? .isSelected : [])
                }
            }.padding(12).background(style.tile, in: RoundedRectangle(cornerRadius: 8))
            Toggle("Don't ask again. You can change this in Settings, under Library.", isOn: $remember).toggleStyle(.checkbox).font(.callout)
            HStack { Spacer(); Button("Cancel") { model.askingMode = nil }.keyboardShortcut(.cancelAction); Button("Add") { if remember { model.addMode = mode }; model.askingMode = nil; model.take(pending.found, mode: mode) }.keyboardShortcut(.defaultAction).tint(style.button) }
        }.padding(24).frame(width: 480).background(AllowQuit()).background(Backdrop())
    }
}

// What Organize Library will move, before anything moves
struct TidyView: View {
    @EnvironmentObject var model: Model
    var list: [Tidy] { model.tidying ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Organize Library").font(.title2.weight(.semibold))
            Text("Each game goes in its console's folder in \(short(model.libraryFolder)), named after the game. Saves follow their game. Games you keep outside Docked's folders, such as another emulator's, stay where they are.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if list.isEmpty {
                VStack(spacing: 8) { Image(systemName: "checkmark.circle").font(.title).foregroundStyle(style.accent).accessibilityHidden(true); Text("Your library is already organized.").foregroundStyle(.secondary) }.frame(maxWidth: .infinity).frame(height: 120)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(list) { t in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.game.name)
                                Text("\(short(t.game.url.deletingLastPathComponent()))  →  \(short(t.to.deletingLastPathComponent()))" + (t.to.lastPathComponent != t.game.url.lastPathComponent && t.game.rom != nil ? ", as \(t.to.lastPathComponent)" : "")).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                            }.padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                    }
                }.frame(height: min(320, CGFloat(list.count) * 46 + 4)).background(style.tile).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button("Show Library in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.libraryFolder]) }
                Spacer()
                Button(list.isEmpty ? "Done" : "Cancel") { model.tidying = nil }.keyboardShortcut(.cancelAction)
                if !list.isEmpty { Button(list.count == 1 ? "Organize 1 Game" : "Organize \(list.count) Games") { model.tidy(list) }.keyboardShortcut(.defaultAction).tint(style.button) }
            }
        }.padding(24).frame(width: 580).background(AllowQuit()).background(Backdrop())
    }
}

// Settings, Library tab
extension SettingsSheet {
    @ViewBuilder var library: some View {
        VStack(spacing: 14) {
            line("Library folder", short(model.libraryFolder) + (drive(of: model.libraryFolder.path).map { $0.connected ? ", on \($0.name)" : ". \($0.name) isn't connected." } ?? "")) { Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([model.libraryFolder]) }; Button("Change…") { model.pickLibraryFolder() } }
            flip("Keep the library organized", "New games go into their console's folder on their own, without asking. Turn this off to choose a folder yourself.", $model.organized)
            line("Name game files by", "Games for other consoles. Files that belong together keep their names.") { Picker("Name game files by", selection: $model.naming) { ForEach(Naming.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().fixedSize().disabled(!model.organized) }
            line("Games from other folders", model.addMode?.detail ?? "Docked asks each time.") { Picker("Games from other folders", selection: $model.addMode) { Text("Ask Each Time").tag(AddMode?.none); Divider(); ForEach(AddMode.allCases, id: \.self) { Text($0.label).tag(AddMode?.some($0)) } }.labelsHidden().fixedSize() }
            line("Organize", "Puts games in Docked's folders where they belong, after showing you the list.") { Button("Organize…") { model.planTidy() }.disabled(!model.organized) }
            line("Find games", "Converted games, OpenEmu, RetroArch, Ryujinx, and any folder or drive.") { Button("Find…") { model.findGames() } }
            line("Offloaded games", (model.offloadFolder.map { short($0) + (drive(of: $0.path).map { $0.connected ? ", on \($0.name)" : ". \($0.name) isn't connected." } ?? "") } ?? "Choose Offload on a game to free space. It goes to iCloud Drive, a cloud folder or a drive, and its tile and saves stay.") + (model.offloadedCount > 0 ? " \(model.offloadedCount) offloaded now." : "")) { if let f = model.offloadFolder { Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([f]) } }; Button(model.offloadFolder == nil ? "Choose…" : "Change…") { model.pickOffloadFolder() } }
            ArtworkRow()
            VStack(alignment: .leading, spacing: 6) {
                line("Watched folders", "New games in these are added on their own and stay where they are. A drive's games come back when it's connected.") { Button("Add Folder…") { model.addWatched() } }
                ForEach(model.watched, id: \.self) { w in
                    HStack(spacing: 8) {
                        Image(systemName: drive(of: w) != nil ? "externaldrive" : "folder").foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
                        Text(short(URL(fileURLWithPath: w))).lineLimit(1).truncationMode(.middle)
                        if let d = drive(of: w), !d.connected { Text("Not connected").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button { model.watched.removeAll { $0 == w } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Stop watching").accessibilityLabel("Stop watching \(w)")
                    }.font(.callout).padding(.leading, 4)
                }
            }
        }
    }
}

// Where covers are kept and how much room they take, with a way to clear what no game uses
struct ArtworkRow: View {
    @EnvironmentObject var model: Model
    @State private var places: [ArtPlace]?
    @State private var clearing = false
    var body: some View {
        let all = places ?? [], bytes = all.reduce(0) { $0 + $1.bytes }, spare = all.reduce(0) { $0 + $1.spareBytes }, files = all.reduce(0) { $0 + $1.files }
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Artwork")
                Text(places == nil ? "Measuring…" : files == 0 ? "No covers yet." : "\(size(bytes)) in \(files) files. Covers you chose are in Docked › Artwork; found and ready-to-show ones in Docked › Metadata." + (spare > 0 ? " \(size(spare)) is left over from games no longer here." : " Nothing is left over."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if clearing { ProgressView().controlSize(.small) }
            Button("Show") { let u = [Artwork.yours, Artwork.found, Artwork.made].filter { FileManager.default.fileExists(atPath: $0.path) }; NSWorkspace.shared.activateFileViewerSelecting(u.isEmpty ? [Paths.root] : u) }
            Button("Clear Leftovers") { clear() }.disabled(spare == 0 || clearing).help("Covers you chose go to the Trash. Others can be found or made again.")
        }.onAppear(perform: measure)
    }
    func measure() { let ids = model.games.map(\.titleID); DispatchQueue.global(qos: .utility).async { let p = Artwork.survey(ids: ids); DispatchQueue.main.async { places = p } } }
    func clear() {
        guard let p = places else { return }; clearing = true
        DispatchQueue.global(qos: .utility).async { let freed = Artwork.removeSpare(p); DispatchQueue.main.async { clearing = false; model.tell("Cleared \(size(freed)) of leftover artwork."); measure() } }
    }
    func size(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}
