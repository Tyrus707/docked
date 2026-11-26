import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var builder: Builder
    @Environment(\.dismiss) var dismiss
    enum Tab: String, CaseIterable { case general = "General", library = "Library", converting = "Converting", tools = "Setup" }
    @State private var tab = Tab.general
    private let phoneGames = xcodeGames()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Settings").font(.title2.weight(.semibold)); Spacer(); Text("Docked \(appVersion)").font(.callout).foregroundStyle(.secondary) }
            Picker("Section", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            Group { switch tab { case .general: general; case .library: library; case .converting: converting; case .tools: tools } }.frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
            HStack { Button("How to Use Docked") { model.leaveSettings { model.showHelp = true } }; Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).tint(style.button) }
        }.padding(24).frame(width: 520).background(AllowQuit()).background(Backdrop())
    }
    func line<C: View>(_ t: String, _ d: String, @ViewBuilder _ c: () -> C) -> some View { HStack(alignment: .center, spacing: 14) { VStack(alignment: .leading, spacing: 1) { Text(t); if !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }; Spacer(); c() } }
    func flip(_ t: String, _ d: String, _ b: Binding<Bool>) -> some View { line(t, d) { Toggle(t, isOn: b).labelsHidden().toggleStyle(.switch).tint(style.button) } }
    @ViewBuilder var general: some View {
        VStack(spacing: 14) {
            line("Theme", "Docked keeps its own look, whatever your Mac's light or dark setting.") {
                HStack(spacing: 8) { ForEach(Style.all) { t in ThemeSwatch(theme: t, on: model.palette == t) { model.palette = t } } }
            }
            line("Show games as", "") { Picker("Show games as", selection: $model.look) { Text("Covers").tag(Look.covers); Text("Icons").tag(Look.icons) }.pickerStyle(.segmented).labelsHidden().fixedSize() }
            flip("Open filling the screen", "A window as big as the screen, without a separate Space. From the next time Docked opens.", $model.fullScreen)
            flip("Play other consoles full screen", "Retro games fill the whole screen. Off: a window as big as the screen. Press F in a game to switch.", .init(get: { RetroArch.fullScreen }, set: { RetroArch.fullScreen = $0; model.objectWillChange.send() }))
            flip("Step aside while playing", "Docked hides when a game starts and comes back when it closes.", $model.hideWhilePlaying)
            flip("Theme music", "Plays a game's own theme while it is selected.", $model.themes)
            flip("Couch Mode sounds", "Soft clicks and chimes as you move around Couch Mode.", $model.couchSounds)
            flip("Find covers and details", "Covers and descriptions for games from other consoles, Switch banners in Couch Mode, and critic scores, popularity, year and genre for every game. Your files are matched on this Mac; libretro, Wikidata and Wikipedia see only a game's name, the banner service only its title ID.", .init(get: { model.lookUp == true }, set: { model.lookUp = $0; if $0 { model.lookUpAll(); model.findMetaAll() } }))
            line("Game details", model.scoring.isEmpty ? "Looks up every game not checked in the last month, a couple of seconds each, while you use Docked." : "Finding details, \(model.scoring.count) to go…") {
                if !model.scoring.isEmpty { ProgressView().controlSize(.small) }
                Button("Find for All Games") { model.lookUpAll(); model.findMetaAll() }.disabled(model.lookUp != true || !model.scoring.isEmpty)
            }
            flip("Check for updates at launch", "Asks GitHub for the newest version numbers of Docked and its engine. Nothing else is sent.", $model.updatesAtLaunch)
            line("Updates", "") { if model.checkingUpdate { ProgressView().controlSize(.small) }; Button("Check Now") { model.leaveSettings { model.lookForUpdate() } }.disabled(model.checkingUpdate) }
        }
    }
    @ViewBuilder var converting: some View {
        VStack(spacing: 14) {
            line("Keys file", findKeys(model.keys).map { ($0 as NSString).lastPathComponent } ?? "Not chosen. Needed for .nsp, .xci, .nsz and .xcz games.") { Button(findKeys(model.keys) == nil ? "Choose…" : "Change…") { _ = model.pickKeys() } }
            if model.organized { line("New games go to", "The Switch folder in your library. Change it under Library.") { Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([model.consoleFolder("switch")]) } } }
            else { line("New games go to", model.destination.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) { Button("Change…") { if let u = model.pickFolder(model.destination) { model.destination = u } } } }
            flip("Find details when a game is done", "Critic score, popularity, year and genre from Wikidata and Wikipedia, which see only the game's name.", .init(get: { model.lookUp == true && model.metaConverted ?? true }, set: { model.metaConverted = $0; if $0, model.lookUp != true { model.lookUp = true } }))
            line("When a game is done", "You can change this for each game.") { Picker("When a game is done", selection: $model.after) { ForEach(After.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().fixedSize() }
            flip("Skip the pipeline step", "Faster to convert, slower to start the first time.", $model.quick)
            line("How much of your Mac can converting use?", "\(conversionEffortNote(model.effort)) Lower means a slower conversion, but more room for games. The finished game is the same. Changes apply to games added after this.") {
                HStack(spacing: 8) {
                    Slider(value: model.effortSlider, in: 0.1...1, step: 0.05).frame(width: 150)
                    Text("\(model.effort)%").font(.caption).monospacedDigit().frame(width: 34, alignment: .trailing)
                }
            }
            if !phoneGames.isEmpty { line("Games for iPhone and iPad", phoneGames.map(\.name).joined(separator: ", ")) { Button("Open Steps…") { model.leaveSettings { model.showXcode = true } } } }
            line("Space", "Leftovers, original files and keys you no longer need.") { Button("Clean Up…") { model.leaveSettings { model.cleanUp(nil) } } }
        }
    }
    // The engine that converts games: newer ones come signed by Docked's maker, and the one before is kept
    @ViewBuilder var engineRows: some View {
        let now = Engine.active
        line("Conversion engine", now.map { e in "From \(engineDay(e.date)), version \(e.commit.prefix(8))." + (model.engine.map { n in " A newer one is ready. \(n.summary)" } ?? "") } ?? "Comes with the conversion tools.") {
            if model.checkingEngine || model.engineBusy { ProgressView().controlSize(.small) }
            if model.engine != nil { Button("Update Engine") { model.leaveSettings { model.installEngine() } }.disabled(model.engineBusy) }
            else { Button("Check Now") { model.leaveSettings { model.lookForEngine() } }.disabled(now == nil || model.checkingEngine || model.engineBusy) }
        }
        if now != nil, let p = Engine.installed(Engine.previous) { line("Kept engine", "From \(engineDay(p.date)). Switch to it if a game converts worse with the one in use. You can switch back.") { Button("Switch") { model.leaveSettings { model.engineBack() } }.disabled(model.engineBusy) } }
    }
    @ViewBuilder var tools: some View {
        VStack(spacing: 14) {
            line("This Mac", cannotConvert() ?? (model.ready ? "Ready to convert Switch games." : model.checks.isEmpty ? "Checking…" : "\(model.checks.filter { !$0.ok }.count) to do: \(nextCheck(model.checks)?.title ?? "")")) { Button("Details…") { model.leaveSettings { model.recheck(); model.showSetup = true } } }
            if model.carriesEngine { engineRows }
            line("Setup guide", "One step at a time, from the beginning.") { Button("Open Guide…") { model.leaveSettings { model.recheck(); model.showGuide = true } } }
            line("Other consoles", RetroArch.installed ? "RetroArch \(RetroArch.installedVersion ?? "") is set up inside Docked." : "Docked sets up RetroArch the first time you add one of their games.") { Button("Consoles…") { model.leaveSettings { model.showConsoles = true } } }
            line("Docked's folder", "Its tools, RetroArch, covers and leftovers.") { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.root]) } }
        }
    }
}

// A game has arrived: its cover comes down, and what comes next is right there.
struct FinishCard: View {
    @EnvironmentObject var model: Model
    let game: Game
    var more = 0
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        HStack(spacing: 18) {
            Group { if let c = model.cover(game) { Image(nsImage: c).resizable() } else { Rectangle().fill(style.tile) } }.aspectRatio(Cover.shape, contentMode: .fit).frame(height: 104).clipShape(RoundedRectangle(cornerRadius: 9)).offset(y: landed || still ? 0 : -46).opacity(landed || still ? 1 : 0).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(game.name) is ready").font(.title3.weight(.semibold)).foregroundStyle(style.text).lineLimit(2)
                Text(more > 0 ? "\(more) more \(more == 1 ? "game is" : "games are") ready too." : "Try it, then remove what's left over to save space.").font(.callout).foregroundStyle(style.soft)
                HStack(spacing: 8) {
                    Button { model.offers.removeAll { $0.id == game.id }; model.play(game) } label: { Label("Play Now", systemImage: "play.fill").font(.body.weight(.semibold)) }.buttonStyle(.borderedProminent).tint(style.button)
                    Button("Clean Up…") { model.cleanUp(game) }
                    Button("Not Now") { model.offers.removeAll { $0.id == game.id } }
                }.padding(.top, 4)
            }
        }
        .padding(18).background { RoundedRectangle(cornerRadius: 18).fill(style.tile).shadow(color: .black.opacity(0.4), radius: 22, y: 8) }.overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(style.line, lineWidth: 1) }.frame(maxWidth: 560)
        .onAppear { if still { landed = true } else { withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.18)) { landed = true } } }
        .accessibilityElement(children: .contain)
    }
}

// One theme to pick: its window colours, with its accent and button
struct ThemeSwatch: View {
    let theme: Style, on: Bool, pick: () -> Void
    var body: some View {
        Button(action: pick) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [theme.top, theme.bottom], startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .bottomLeading) { HStack(spacing: 3) { Capsule().fill(theme.button).frame(width: 16, height: 6); Circle().fill(theme.accent).frame(width: 6, height: 6) }.padding(6) }
                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(on ? style.accent : theme.line, lineWidth: on ? 2.5 : 1) }
                    .frame(width: 52, height: 34)
                Text(theme.name).font(.caption).foregroundStyle(on ? style.text : style.soft)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(theme.name) theme").accessibilityAddTraits(on ? .isSelected : []).help(theme.name)
    }
}
