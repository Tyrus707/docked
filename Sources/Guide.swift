import SwiftUI

// Takes someone from a fresh download to a first game, one thing at a time. It watches for each step to be done and goes on by itself.
struct GuideView: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var step = GuideStep.welcome
    @State private var dropping = false
    @State private var copied = false
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    var steps: [GuideStep] { cannotConvert() == nil ? GuideStep.allCases : [.welcome, .games] }
    func go(_ by: Int) { if let i = steps.firstIndex(of: step), steps.indices.contains(i + by) { withAnimation(still ? nil : .easeOut(duration: 0.18)) { step = steps[i + by] } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 7) { ForEach(steps, id: \.self) { s in Capsule().fill(s == step ? style.accent : s.rawValue < step.rawValue ? style.accent.opacity(0.5) : style.line).frame(width: s == step ? 26 : 10, height: 6) }; Spacer() }.accessibilityElement(children: .ignore).accessibilityLabel("Step \((steps.firstIndex(of: step) ?? 0) + 1) of \(steps.count)")
            Text(step.title).font(.title.weight(.semibold)).foregroundStyle(style.text).accessibilityAddTraits(.isHeader)
            Group { switch step { case .welcome: welcome; case .tools: tools; case .keys: keys; case .games: games } }.frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
            HStack {
                Button(step == .welcome ? "Skip Guide" : "Back") { if step == .welcome { finish() } else { go(-1) } }
                Spacer()
                switch step {
                case .welcome: Button("Get Started") { go(1) }.keyboardShortcut(.defaultAction).tint(style.button)
                case .tools: if model.ready { Button("Continue") { go(1) }.keyboardShortcut(.defaultAction).tint(style.button) } else { Button("Do This Later") { go(1) } }
                case .keys: if keysOK { Button("Continue") { go(1) }.keyboardShortcut(.defaultAction).tint(style.button) } else { Button("Skip") { go(1) } }
                case .games: Button("Done") { finish() }.keyboardShortcut(.defaultAction).tint(style.button)
                }
            }
        }
        .padding(30).frame(width: 600).background(AllowQuit()).background(Backdrop())
        .onReceive(tick) { _ in if step == .tools, !model.ready, !model.checking, !model.installing, !model.fetching { model.recheck() } }
        .whenChanged(model.ready) { if model.ready, step == .tools { go(1) } }
    }
    func finish() { model.guided = true; dismiss() }
    func row(_ s: String, _ t: String, _ d: String) -> some View { HStack(alignment: .top, spacing: 14) { Image(systemName: s).font(.title2).foregroundStyle(style.accent).frame(width: 30).accessibilityHidden(true); VStack(alignment: .leading, spacing: 2) { Text(t).font(.headline).foregroundStyle(style.text); Text(d).font(.callout).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true) } }.accessibilityElement(children: .combine) }

    @ViewBuilder var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("wand.and.stars", "Convert", cannotConvert() ?? "Turn Switch games you own into Mac apps that run natively.")
            row("square.grid.2x2", "Collect", "Keep them beside your games for other consoles, which play in RetroArch.")
            row("lock", "Private", "Everything stays on this Mac. Docked only looks online for a new version.")
            Text("You need games and, for most of them, a keys file that you copied from your own Switch. Docked includes neither.").font(.callout).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder var tools: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Converting uses Apple's free developer tools. Docked checks each step and moves on by itself.").foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
            let now = nextCheck(model.checks)
            ForEach(model.checks) { c in
                HStack(spacing: 10) { Image(systemName: c.ok ? "checkmark.circle.fill" : c.id == now?.id ? "arrow.right.circle.fill" : "circle").foregroundStyle(c.ok ? Color(light: 0x1E7A3C, dark: 0x6FCF8A) : c.id == now?.id ? style.accent : style.line).accessibilityLabel(c.ok ? "Done" : "Not done"); Text(c.title).foregroundStyle(c.ok || c.id == now?.id ? style.text : style.soft); Spacer(); if c.ok { Text(c.detail).font(.caption).foregroundStyle(style.soft) } }
            }
            if let now { VStack(alignment: .leading, spacing: 8) { action(now) }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(style.tile, in: RoundedRectangle(cornerRadius: 10)) }
            else if model.checks.isEmpty { HStack { ProgressView().controlSize(.small); Text("Checking your Mac…").foregroundStyle(style.soft) } }
            else { Label("Your Mac is ready.", systemImage: "checkmark.seal.fill").foregroundStyle(Color(light: 0x1E7A3C, dark: 0x6FCF8A)) }
            if let p = model.installProblem { Text(p).font(.callout).foregroundStyle(Color(light: 0xB3261E, dark: 0xFF8A80)).fixedSize(horizontal: false, vertical: true) }
        }
    }
    @ViewBuilder func action(_ c: Check) -> some View {
        if c.installs {
            Text("Docked carries its conversion tools. Putting them in place takes about a minute and 2.5 GB.").font(.callout).foregroundStyle(style.text)
            if model.installing { HStack { ProgressView().controlSize(.small); Text("Installing…") } } else { Button("Install Conversion Tools") { model.install() } }
        } else if c.title.hasPrefix("Xcode") {
            Text("Download \(c.title) from Apple and move it to Applications. You need a free Apple account. It's large, so this takes a while. \(c.detail == "Not installed" ? "" : c.detail + ".")").font(.callout).foregroundStyle(style.text).fixedSize(horizontal: false, vertical: true)
            Button("Open Apple's Download Page") { NSWorkspace.shared.open(URL(string: "https://developer.apple.com/download/all/?q=Xcode%20\(requiredXcode)")!) }
        } else if c.title == "Apple's Metal compiler" {
            Text("A free download from Apple that Docked can start for you.").font(.callout).foregroundStyle(style.text)
            if model.fetching { HStack { ProgressView().controlSize(.small); Text("Downloading from Apple…") } } else { Button("Download It") { model.fetchMetal() } }
        } else if !c.fix.isEmpty {
            Text(c.fix.hasPrefix("sudo") ? "Apple asks you to accept its licence yourself. Paste this in Terminal, press Return, type your Mac's password, then follow what it says." : "\(c.detail). Paste this in Terminal and press Return.").font(.callout).foregroundStyle(style.text).fixedSize(horizontal: false, vertical: true)
            Text(c.fix).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
            Button(copied ? "Copied. Paste It in Terminal" : "Copy and Open Terminal") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c.fix, forType: .string); copied = true; NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")); DispatchQueue.main.asyncAfter(deadline: .now() + 6) { copied = false } }
        } else { Text(c.detail).font(.callout).foregroundStyle(style.text) }
    }
    var found: String? { findKeys(model.keys) }
    var keysOK: Bool { found.map { readKeys($0).usable } ?? false }
    @ViewBuilder var keys: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Games in .nsp, .xci, .nsz and .xcz files are locked. Docked unlocks them with the prod.keys file from your own Switch. .nup files and game folders don't need it.").foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
            dropBox(found == nil ? "Drop your prod.keys file here" : (found! as NSString).lastPathComponent, found == nil ? "key" : "key.fill") { u in model.offerKeys(u) } choose: { if model.pickKeys() { model.objectWillChange.send() } }
            if let f = found { let v = readKeys(f); Label(v.text, systemImage: v.usable ? "checkmark.circle.fill" : "exclamationmark.triangle").font(.callout).foregroundStyle(v.usable ? Color(light: 0x1E7A3C, dark: 0x6FCF8A) : Color(light: 0x8A4B00, dark: 0xF2B45C)).fixedSize(horizontal: false, vertical: true) }
            Text("It stays where it is. Docked remembers its place and never copies or sends it.").font(.caption).foregroundStyle(style.soft)
        }
    }
    @ViewBuilder var games: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(cannotConvert() == nil ? "Drop a Switch game with its update and DLC, or games for other consoles." : "Drop games for other consoles. They play in RetroArch.").foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
            dropBox("Drop games here", "gamecontroller") { u in finish(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.add([u]) } } choose: { finish(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.pickGame() } }
            if !RetroArch.installed { Text("Other consoles play in RetroArch, which is free. Docked downloads it and keeps it inside itself the first time you add one of their games.").font(.callout).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true) }
            if cannotConvert() == nil, !model.ready { Label("Your Mac isn't ready to convert yet. The setup guide, in Settings, picks up where you left off.", systemImage: "info.circle").font(.callout).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true) }
        }
    }
    func dropBox(_ t: String, _ s: String, _ took: @escaping (URL) -> Void, choose: @escaping () -> Void) -> some View {
        VStack(spacing: 10) { Image(systemName: s).font(.system(size: 30)).foregroundStyle(style.accent).accessibilityHidden(true); Text(t).font(.headline).foregroundStyle(style.text).lineLimit(1).truncationMode(.middle); Button("Choose…", action: choose) }
            .frame(maxWidth: .infinity).padding(.vertical, 24).background(style.tile.opacity(0.6), in: RoundedRectangle(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(dropping ? style.accent : style.line, style: StrokeStyle(lineWidth: dropping ? 2.5 : 1.5, dash: [7, 6])) }
            .onDrop(of: [.fileURL], isTargeted: $dropping) { loadDropped($0) { if let u = $0.first { took(u) } }; return true }
    }
}
