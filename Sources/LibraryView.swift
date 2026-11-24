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
            .overlay(alignment: .trailing) { if !wide, let g { HStack(spacing: 0) { line; Inspector(game: g, deleting: $deleting) }.shadow(color: .black.opacity(0.35), radius: 16, x: -4).transition(.move(edge: .trailing)) } }
            .clipped().animation(still ? nil : .easeOut(duration: 0.2), value: g?.id)
        }.onExitCommand { model.selected = nil }
    }
    var line: some View { Rectangle().fill(style.line.opacity(0.6)).frame(width: 1) }
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
                HStack { head("Collections"); Spacer(); Button { name = ""; naming = true } label: { Image(systemName: "plus").frame(width: 22, height: 22).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(style.soft).help("New Collection").accessibilityLabel("New Collection").padding(.top, 12) }
                ForEach(model.library.collections, id: \.self) { c in
                    row(.collection(c)).contextMenu {
                        Button("Rename…") { model.renaming = c }
                        Button("Remove Collection") { model.removeCollection(c) }
                    }
                }
                if model.library.collections.isEmpty { Text("Group games your way").font(.caption).foregroundStyle(style.soft).padding(.leading, 10) }
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
                Image(systemName: on && s == .favorites ? "heart.fill" : s.symbol).frame(width: 18).foregroundStyle(on ? style.accent : style.soft)
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
    }
}

struct Home: View {
    @EnvironmentObject var model: Model
    @Binding var deleting: Game?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                let recent = Array(model.shown(.all, by: .recent).prefix(5))
                if !recent.isEmpty { Carousel(games: recent) }
                if model.converting { Shelf(title: "Converting") { ArrivingTile().frame(width: 164) } }
                let fav = model.shown(.favorites)
                if !fav.isEmpty { shelf("Favorites", .favorites, fav) }
                ForEach(model.consolesShown, id: \.id) { c in let l = model.shown(.console(c.id)); if !l.isEmpty { shelf(c.name, .console(c.id), l) } }
                ForEach(model.library.collections, id: \.self) { c in let l = model.shown(.collection(c)); if !l.isEmpty { shelf(c, .collection(c), l) } }
            }.padding(22)
        }
    }
    func shelf(_ t: String, _ s: Section, _ l: [Game]) -> some View {
        Shelf(title: t, count: l.count, all: { model.section = s }) { ForEach(l) { g in Tile(game: g, deleting: $deleting).frame(width: 164) } }
    }
}

struct Shelf<C: View>: View {
    let title: String; var count = 0; var all: (() -> Void)?
    @ViewBuilder var content: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(style.text).accessibilityAddTraits(.isHeader)
                Spacer()
                if let all, count > 3 { Button("See All") { all() }.buttonStyle(.plain).font(.callout).foregroundStyle(style.accent) }
            }
            ScrollView(.horizontal, showsIndicators: false) { LazyHStack(alignment: .top, spacing: 8) { content() } }
        }
    }
}

// The last game played, on a wash of its own art: the icon drawn tiny and stretched, which costs nothing to keep on screen.
struct Hero: View {
    @EnvironmentObject var model: Model
    let game: Game
    var body: some View {
        let e = model.library.entry(game.titleID)
        HStack(spacing: 20) {
            Image(nsImage: model.icon(game)).resizable().frame(width: 128, height: 128).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.isRunning(game) ? "Playing now" : e.lastPlayed == nil ? "Ready to play" : "Continue playing").font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.86))
                Text(game.name).font(.title.weight(.bold)).foregroundStyle(.white).lineLimit(2)
                Text(e.lastPlayed == nil ? consoleName(consoleOf(game.titleID)) : "\(lastPlayedText(e.lastPlayed)), \(playTimeText(e.seconds).lowercased())").font(.callout).foregroundStyle(.white.opacity(0.86))
                Button { model.play(game) } label: { Label(model.isRunning(game) ? "Show" : "Play", systemImage: "play.fill").font(.body.weight(.semibold)).padding(.horizontal, 18).frame(height: 34).foregroundStyle(Color(hex: 0x14242B)).background(.white, in: Capsule()) }.buttonStyle(.plain).padding(.top, 4).accessibilityLabel("Play \(game.name)")
            }
            Spacer(minLength: 0)
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: 196, alignment: .leading)
        .background { ZStack { Color(hex: 0x14242B); Image(nsImage: model.wash(game)).resizable().interpolation(.high).scaledToFill(); LinearGradient(colors: [.black.opacity(0.76), .black.opacity(0.44)], startPoint: .leading, endPoint: .trailing) } }
        .clipShape(RoundedRectangle(cornerRadius: 18)).contentShape(RoundedRectangle(cornerRadius: 18)).onTapGesture { model.select(game) }
    }
}

struct Grid: View {
    @EnvironmentObject var model: Model
    @Binding var deleting: Game?
    var body: some View {
        let list = model.shown(model.section == .home ? .all : model.section, by: model.sort)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.search.isEmpty ? model.section.title : "Search").font(.title2.weight(.semibold)).foregroundStyle(style.text).accessibilityAddTraits(.isHeader)
                    Text("\(list.count)").foregroundStyle(style.soft).monospacedDigit()
                    Spacer()
                    Menu { Picker("Sort by", selection: $model.sort) { ForEach(SortBy.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline) } label: { Text(model.sort.rawValue) }.menuStyle(.button).buttonStyle(.plain).fixedSize().foregroundStyle(style.accent).accessibilityLabel("Sort by \(model.sort.rawValue)")
                }
                if list.isEmpty && !(model.converting && model.section == .all) { blank }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 156, maximum: 200), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                    if model.converting && model.section == .all && model.search.isEmpty { ArrivingTile() }
                    ForEach(list) { Tile(game: $0, deleting: $deleting) }
                }
            }.padding(22)
        }
    }
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
        default: return "Drop a game in this window to add it."
        }
    }
}

struct Tile: View {
    @EnvironmentObject var model: Model
    let game: Game
    @Binding var deleting: Game?
    var body: some View {
        let e = model.library.entry(game.titleID)
        let note = model.isRunning(game) ? "Playing now" : game.cannot != nil ? game.cannot! : e.lastPlayed != nil ? lastPlayedText(e.lastPlayed) : game.rom == nil ? "Version \(game.version)" : consoleName(consoleOf(game.titleID))
        Group {
            if model.look == .covers { CoverTile(game: game, art: model.cover(game), favorite: e.favorite, running: model.isRunning(game), note: note, chosen: model.selected == game.id, select: { model.select(game) }, play: { model.play(game) }) { AnyView(GameActions(game: game, deleting: $deleting)) } }
            else { GameTile(game: game, icon: model.icon(game), favorite: e.favorite, running: model.isRunning(game), note: note, chosen: model.selected == game.id, select: { model.select(game) }, play: { model.play(game) }) { AnyView(GameActions(game: game, deleting: $deleting)) } }
        }.onDrop(of: [.fileURL], isTargeted: nil) { loadDropped($0) { model.dropped($0, on: game) }; return true }
    }
}

struct GameActions: View {
    @EnvironmentObject var model: Model
    let game: Game
    @Binding var deleting: Game?
    var body: some View {
        let e = model.library.entry(game.titleID)
        Button("Play") { model.play(game) }
        if game.rom == nil { Button("Play with Settings…") { model.play(game, settings: true) } }
        Divider()
        Button(e.favorite ? "Remove from Favorites" : "Favorite") { model.edit(game) { $0.favorite.toggle() } }
        Menu("Progress") { ForEach(Entry.Status.allCases, id: \.self) { s in Toggle(s.rawValue, isOn: .init(get: { e.status == s }, set: { if $0 { model.edit(game) { $0.status = s } } })) } }
        Menu("Collections") {
            ForEach(model.library.collections, id: \.self) { c in Toggle(c, isOn: .init(get: { e.collections.contains(c) }, set: { on in model.edit(game) { on ? $0.collections.append(c) : $0.collections.removeAll { $0 == c } } })) }
            if !model.library.collections.isEmpty { Divider() }
            Button("New Collection…") { model.collecting = game }
        }
        Divider()
        if game.rom == nil { Button("Add Update or DLC…") { model.addTo(game) }; Button("Move to Folder…") { model.moveGame(game) } }
        else { Button("Rename…") { model.retitling = game } }
        Button("Choose Cover…") { model.pickArt(game) }; if model.hasArt(game) { Button("Use Original Cover") { model.clearArt(game) } }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([game.url]) }
        Divider()
        if game.rom == nil { Button("Clean Up…") { model.cleanUp(game) }; Button("Move Game to Trash…") { deleting = game } }
        else { Button("Remove from Library") { model.removeRom(game) } }
    }
}
