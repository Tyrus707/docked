import SwiftUI

// What is known about the chosen game, and everything that can be done with it. Beside the library when there is room, over it when there is not.
struct Inspector: View {
    @EnvironmentObject var model: Model
    let game: Game
    @Binding var deleting: Game?
    var body: some View {
        let e = model.library.entry(game.titleID)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Spacer(); Button { model.selected = nil } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(style.soft).frame(width: 26, height: 26).contentShape(Rectangle()) }.buttonStyle(.plain).help("Close").accessibilityLabel("Close details") }.padding(.bottom, -14)
                    Group { if let c = model.cover(game) { Image(nsImage: c).resizable() } else { Rectangle().fill(style.tile) } }
                        .aspectRatio(Cover.shape, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12)).frame(maxWidth: 190).frame(maxWidth: .infinity).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.name).font(.title3.weight(.semibold)).foregroundStyle(style.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Text(([consoleName(consoleOf(game.titleID)) + (game.rom == nil && !game.version.isEmpty ? ", version \(game.version)" : "")] + [game.rom?.info?.year.map(String.init)].compactMap { $0 }).joined(separator: " · ")).font(.callout).foregroundStyle(style.soft)
                    }
                    if game.missing { VStack(alignment: .leading, spacing: 8) { Label(drive(of: game.url.path).map { !$0.connected ? "On \($0.name). Connect the drive to play." : "Can't be found where it was." } ?? "Can't be found where it was.", systemImage: drive(of: game.url.path) != nil ? "externaldrive.badge.xmark" : "questionmark.folder").font(.callout).foregroundStyle(style.text); HStack { Button("Locate…") { model.locate(game) }; Button("Remove from Library") { model.forget(game) } }.controlSize(.small) }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(style.tile, in: RoundedRectangle(cornerRadius: 10)) }
                    else if let why = game.cannot { Label(why, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(style.warn) }
                    HStack(spacing: 8) {
                        Button { model.play(game) } label: { Label(model.isRunning(game) ? "Show" : "Play", systemImage: "play.fill").font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 24) }.buttonStyle(.borderedProminent).tint(style.button).controlSize(.large).keyboardShortcut(.return, modifiers: .command).help("Play (Command-Return)")
                        Button { model.edit(game) { $0.favorite.toggle() } } label: { Image(systemName: e.favorite ? "heart.fill" : "heart").foregroundStyle(e.favorite ? style.accent : style.text).frame(width: 18, height: 24) }.controlSize(.large).help(e.favorite ? "Remove from Favorites" : "Favorite").accessibilityLabel(e.favorite ? "Remove from Favorites" : "Favorite")
                        Menu { GameActions(game: game, deleting: $deleting) } label: { Image(systemName: "ellipsis").frame(width: 18, height: 24) }.menuStyle(.button).buttonStyle(.bordered).menuIndicator(.hidden).fixedSize().controlSize(.large).help("More").accessibilityLabel("More")
                    }
                    Stars(rating: e.rating) { n in model.edit(game) { $0.rating = $0.rating == n ? 0 : n } }
                    Picker("Progress", selection: .init(get: { e.status }, set: { v in model.edit(game) { $0.status = v } })) { ForEach(Entry.Status.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    VStack(alignment: .leading, spacing: 9) {
                        fact("Played", playTimeText(e.seconds)); if e.plays > 0 { fact("Times played", "\(e.plays)") }; fact("Last played", e.lastPlayed == nil ? "Never" : lastPlayedText(e.lastPlayed).replacingOccurrences(of: "Played ", with: "").firstCapital); if e.added > .distantPast { fact("Added", e.added.formatted(date: .abbreviated, time: .omitted)) }
                        fact("Size", game.missing ? "Not available" : model.size(game).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Measuring…"); if let r = game.rom { fact("Plays in", RetroArch.core(console(r.console) ?? consoles[0]) == nil ? "RetroArch, set up when you first play" : "RetroArch") }
                        fact("In", (drive(of: game.url.path).map { "\($0.name), " } ?? "") + FileManager.default.displayName(atPath: game.url.deletingLastPathComponent().path)); if !e.collections.isEmpty { fact("Collections", e.collections.joined(separator: ", ")) }
                        if let i = game.rom?.info { if let d = i.developer { fact("Made by", d) }; if let p = i.publisher, p != i.developer { fact("Published by", p) }; if let g = i.genre { fact("Genre", g) } }
                    }.padding(12).background(style.tile, in: RoundedRectangle(cornerRadius: 10))
                    if let i = game.rom?.info { GameAbout(info: i) }
                    if game.rom == nil, FileManager.default.fileExists(atPath: GameNotes.file(game.titleID).path) {
                        let notes = model.notes(game)
                        VStack(alignment: .leading, spacing: 7) {
                            if !notes.isEmpty { Text("Known issues").font(.callout.weight(.semibold)).foregroundStyle(style.text).accessibilityAddTraits(.isHeader); ForEach(notes, id: \.self) { n in HStack(alignment: .firstTextBaseline, spacing: 7) { Circle().fill(style.accent).frame(width: 4, height: 4).offset(y: -3).accessibilityHidden(true); Text(n).font(.caption).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) } } }
                            Button(notes.isEmpty ? "Engine notes for this game" : "All engine notes") { NSWorkspace.shared.open(GameNotes.page(game.titleID)) }.buttonStyle(.plain).font(.caption).foregroundStyle(style.accent)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        link("Choose Cover…", "photo") { model.pickArt(game) }
                        if let r = game.rom { if model.finding.contains(r.id) { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Finding details…").font(.callout).foregroundStyle(style.soft) } } else { link(r.info == nil ? "Find Cover and Details…" : "Wrong Game? Find Again…", "magnifyingglass") { model.find(r.id, byHand: true) } } }
                        if model.addingTheme { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Adding music…").font(.callout).foregroundStyle(style.soft) } }
                        else if model.hasTheme(game) { link("Change Theme Music…", "music.note") { model.pickTheme(game) }; link("Remove Theme Music", "minus.circle") { model.clearTheme(game) }; link(model.themes ? "Turn Theme Music Off" : "Turn Theme Music On", model.themes ? "speaker.slash" : "speaker.wave.2") { model.themes.toggle() } }
                        else { link("Choose Theme Music…", "music.note") { model.pickTheme(game) } }
                        if game.rom == nil { if !game.missing { link("Game Settings…", "slider.horizontal.3") { model.openSettings(game) } }; link("Play with Settings…", "play.circle") { model.play(game, settings: true) }; link("Add Update or DLC…", "plus.square.on.square") { model.addTo(game) }; link("Clean Up…", "sparkles") { model.cleanUp(game) } }
                        if !game.missing { link("Show in Finder", "folder") { NSWorkspace.shared.activateFileViewerSelecting([game.url]) } }
                    }
                }.padding(18)
            }
        }.frame(width: 280).frame(maxHeight: .infinity).background(style.bottom)
    }
    func fact(_ a: String, _ b: String) -> some View { HStack(alignment: .firstTextBaseline) { Text(a).foregroundStyle(style.soft); Spacer(minLength: 12); Text(b).foregroundStyle(style.text).multilineTextAlignment(.trailing) }.font(.callout).accessibilityElement(children: .combine) }
    func link(_ t: String, _ s: String, _ f: @escaping () -> Void) -> some View { Button(action: f) { Label(t, systemImage: s).font(.callout).foregroundStyle(style.accent).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain) }
}

// The player's own rating: click a star to set it, the same star again to clear it.
struct Stars: View {
    let rating: Int
    let set: (Int) -> Void
    var body: some View {
        HStack(spacing: 2) {
            Text("Rating").font(.callout).foregroundStyle(style.soft)
            Spacer()
            ForEach(1...5, id: \.self) { n in
                Button { set(n) } label: { Image(systemName: n <= rating ? "star.fill" : "star").font(.system(size: 14)).foregroundStyle(n <= rating ? style.accent : style.soft).frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help(n == rating ? "Clear rating" : "\(n) star\(n == 1 ? "" : "s")")
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Rating").accessibilityValue(rating == 0 ? "Not rated" : "\(rating) of 5 stars")
        .accessibilityAdjustableAction { d in switch d { case .increment: if rating < 5 { set(rating + 1) }; case .decrement: if rating > 0 { set(rating - 1) }; default: break } }
    }
}
