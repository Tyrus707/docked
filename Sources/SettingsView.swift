import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var builder: Builder
    @Environment(\.dismiss) var dismiss
    enum Tab: String, CaseIterable { case general = "General", converting = "Converting", tools = "Setup" }
    @State private var tab = Tab.general
    private let phoneGames = xcodeGames()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Settings").font(.title2.weight(.semibold)); Spacer(); Text("Docked \(appVersion)").font(.callout).foregroundStyle(.secondary) }
            Picker("Section", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            Group { switch tab { case .general: general; case .converting: converting; case .tools: tools } }.frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
            HStack { Button("How to Use Docked") { model.leaveSettings { model.showHelp = true } }; Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).tint(style.button) }
        }.padding(24).frame(width: 520).background(AllowQuit()).background(Backdrop())
    }
    func line<C: View>(_ t: String, _ d: String, @ViewBuilder _ c: () -> C) -> some View { HStack(alignment: .center, spacing: 14) { VStack(alignment: .leading, spacing: 1) { Text(t); if !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }; Spacer(); c() } }
    func flip(_ t: String, _ d: String, _ b: Binding<Bool>) -> some View { line(t, d) { Toggle(t, isOn: b).labelsHidden().toggleStyle(.switch).tint(style.button) } }
    @ViewBuilder var general: some View {
        VStack(spacing: 14) {
            line("Show games as", "") { Picker("Show games as", selection: $model.look) { Text("Covers").tag(Look.covers); Text("Icons").tag(Look.icons) }.pickerStyle(.segmented).labelsHidden().fixedSize() }
            flip("Open in full screen", "From the next time Docked opens.", $model.fullScreen)
            flip("Theme music", "Plays a game's own theme while it is selected.", $model.themes)
            flip("Check for updates at launch", "Asks GitHub for the newest version number. Nothing else is sent.", $model.updatesAtLaunch)
            line("Updates", "") { if model.checkingUpdate { ProgressView().controlSize(.small) }; Button("Check Now") { model.leaveSettings { model.lookForUpdate() } }.disabled(model.checkingUpdate) }
        }
    }
    @ViewBuilder var converting: some View {
        VStack(spacing: 14) {
            line("Keys file", findKeys(model.keys).map { ($0 as NSString).lastPathComponent } ?? "Not chosen. Needed for .nsp, .xci, .nsz and .xcz games.") { Button(findKeys(model.keys) == nil ? "Choose…" : "Change…") { _ = model.pickKeys() } }
            line("New games go to", model.destination.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) { Button("Change…") { if let u = model.pickFolder(model.destination) { model.destination = u } } }
            line("When a game is done", "You can change this for each game.") { Picker("When a game is done", selection: $model.after) { ForEach(After.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().fixedSize() }
            flip("Skip the pipeline step", "Faster to convert, slower to start the first time.", $model.quick)
            if !phoneGames.isEmpty { line("Games for iPhone and iPad", phoneGames.map(\.name).joined(separator: ", ")) { Button("Open Steps…") { model.leaveSettings { model.showXcode = true } } } }
            line("Space", "Leftovers, original files and keys you no longer need.") { Button("Clean Up…") { model.leaveSettings { model.cleanUp(nil) } } }
        }
    }
    @ViewBuilder var tools: some View {
        VStack(spacing: 14) {
            line("This Mac", cannotConvert() ?? (model.ready ? "Ready to convert Switch games." : model.checks.isEmpty ? "Checking…" : "\(model.checks.filter { !$0.ok }.count) to do: \(nextCheck(model.checks)?.title ?? "")")) { Button("Details…") { model.leaveSettings { model.recheck(); model.showSetup = true } } }
            line("Setup guide", "One step at a time, from the beginning.") { Button("Open Guide…") { model.leaveSettings { model.recheck(); model.showGuide = true } } }
            line("Other consoles", RetroArch.installed ? "RetroArch is installed." : "RetroArch is not installed.") { Button("Consoles…") { model.leaveSettings { model.showConsoles = true } } }
            line("Games folder", "") { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.games]) } }
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
