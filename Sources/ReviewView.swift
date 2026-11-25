import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var builder: Builder
    @Environment(\.dismiss) var dismiss
    @State private var dropping = false
    @State private var more = false
    @Environment(\.accessibilityReduceMotion) private var still
    var space: (text: String, short: Bool) { spaceText(need: spaceNeeded(model.review.parts.reduce(0) { $0 + $1.bytes }), free: freeSpace()) }
    var summary: String { ([model.target == .mac && model.reviewPlace.path != Paths.games.path ? "Saves to " + FileManager.default.displayName(atPath: model.reviewPlace.path) : nil, model.after == .ask || model.forXcode ? nil : model.after.label, model.quick ? "Quick" : nil].compactMap { $0 }).joined(separator: ", ") }
    func note(_ t: String, _ s: String, _ warn: Bool) -> some View { Label(t, systemImage: s).foregroundStyle(warn ? Color(light: 0x8A4B00, dark: 0xF2B45C) : Color.secondary).font(.callout).fixedSize(horizontal: false, vertical: true) }

    // Only a copy in Docked's own folder, or in the chosen folder, is replaced.
    func existingNote(_ g: Game) -> String {
        let dir = g.url.deletingLastPathComponent().path
        if dir == model.reviewPlace.path || dir == Paths.games.path { return "\(g.name) is already converted. Converting replaces it and keeps your save." }
        return "\(g.name) is already in \(FileManager.default.displayName(atPath: dir)). That copy stays, and the new one uses the same save."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Check the Files").font(.title2.weight(.semibold))
            Text("Add the game with its update and DLC. Drop more files here.").foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.review.parts) { p in
                        HStack {
                            Text(p.kind == .unknown ? "File" : p.kind.rawValue).font(.caption.weight(.semibold)).frame(width: 56, alignment: .leading)
                            Text(p.label).lineLimit(1).truncationMode(.head).help(p.url.lastPathComponent)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: p.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                            Button { model.review.parts.removeAll { $0.id == p.id } } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Remove \(p.url.lastPathComponent)")
                        }.padding(.vertical, 6).padding(.horizontal, 10)
                        Divider()
                    }
                }
            }
            .frame(height: min(150, max(34, CGFloat(model.review.parts.count) * 34 + 2))).background(style.tile).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(dropping ? style.accent : style.line, lineWidth: dropping ? 3 : 1) }
            Picker("Make it for", selection: $model.target) { Text("Mac").tag(Target.mac); Text("iPhone or iPad").tag(Target.phone) }.pickerStyle(.segmented).fixedSize().whenChanged(model.target) { if model.target == .phone { model.recheckPhone() } }
            if model.target == .phone {
                HStack { Text("Install with"); Picker("Install with", selection: $model.way) { Text("Xcode").tag(InstallWay.xcode); Text(".ipa file").tag(InstallWay.ipa) }.pickerStyle(.segmented).labelsHidden().fixedSize() }
                Text(model.way == .xcode ? "Xcode signs the game with your Apple account and installs it over a cable. Docked keeps the game's leftovers, because Xcode needs them." : "Makes an .ipa file that you install with a sideloading tool. Many of those tools can't install a file this big.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label("Needs an \(phoneNeeds)", systemImage: "iphone").font(.callout).foregroundStyle(Color(light: 0x8A4B00, dark: 0xF2B45C)).fixedSize(horizontal: false, vertical: true)
                ForEach(model.phoneChecks.filter { !$0.ok }) { c in HStack { Image(systemName: "circle").foregroundStyle(.secondary).accessibilityLabel("Not done"); VStack(alignment: .leading) { Text(c.title); Text(c.detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); if !c.fix.isEmpty { Button("Copy Command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c.fix, forType: .string) } } } }
                if !model.phoneChecks.isEmpty, !model.phoneSet { HStack { Text("Paste each command in Terminal, then check again.").font(.callout).foregroundStyle(.secondary); Button("Check Again") { model.recheckPhone() } } }
            }
            if let b = model.review.blocker { Label(b, systemImage: "exclamationmark.circle").foregroundStyle(Color(light: 0xB3261E, dark: 0xFF8A80)).font(.callout) }
            // Only what needs attention is in sight; what is fine is under More Options.
            ForEach(model.review.notes.filter(\.1), id: \.0) { n in note(n.0, "exclamationmark.triangle", true) }
            if model.target == .mac, let g = model.existing { note(existingNote(g), "arrow.triangle.2.circlepath", false) }
            if !model.review.parts.isEmpty, space.short { note(space.text, "exclamationmark.triangle", true) }
            if model.after == .everything, !model.forXcode { note("The original files go to the Trash before you've tried the game. Don't empty it until you have.", "exclamationmark.triangle", true) }
            if let n = model.reviewNote { Label(n, systemImage: "exclamationmark.circle").foregroundStyle(Color(light: 0xB3261E, dark: 0xFF8A80)).font(.callout).fixedSize(horizontal: false, vertical: true) }
            Button { withAnimation(still ? nil : .easeOut(duration: 0.15)) { more.toggle() } } label: { HStack(spacing: 6) { Image(systemName: "chevron.right").font(.caption.weight(.bold)).rotationEffect(.degrees(more ? 90 : 0)); Text("More options"); Spacer(); if !more { Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(1) } }.contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityValue(more ? "Open" : "Closed")
            if more {
                VStack(alignment: .leading, spacing: 10) {
                    if model.target == .mac { HStack {
                        Text("Save game to")
                        Label(FileManager.default.displayName(atPath: model.reviewPlace.path), systemImage: "folder").help(model.reviewPlace.path)
                        if model.reviewPlace.path == Paths.games.path { Text("in Docked").foregroundStyle(.secondary) }
                        Spacer(); Button("Change…") { model.pickDestination() }
                    } }
                    if !model.forXcode { Picker("When it's done", selection: $model.after) { ForEach(After.allCases, id: \.self) { Text($0.label).tag($0) } }.fixedSize() }
                    if model.after == .leftovers, !model.forXcode { Text("Frees the most space. Adding an update later then takes the full time.").font(.callout).foregroundStyle(.secondary) }
                    Toggle("Skip the pipeline step", isOn: $model.quick)
                    Text("Converts faster, but the game's first start takes longer and may stutter.").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.review.notes.filter { !$0.1 }, id: \.0) { n in note(n.0, "checkmark.circle", false) }
                    if !model.review.parts.isEmpty, !space.short { note(space.text, "internaldrive", false) }
                }.padding(.leading, 16)
            }
            HStack {
                Button("Add More Files…") { model.pickGame() }
                Spacer()
                if model.waits { Text("Starts by itself").font(.caption).foregroundStyle(.secondary) }
                Button("Cancel") { model.review.parts = []; dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.waits ? "Add to Queue" : "Convert") { if model.convert() { dismiss() } }.keyboardShortcut(.defaultAction).tint(style.button).disabled(model.review.blocker != nil || (model.target == .phone && !model.phoneSet))
            }
        }
        .whenChanged(model.review) { model.reviewNote = nil }
        .padding(24).frame(width: 600).background(AllowQuit()).background(Backdrop())
        .onDrop(of: [.fileURL], isTargeted: $dropping) { loadDropped($0) { model.add($0) }; return true }
    }
}

func loadDropped(_ providers: [NSItemProvider], _ done: @escaping ([URL]) -> Void) {
    let g = DispatchGroup(), lock = NSLock(); var urls: [URL] = []
    for p in providers {
        g.enter()
        _ = p.loadObject(ofClass: URL.self) { u, _ in if let u { lock.lock(); urls.append(u); lock.unlock() }; g.leave() }
    }
    g.notify(queue: .main) { done(urls.sorted { $0.path < $1.path }) }
}
