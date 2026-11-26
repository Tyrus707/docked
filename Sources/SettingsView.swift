import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var builder: Builder
    @Environment(\.dismiss) var dismiss
    enum Tab: String, CaseIterable { case general = "General", library = "Library", converting = "Converting", retro = "Retro", friends = "Friends", tools = "Setup" }
    static var start = Tab.general   // set just before opening, to land on one tab
    @State private var tab = SettingsSheet.start
    private let phoneGames = xcodeGames()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Settings").font(.title2.weight(.semibold)); Spacer(); Text("Docked \(appVersion)").font(.callout).foregroundStyle(.secondary) }
            Picker("Section", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                Group { switch tab { case .general: general; case .library: library; case .converting: converting; case .retro: RetroSettings(); case .friends: FriendsSettings(); case .tools: tools } }
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(.leading, 2).padding(.trailing, 14).padding(.vertical, 4)
            }.frame(height: 470)
            Divider()
            HStack { Button("How to Use Docked") { model.leaveSettings { model.showHelp = true } }; Button("Release Notes") { model.leaveSettings { model.showReleaseNotes = true } }; Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).tint(style.button) }
        }.padding(24).frame(width: 660).background(AllowQuit()).background(Backdrop())
    }
    func line<C: View>(_ t: String, _ d: String, @ViewBuilder _ c: () -> C) -> some View { settingsRow(t, d, c) }
    func flip(_ t: String, _ d: String, _ b: Binding<Bool>) -> some View { line(t, d) { Toggle(t, isOn: b).labelsHidden().toggleStyle(.switch).tint(style.button) } }
    @ViewBuilder var general: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) { Text("Theme"); Text("Docked keeps its own look, whatever your Mac's light or dark setting.").font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 12), count: 6), alignment: .leading, spacing: 12) { ForEach(Style.all) { t in ThemeSwatch(theme: t, on: model.palette == t) { model.palette = t } } }.fixedSize()
            }.frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            line("Show games as", "") { Picker("Show games as", selection: $model.look) { Text("Covers").tag(Look.covers); Text("Icons").tag(Look.icons) }.pickerStyle(.segmented).labelsHidden().fixedSize() }
            flip("Open filling the screen", "A window as big as the screen, without a separate Space. From the next time Docked opens.", $model.fullScreen)
            flip("Play other consoles full screen", "Retro games fill the whole screen. Off: a window as big as the screen. Press F in a game to switch.", .init(get: { RetroArch.fullScreen }, set: { RetroArch.fullScreen = $0; model.objectWillChange.send() }))
            flip("Show games in Spotlight", "Type a game's name in Spotlight to play it. Each game's ••• menu also has a link for Shortcuts.", $model.spotlight)
            flip("Step aside while playing", "Docked hides when a game starts and comes back when it closes.", $model.hideWhilePlaying)
            flip("Theme music", "Plays a game's own theme while it is selected.", $model.themes)
            flip("Couch Mode sounds", "Soft clicks and chimes as you move around Couch Mode.", $model.couchSounds)
            flip("Find covers and details", "Covers and descriptions for games from other consoles, Switch banners in Couch Mode, and critic scores, popularity, year and genre for every game. Your files are matched on this Mac; libretro sees only a game's name, Wikidata a name and any chosen item ID, Wikipedia the article title for reader counts, and the banner service only the title ID.", .init(get: { model.lookUp == true }, set: { model.lookUp = $0; if $0 { model.lookUpAll(); model.findMetaAll() } }))
            line("Game details", model.scoring.isEmpty ? "Looks up every game not checked in the last month, a couple of seconds each, while you use Docked." : "Finding details, \(model.scoring.count) to go…") {
                if !model.scoring.isEmpty { ProgressView().controlSize(.small) }
                Button("Find for All Games") { model.lookUpAll(); model.findMetaAll() }.disabled(model.lookUp != true || !model.scoring.isEmpty)
            }
            Divider()
            line("Updates", "Asks GitHub for the newest version numbers of Docked and its engine. Nothing else is sent.") { if model.checkingUpdate { ProgressView().controlSize(.small) }; Button("Check Now") { model.leaveSettings { model.lookForUpdate() } }.disabled(model.checkingUpdate) }
            flip("Check for updates at launch", "", $model.updatesAtLaunch)
        }
    }
    @ViewBuilder var converting: some View {
        VStack(spacing: 14) {
            line("Keys file", findKeys(model.keys).map { ($0 as NSString).lastPathComponent } ?? "Not chosen. Needed for .nsp, .xci, .nsz and .xcz games.") { Button(findKeys(model.keys) == nil ? "Choose…" : "Change…") { _ = model.pickKeys() } }
            if model.organized { line("New games go to", "Their console's folder in your library, automatically. Choose a folder of your own only if you want to.") { HStack { Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([model.consoleFolder("switch")]) }; Button("Choose…") { if let u = model.pickFolder(model.destination) { model.destination = u; model.organized = false } } } } }
            else { line("New games go to", model.destination.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) { Button("Change…") { if let u = model.pickFolder(model.destination) { model.destination = u } } } }
            flip("Find details when a game is done", "Critic score, popularity, year and genre from Wikidata and Wikipedia, which see the game's name, its Wikidata ID and its Wikipedia article title.", .init(get: { model.lookUp == true && model.metaConverted ?? true }, set: { model.metaConverted = $0; if $0, model.lookUp != true { model.lookUp = true } }))
            line("When a game is done", "You can change this for each game.") { Picker("When a game is done", selection: $model.after) { ForEach(After.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().fixedSize() }
            flip("Skip the pipeline step", "Faster to convert, slower to start the first time.", $model.quick)
            line("Conversion speed", model.speed.note + " The finished game is the same. Applies to games added after this.") { Picker("Conversion speed", selection: $model.speed) { ForEach(Speed.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().fixedSize() }
            line("Convert", model.convertWhen.note) { Picker("Convert", selection: $model.convertWhen) { ForEach(ConvertWhen.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().fixedSize() }
            if !phoneGames.isEmpty { line("Games for iPhone and iPad", phoneGames.map(\.name).joined(separator: ", ")) { Button("Open Steps…") { model.leaveSettings { model.showXcode = true } } } }
            line("Cloud saves", model.cloudSaves.isEmpty ? "Off. Choose a folder in iCloud Drive to carry your Switch saves between Macs and an iPhone or iPad." : "Every converted game syncs its save through \((model.cloudSaves as NSString).lastPathComponent). It starts with the newer save.") {
                if !model.cloudSaves.isEmpty { Button("Turn Off") { model.cloudSaves = "" } }
                Button(model.cloudSaves.isEmpty ? "Choose Folder…" : "Change…") { model.pickCloudSaves() }
            }
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
/// One Settings row: title and description on the left, wrapping to fit; the control on the right at its natural size.
func settingsRow<C: View>(_ t: String, _ d: String, _ c: () -> C) -> some View {
    HStack(alignment: .center, spacing: 20) {
        VStack(alignment: .leading, spacing: 2) { Text(t); if !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }
            .frame(maxWidth: .infinity, alignment: .leading)
        c().fixedSize()
    }
}

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

// Other consoles: RetroAchievements, retro looks and controllers
struct RetroSettings: View {
    @EnvironmentObject var model: Model
    @State private var user = ""
    @State private var password = ""
    @State private var key = ""
    @State private var busy = false
    @State private var note: String?
    @State private var pads = Pads.installed
    func line<C: View>(_ t: String, _ d: String, @ViewBuilder _ c: () -> C) -> some View { settingsRow(t, d, c) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let u = Cheevos.user, Cheevos.signedIn {
                line("RetroAchievements", "Signed in as \(u). Unlocks pop up while you play.") { Button("Sign Out") { Cheevos.signOut(); CheevoStore.shared.forget(); model.objectWillChange.send() } }
                line("Hardcore", "No save states, rewind or cheats, and unlocks count as hardcore. From the next game you start.") { Toggle("Hardcore", isOn: .init(get: { Cheevos.hardcore }, set: { Cheevos.hardcore = $0; model.objectWillChange.send() })).labelsHidden().toggleStyle(.switch).tint(style.button) }
                line("Progress in Docked", Cheevos.hasWebKey ? "On each game's page, on its tile, and under Achievements in the sidebar." : "Paste the Web API key from your RetroAchievements settings page to see your achievements in Docked.") {
                    if Cheevos.hasWebKey { Button("Refresh") { model.refreshCheevos(force: true) } }
                    else { SecureField("Web API key", text: $key).frame(width: 150); Button("Save") { Cheevos.setWebKey(key); key = ""; CheevoStore.shared.recheck(); model.refreshCheevos(force: true) }.disabled(key.isEmpty) }
                }
            } else {
                line("RetroAchievements", "Earn achievements in retro games with your free retroachievements.org account. Docked keeps only a sign-in token, in your Keychain.") { Button("Create Account…") { NSWorkspace.shared.open(URL(string: "https://retroachievements.org/createaccount")!) } }
                HStack(spacing: 8) {
                    TextField("User name", text: $user); SecureField("Password", text: $password); SecureField("Web API key (optional)", text: $key)
                    if busy { ProgressView().controlSize(.small) }
                    Button("Sign In") { signIn() }.disabled(busy || user.isEmpty || password.isEmpty)
                }.textFieldStyle(.roundedBorder)
            }
            if let note { Text(note).font(.caption).foregroundStyle(style.warn) }
            Divider()
            Text("Retro looks").font(.callout.weight(.semibold))
            Text("A filter over the picture for each console. A game can have its own in its details.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(consoles.filter { !$0.native }) { c in
                        HStack { Text(c.name); Spacer(); Picker(c.name, selection: .init(get: { Shaders.look(console: c.id) }, set: { Shaders.setLook($0, console: c.id); model.objectWillChange.send() })) { ForEach(RetroLook.allCases) { Text($0.label).tag($0) } }.labelsHidden().fixedSize() }
                    }
                }.padding(.trailing, 6)
            }.frame(height: 130)
            Divider()
            line("Controllers", pads ? "Most game pads work as soon as they are plugged in, using libretro's controller profiles." : "Docked downloads libretro's controller profiles with your first retro game, so most pads work without setup.") {
                if !pads { Button("Download Now") { busy = true; DispatchQueue.global(qos: .userInitiated).async { let ok = (try? Pads.install()) != nil; DispatchQueue.main.async { busy = false; pads = Pads.installed; if !ok { note = "The controller profiles couldn't be downloaded. Check your connection." } } } }.disabled(busy) }
            }
        }
    }
    func signIn() {
        busy = true; note = nil; let (u, p, k) = (user, password, key)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try Cheevos.signIn(user: u, password: p, webKey: k) }
            DispatchQueue.main.async {
                busy = false; password = ""
                switch r { case .success: key = ""; CheevoStore.shared.recheck(); model.objectWillChange.send(); model.refreshCheevos(force: true); case .failure(let e): note = e.localizedDescription }
            }
        }
    }
}

struct FriendsSettings: View {
    @EnvironmentObject var model: Model
    @State private var ready = Friends.ready
    @State private var airDrop = UserDefaults.standard.string(forKey: "friends.airDrop") ?? ""
    @State private var share: URL?   // a copy made once, for AirDrop, Messages or Mail
    @State private var note: String?
    @State private var choosing = false
    func line<C: View>(_ t: String, _ d: String, @ViewBuilder _ c: () -> C) -> some View { settingsRow(t, d, c) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            line("Friends circle", ready ? "Connected through \(Friends.meetingPoint ?? "your meeting point"). To add friends, open a game's Friends screen (Friends menu, or click both sticks) and swap codes." : "Play local wireless games with friends over the internet. Add the friends pass you were sent: AirDrop and Messages save it to Downloads.") {
                Button(ready ? "Replace Pass…" : "Add Friends Pass…") { pick() }
                if ready, let u = share { ShareLink("Send to a Friend…", item: u) }
            }
            if let note { Text(note).font(.caption).foregroundStyle(.red) }
            line("Multiplayer for older games", "For a game converted before multiplayer: converts it again, then turns Play with friends on. Its save stays, but this takes a while.") {
                Button("Add Multiplayer to Game…") { choosing = true }
            }
            line("In each game", "Turn on Play with friends in a game's Game Settings, then start its local wireless mode. For an older game, use Add Multiplayer here or the button in its Game Settings.") { EmptyView() }
            line("For smooth play", "Ethernet plays best. On Wi-Fi, let Docked pause AirDrop while you play. A slower Mac slows both players, so set its Upscaling to Standard. Keep Connection smoothing off for fighting and racing games.") { EmptyView() }
            line("Pause AirDrop on Wi-Fi", "Keeps Wi-Fi on your network during friends games. Asks for your password each time.") {
                Picker("Pause AirDrop on Wi-Fi", selection: $airDrop) { Text("Ask").tag(""); Text("Always").tag("pause"); Text("Never").tag("leave") }.labelsHidden().fixedSize()
                    .onChange(of: airDrop) { v in if v.isEmpty { UserDefaults.standard.removeObject(forKey: "friends.airDrop") } else { UserDefaults.standard.set(v, forKey: "friends.airDrop") } }
            }
            line("Start your own circle", "Run Friends/meeting/setup_meeting.py once with a Cloudflare token. It sets up a free meeting point and saves your pass here. Share the pass only with friends you trust.") {
                Button("How…") { NSWorkspace.shared.open(URL(string: "https://github.com/Tyrus707/docked/blob/main/Friends/README.md")!) }
            }
            Text("Friends you play with can see your internet address, as in any direct online game.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { Friends.adoptOlder(); ready = Friends.ready; share = Friends.shareable() }
        .sheet(isPresented: $choosing) { FriendsGamePicker() }
    }
    func pick() {
        let p = NSOpenPanel(); p.canChooseDirectories = false; p.allowsMultipleSelection = false; p.message = "Choose the friends pass (friends.cfg) you were sent."; p.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first   // where AirDrop and Messages put it
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try Friends.use(u); note = nil } catch { note = error.localizedDescription }
        ready = Friends.ready; share = Friends.shareable()
    }
}

// Pick an older Switch game to convert again with the friends switch added.
struct FriendsGamePicker: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss
    private var games: [Game] { model.games.filter { $0.rom == nil && !$0.missing && $0.away == nil && !Friends.supported($0.url) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Multiplayer to Game").font(.title2.weight(.semibold))
            Text("Choose a Switch game converted before multiplayer. Docked converts it again, then turns on Play with friends. Its save stays. If Docked can't find the originals, check the Trash before emptying it, or add the game file again; links in Docked's Inputs folder need the original file.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                if games.isEmpty {
                    Text("Every converted game here already has multiplayer. Turn on Play with friends in a game's Game Settings.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                } else {
                    ForEach(games) { g in
                        Button { choose(g) } label: { HStack { Text(g.name).foregroundStyle(style.text); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) } }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }.frame(minHeight: 120, maxHeight: 300)
            HStack { Spacer(); Button("Cancel") { dismiss() } }
        }.padding(24).frame(width: 480).background(Backdrop())
    }
    func choose(_ g: Game) {
        dismiss()
        model.leaveSettings { model.reconvertForFriends(g) }
    }
}
