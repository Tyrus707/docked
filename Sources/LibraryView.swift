import SwiftUI

struct Shell: View {
    @EnvironmentObject var model: Model
    @Binding var deleting: Game?
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 960, g = model.chosen
            HStack(spacing: 0) {
                Sidebar(); line
                Pane(deleting: $deleting).frame(maxWidth: .infinity)
                if wide, let g { line; Inspector(game: g, deleting: $deleting).transition(.move(edge: .trailing)) }
            }
            .overlay(alignment: .bottom) { if model.padUsed { PadHints(open: g != nil) } }
            .overlay(alignment: .trailing) { if !wide, let g { HStack(spacing: 0) { line; Inspector(game: g, deleting: $deleting) }.shadow(color: .black.opacity(0.35), radius: 16, x: -4).transition(.move(edge: .trailing)) } }
            .clipped().animation(still ? nil : .easeOut(duration: 0.11), value: g?.id)
        }.onExitCommand { model.selected = nil }
    }
    var line: some View { Rectangle().fill(style.line.opacity(0.6)).frame(width: 1) }
}

struct PadHints: View {
    let open: Bool
    var body: some View {
        HStack(spacing: 18) { hint("A", open ? "Play" : "Details"); hint("B", "Back"); hint("Y", "Favorite"); hint("L R", "Sections"); hint("+", "Play") }
            .padding(.horizontal, 18).padding(.vertical, 9).background(Color.black.opacity(0.72), in: Capsule()).padding(.bottom, 14).allowsHitTesting(false).accessibilityHidden(true)
    }
    func hint(_ b: String, _ t: String) -> some View { HStack(spacing: 6) { Text(b).font(.caption.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 2).background(Color.white.opacity(0.22), in: Capsule()); Text(t).font(.callout) }.foregroundStyle(.white) }
}

// ---- sidebar ----
struct Sidebar: View {
    @EnvironmentObject var model: Model
    @State private var naming = false
    @Namespace private var mark
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var name = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                row(.home); row(.all); row(.favorites)
                head("Consoles"); ForEach(model.consolesShown, id: \.id) { row(.console($0.id)) }
                head("Progress"); row(.status(.playing)); row(.status(.finished)); row(.status(.aside)); row(.status(.none))
                HStack { head("Collections"); Spacer(); Menu { Button("New Collection…") { name = ""; naming = true }; Button("New Smart Collection…") { model.editing = SmartCollection(name: "") } } label: { Image(systemName: "plus").frame(width: 22, height: 22).contentShape(Rectangle()) }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().foregroundStyle(style.soft).help("New Collection").accessibilityLabel("New Collection").padding(.top, 12) }
                ForEach(model.library.collections, id: \.self) { c in
                    row(.collection(c)).contextMenu {
                        Button("Rename…") { model.renaming = c }
                        Button("Remove Collection") { model.removeCollection(c) }
                    }
                }
                ForEach(model.library.smart) { c in row(.smart(c)).contextMenu { Button("Edit…") { model.editing = c }; Button("Remove Collection") { if model.section == .smart(c) { model.section = .home }; model.library.smart.removeAll { $0.id == c.id } } } }
                if model.library.collections.isEmpty && model.library.smart.isEmpty { Text("Group games your way").font(.caption).foregroundStyle(style.soft).padding(.leading, 10) }
                let drives = model.drivesInUse
                if !drives.isEmpty {
                    head("Drives")
                    ForEach(drives, id: \.name) { d in
                        HStack(spacing: 9) {
                            Circle().fill(d.connected ? style.ok : .clear).overlay(Circle().strokeBorder(d.connected ? .clear : style.soft, lineWidth: 1.5)).frame(width: 7, height: 7).frame(width: 18)
                            Text(d.name).foregroundStyle(d.connected ? style.text : style.soft).lineLimit(1)
                            Spacer()
                            if !d.connected { Text("Unplugged").font(.caption).foregroundStyle(style.soft) }
                        }.padding(.horizontal, 10).frame(height: 30).accessibilityElement(children: .combine)
                    }
                }
            }.padding(.horizontal, 10).padding(.vertical, 12)
        }
        .frame(width: 216)
        .alert("New Collection", isPresented: $naming) { TextField("Name", text: $name); Button("Create") { model.newCollection(name, adding: nil) }; Button("Cancel", role: .cancel) {} }
    }
    func head(_ t: String) -> some View { Text(t).font(.caption.weight(.semibold)).foregroundStyle(style.soft).padding(.leading, 10).padding(.top, 14).padding(.bottom, 3).accessibilityAddTraits(.isHeader) }
    func row(_ s: Section) -> some View {
        let on = model.section == s, n = s == .home ? nil : model.count(s)
        return Button { withAnimation(still ? nil : .easeOut(duration: 0.18)) { model.section = s } } label: {
            HStack(spacing: 9) {
                Group { if case let .console(id) = s { ConsoleIcon(id: id) } else { Image(systemName: on && s == .favorites ? "heart.fill" : s.symbol) } }.frame(width: 18).foregroundStyle(s.machine?.color ?? (on ? style.accent : style.soft))
                Text(s.title).foregroundStyle(style.text).lineLimit(1)
                Spacer()
                if let n { Text("\(n)").font(.caption).monospacedDigit().foregroundStyle(style.soft) }
            }
            .padding(.horizontal, 10).frame(height: 30).background { if on { RoundedRectangle(cornerRadius: 8).fill(style.tile).matchedGeometryEffect(id: "mark", in: mark) } }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
}

// ---- main pane ----
struct Pane: View {
    @EnvironmentObject var model: Model
    @Binding var deleting: Game?
    var body: some View {
        ZStack { if model.section == .home && model.search.isEmpty { Home(deleting: $deleting).transition(.opacity) } else { Grid(deleting: $deleting).id(model.search.isEmpty ? model.section : .all).transition(.opacity) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle()).onTapGesture { model.selected = nil }   // blank space; games and buttons take their own clicks
    }
}

struct Home: View {
    @EnvironmentObject var model: Model
    @Binding var deleting: Game?
    var body: some View {
        ScrollViewReader { p in ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                let recent = Array(model.shown(.all, by: .recent).prefix(5))
                if !recent.isEmpty { Carousel(games: recent).id("recent") }
                if model.converting { Shelf(title: "Converting") { ArrivingTile().frame(width: 164) } }
                let fav = model.shown(.favorites)
                if !fav.isEmpty { shelf("Favorites", .favorites, fav) }
                ForEach(model.consolesShown, id: \.id) { c in let l = model.shown(.console(c.id)); if !l.isEmpty { shelf(c.name, .console(c.id), l) } }
                ForEach(model.library.collections, id: \.self) { c in let l = model.shown(.collection(c)); if !l.isEmpty { shelf(c, .collection(c), l) } }
            }.padding(22)
        }.whenChanged(model.cursor) { if let c = model.cursor { withAnimation(.easeOut(duration: 0.15)) { p.scrollTo(c.row) } } } }
    }
    func shelf(_ t: String, _ s: Section, _ l: [Game]) -> some View {
        Shelf(title: t, count: l.count, all: { model.section = s }, dot: s.machine?.color) { ForEach(l) { g in Tile(game: g, deleting: $deleting, row: t).frame(width: 164).id("\(t)|\(g.id)") } }.id(t)
    }
}

struct Shelf<C: View>: View {
    @EnvironmentObject var model: Model
    let title: String; var count = 0; var all: (() -> Void)?; var dot: Color? = nil   // a console's own colour beside its name
    private var cursor: Cursor? { model.cursor }
    @ViewBuilder var content: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                if let dot { Circle().fill(dot).frame(width: 9, height: 9).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }.accessibilityHidden(true) }
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(style.text).accessibilityAddTraits(.isHeader)
                Spacer()
                if let all, count > 3 { Button("See All") { all() }.buttonStyle(.plain).font(.callout).foregroundStyle(style.accent) }
            }
            ScrollViewReader { p in ScrollView(.horizontal, showsIndicators: false) { LazyHStack(alignment: .top, spacing: 8) { content() } }.whenChanged(cursor) { if let c = cursor, c.row == title { withAnimation(.easeOut(duration: 0.15)) { p.scrollTo("\(c.row)|\(c.game)") } } } }
        }
    }
}

// The last game played, on a wash of its own art: the icon drawn tiny and stretched, which costs nothing to keep on screen.
// The game you were playing, by the fire: its wide art when Docked has it, one brass action, the rest quiet.
struct Hero: View {
    @EnvironmentObject var model: Model
    let game: Game
    @State private var art: NSImage?
    var body: some View {
        let e = model.library.entry(game.titleID), c = game.rom == nil ? model.compat[game.titleID.uppercased()] : nil
        let label = model.isRunning(game) ? "PLAYING NOW" : game.missing ? "NOT CONNECTED" : e.lastPlayed == nil ? "READY TO PLAY" : "CONTINUE PLAYING"
        let facts = [consoleName(consoleOf(game.titleID)), e.seconds >= 60 ? playTimeText(e.seconds).replacingOccurrences(of: " played", with: "") : nil, e.lastPlayed.map { lastPlayedText($0) }, c.map { $0.label + ($0.fps.isEmpty ? "" : ", \($0.fps)") }].compactMap { $0 }
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            HStack(spacing: 7) { Circle().fill(game.missing ? style.soft : style.accent).frame(width: 7, height: 7); Text(label).font(.caption.weight(.semibold)).tracking(1.4) }.foregroundStyle(game.missing ? style.soft : style.accent).accessibilityElement(children: .combine)
            Text(game.name).font(.system(size: 40, weight: .heavy)).tracking(-0.6).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
            Text(facts.joined(separator: " · ")).font(.callout).foregroundStyle(.white.opacity(0.82)).lineLimit(1)
            HStack(spacing: 10) {
                Button { model.play(game) } label: { Label(model.isRunning(game) ? "Show" : "Play", systemImage: "play.fill").font(.body.weight(.bold)).padding(.horizontal, 24).frame(height: 40).foregroundStyle(Color(hex: 0x1B1612)).background(style.accent, in: Capsule()) }.buttonStyle(.plain).disabled(game.missing)
                if game.rom == nil, !game.missing { Button { model.openSettings(game) } label: { Text("Game Settings").font(.body.weight(.medium)).padding(.horizontal, 18).frame(height: 40).foregroundStyle(.white).background(Capsule().fill(.black.opacity(0.3))).overlay(Capsule().strokeBorder(.white.opacity(0.28))) }.buttonStyle(.plain) }
            }.padding(.top, 4)
        }
        .padding(.horizontal, 34).padding(.vertical, 28).frame(maxWidth: .infinity, minHeight: 300, alignment: .leading)
        .background { ZStack { style.bottom; if let art { Image(nsImage: art).resizable().interpolation(.high).scaledToFill() } else { Image(nsImage: model.wash(game)).resizable().interpolation(.high).scaledToFill().opacity(0.9) }; LinearGradient(colors: [style.bottom.opacity(0.94), style.bottom.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing) }.accessibilityHidden(true) }
        .clipShape(RoundedRectangle(cornerRadius: 18)).overlay { if model.cursor == Cursor(row: "recent", game: game.id) { RoundedRectangle(cornerRadius: 18).strokeBorder(style.accent, lineWidth: 4) } }.contentShape(RoundedRectangle(cornerRadius: 18)).onTapGesture { model.select(game) }
        .task(id: game.id) { let u = CouchArt.banner(game.titleID); art = await Task.detached(priority: .utility) { CouchArt.load(u) }.value }
    }
}

struct Grid: View {
    @EnvironmentObject var model: Model
    @Binding var deleting: Game?
    @State private var confirm: [Game]?
    var body: some View {
        let list = model.gridList, groups = model.gridGroups
        let lost = list.filter { $0.missing && $0.away == nil && drive(of: $0.url.path)?.connected != false }   // can't be found, and not because a drive is away
        GeometryReader { geo in let back = model.marking ? [] : model.jumpBack(perRow(geo.size.width)); ScrollViewReader { p in ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(model.search.isEmpty ? model.section.title : "Search").font(.title2.weight(.semibold)).foregroundStyle(style.text).accessibilityAddTraits(.isHeader)
                    Text("\(list.count)").foregroundStyle(style.soft).monospacedDigit()
                    Spacer()
                    if !lost.isEmpty, !model.marking { Button("Remove \(lost.count) Missing") { confirm = lost }.buttonStyle(.plain).foregroundStyle(style.accent).help("Take games that can't be found out of the library") }
                    if !list.isEmpty { Button(model.marking ? "Done" : "Select") { model.marking.toggle() }.buttonStyle(.plain).foregroundStyle(style.accent) }
                    Menu {
                        Picker("Sort by", selection: $model.sort) { ForEach(SortBy.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.inline)
                        Picker("Group by", selection: $model.group) { ForEach(GroupBy.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline)
                        Divider()
                        Toggle("Compact Tiles", isOn: $model.compact)
                    } label: { Text(model.sort.title) }.menuStyle(.button).buttonStyle(.plain).fixedSize().foregroundStyle(style.accent).accessibilityLabel("Sort by \(model.sort.title)").help("Sort, group and tile size")
                }
                if list.isEmpty && !(model.converting && model.section == .all) { blank }
                if !back.isEmpty { run(Model.jumpRow, back, arriving: false) }
                ForEach(groups, id: \.0) { g in run(g.0, g.1, arriving: g.0 == groups.first?.0) }
            }.padding(22)
        }.whenChanged(model.cursor) { if let c = model.cursor { withAnimation(.easeOut(duration: 0.15)) { p.scrollTo("\(c.row)|\(c.game)") } } } }
            .onAppear { model.columns = perRow(geo.size.width) }.whenChanged(geo.size.width) { model.columns = perRow(geo.size.width) }.whenChanged(model.compact) { model.columns = perRow(geo.size.width) } }
            .safeAreaInset(edge: .bottom) { if model.marking { marks(list) } }
            .onDisappear { model.marking = false }
            .alert(confirm.map { $0.count == 1 ? "Remove \($0[0].name) from the library?" : "Remove \($0.count) games from the library?" } ?? "", isPresented: .init(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
                Button("Remove", role: .destructive) { if let c = confirm { remove(c) }; confirm = nil }
                Button("Cancel", role: .cancel) { confirm = nil }
            } message: { Text("Their files stay where they are, and their play time is kept if you add them again.") }
    }
    // Choosing several: a bar at the foot of the grid
    func marks(_ list: [Game]) -> some View {
        let n = model.marked.count
        return HStack(spacing: 14) {
            Text(n == 0 ? "Click games to choose them" : "\(n) chosen").foregroundStyle(style.text).monospacedDigit()
            Spacer()
            Button(n == list.count ? "Choose None" : "Choose All") { model.marked = n == list.count ? [] : Set(list.map(\.id)) }
            let chosen = list.filter { model.marked.contains($0.id) }
            Button("Offload") { model.offload(chosen); model.marking = false }.disabled(!chosen.contains { !$0.missing && $0.away == nil }).help("Free space: move them to iCloud Drive, another cloud folder or a drive")
            Button("Download") { model.download(chosen); model.marking = false }.disabled(!chosen.contains { $0.away != nil })
            Button("Remove from Library") { confirm = chosen }.disabled(n == 0).tint(style.button)
            Button("Done") { model.marking = false }
        }.padding(.horizontal, 18).padding(.vertical, 10).background(style.tile.opacity(0.97)).overlay(alignment: .top) { Rectangle().fill(style.line).frame(height: 1) }
    }
    func remove(_ list: [Game]) {
        let r = model.forget(list); model.marking = false
        if r.kept > 0 { model.tell("\(r.kept) converted \(r.kept == 1 ? "game stays" : "games stay"): \(r.kept == 1 ? "it is" : "they are") in your library folder. Use Move Game to Trash to remove \(r.kept == 1 ? "it" : "them").", good: false) }
        else if r.gone > 0 { model.tell(r.gone == 1 ? "1 game has left the library." : "\(r.gone) games have left the library.") }
    }
    var tile: CGFloat { model.compact ? 112 : 156 }
    // One run of the grid, under its own heading when it has one ("grid" is the untitled whole list).
    @ViewBuilder func run(_ row: String, _ l: [Game], arriving: Bool) -> some View {
        if row != "grid" {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row).font(.headline).foregroundStyle(row == Model.jumpRow ? style.accent : style.text).accessibilityAddTraits(.isHeader)
                Text("\(l.count)").font(.callout).foregroundStyle(style.soft).monospacedDigit()
                Rectangle().fill(style.line).frame(height: 1).padding(.leading, 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
            }.padding(.top, 8)
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tile, maximum: tile + 44), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
            if arriving && model.converting && model.section == .all && model.search.isEmpty && !model.marking { ArrivingTile() }
            ForEach(l) { Tile(game: $0, deleting: $deleting, row: row, small: model.compact).id("\(row)|\($0.id)") }
        }
    }
    func perRow(_ w: CGFloat) -> Int { max(1, Int((w - 44 + 10) / (tile + 10))) }   // as the grid folds
    var blank: some View {
        VStack(spacing: 8) {
            DPad().fill(style.line).frame(width: 34, height: 34).accessibilityHidden(true)
            Text(model.search.isEmpty ? "Nothing here yet" : "No games match “\(model.search)”").font(.headline).foregroundStyle(style.text)
            Text(hint).font(.callout).foregroundStyle(style.soft).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.top, 70)
    }
    var hint: String {
        if !model.search.isEmpty { return "Check the spelling, or try part of the name." }
        switch model.section {
        case .favorites: return "Open a game's ••• menu and choose Favorite."
        case .collection: return "Open a game's ••• menu, then Collections, to add it."
        case .status: return "Open a game's ••• menu, then Progress, to mark it."
        case .smart: return "No game matches its rules now. Right-click it in the sidebar to change them."
        default: return "Drop a game in this window to add it."
        }
    }
}

struct Tile: View {
    @EnvironmentObject var model: Model
    let game: Game
    @Binding var deleting: Game?
    var row = ""
    var small = false
    var body: some View {
        let e = model.library.entry(game.titleID)
        let c = game.rom == nil ? model.compat[game.titleID.uppercased()] : nil, worry = c.map { $0.kind == .okay || $0.kind == .poor } ?? false
        let note = game.away.map { "Offloaded to " + offloadName($0) } ?? (game.missing ? whereMissing(game.url.path) : model.isRunning(game) ? "Playing now" : game.cannot != nil ? game.cannot! : worry ? c!.label : e.kept && e.lastPlayed == nil ? "Kept build" : e.lastPlayed != nil ? lastPlayedText(e.lastPlayed) : game.rom == nil ? "Version \(game.version)" : consoleName(consoleOf(game.titleID)))
        Group {
            if model.look == .covers { CoverTile(game: game, art: model.cover(game), favorite: e.favorite, running: model.isRunning(game), note: note, chosen: model.cursor.map { $0.row == row && $0.game == game.id } ?? (model.selected == game.id), select: { model.select(game) }, play: { model.play(game) }, fave: { model.edit(game) { $0.favorite.toggle() } }) { AnyView(GameActions(game: game, deleting: $deleting)) } }
            else { GameTile(game: game, icon: model.icon(game), favorite: e.favorite, running: model.isRunning(game), note: note, chosen: model.cursor.map { $0.row == row && $0.game == game.id } ?? (model.selected == game.id), small: small, select: { model.select(game) }, play: { model.play(game) }, fave: { model.edit(game) { $0.favorite.toggle() } }) { AnyView(GameActions(game: game, deleting: $deleting)) } }
        }.opacity(game.away != nil ? 0.78 : game.missing ? 0.5 : 1)
        .overlay(alignment: .topTrailing) { if game.away != nil, !model.marking { Image(systemName: "icloud.and.arrow.down").font(.system(size: small || model.compact ? 12 : 15, weight: .semibold)).foregroundStyle(.white).padding(6).background(.black.opacity(0.55), in: Circle()).padding(8).help("Offloaded. Play or Download brings it back.").accessibilityLabel("Offloaded") } }
        .onDrop(of: [.fileURL], isTargeted: nil) { loadDropped($0) { model.dropped($0, on: game) }; return true }
        .overlay { if model.marking { Mark(on: model.marked.contains(game.id)).contentShape(Rectangle()).onTapGesture { model.mark(game) }.accessibilityElement().accessibilityLabel(game.name).accessibilityAddTraits(model.marked.contains(game.id) ? [.isButton, .isSelected] : .isButton) } }
    }
}

// Over a tile while choosing several: a tick in the corner, and the whole tile takes the click
struct Mark: View {
    let on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 12).strokeBorder(on ? style.accent : .clear, lineWidth: 3).background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(on ? 0 : 0.18)))
            .overlay(alignment: .topLeading) { Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 22, weight: .semibold)).foregroundStyle(on ? style.accent : .white).background(Circle().fill(Color.black.opacity(0.45)).padding(2)).padding(12) }
    }
}

struct GameActions: View {
    @EnvironmentObject var model: Model
    let game: Game
    @Binding var deleting: Game?
    var body: some View {
        let e = model.library.entry(game.titleID)
        if game.away != nil { Button("Download") { model.download([game]) }; Button("Remove from Library") { model.forget(game) }; Divider() }
        else if game.missing { Button("Locate…") { model.locate(game) }; Button("Remove from Library") { model.forget(game) }; Divider() }
        Button("Play") { model.play(game) }.disabled(game.missing && game.away == nil)
        if game.rom == nil { Button("Game Settings…") { model.openSettings(game) }.disabled(game.missing); Button("Play with Settings…") { model.play(game, settings: true) } }
        Divider()
        Button(e.favorite ? "Remove from Favorites" : "Favorite") { model.edit(game) { $0.favorite.toggle() } }
        Menu("Rating") { ForEach([5, 4, 3, 2, 1], id: \.self) { n in Toggle(String(repeating: "★", count: n), isOn: .init(get: { e.rating == n }, set: { on in model.edit(game) { $0.rating = on ? n : 0 } })) }; Divider(); Button("No Rating") { model.edit(game) { $0.rating = 0 } }.disabled(e.rating == 0) }
        Menu("Progress") { ForEach(Entry.Status.allCases, id: \.self) { s in Toggle(s.rawValue, isOn: .init(get: { e.status == s }, set: { if $0 { model.edit(game) { $0.status = s } } })) } }
        Menu("Collections") {
            ForEach(model.library.collections, id: \.self) { c in Toggle(c, isOn: .init(get: { e.collections.contains(c) }, set: { on in model.edit(game) { on ? $0.collections.append(c) : $0.collections.removeAll { $0 == c } } })) }
            if !model.library.collections.isEmpty { Divider() }
            Button("New Collection…") { model.collecting = game }
        }
        Divider()
        if game.rom == nil, model.lookUp == true { Button(e.meta == nil ? "Find Details" : "Find Details Again") { model.findMeta(game, force: true) }.disabled(model.scoring.contains(game.titleID.uppercased())) }
        if game.rom == nil {
            Button("Add Update or DLC…") { model.addTo(game) }.disabled(e.kept); Button("Move to Folder…") { model.moveGame(game) }
            Toggle("Keep This Build", isOn: .init(get: { e.kept }, set: { on in model.edit(game) { $0.kept = on } }))
            SaveMenu(game: game)
        }
        else { Button("Rename…") { model.retitling = game }; if let r = game.rom { Button(r.info == nil ? "Find Cover and Details…" : "Find Details Again…") { model.find(r.id, byHand: true) }.disabled(model.finding.contains(r.id)) } }
        Button("Choose Cover…") { model.pickArt(game) }; if model.hasArt(game) { Button("Use Original Cover") { model.clearArt(game) } }
        Button("Copy Link for Shortcuts") { model.copyLink(game) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([game.away.map { URL(fileURLWithPath: $0) } ?? game.url]) }.disabled(game.missing && game.away == nil)
        if !game.missing {
            Divider()
            Button("Offload") { model.offload([game]) }.help("Move it to iCloud Drive, another cloud folder or a drive, to free space. Its tile and saves stay.")
            if game.rom == nil { Button("Clean Up…") { model.cleanUp(game) }; if !model.inLibrary(game.url) { Button("Remove from Library") { model.forget(game) } }; Button("Move Game to Trash…") { deleting = game } }
            else { Button("Remove from Library") { model.removeRom(game) } }
        }
    }
}
