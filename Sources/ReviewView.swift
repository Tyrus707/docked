import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var builder: Builder
    @Environment(\.dismiss) var dismiss
    @State private var dropping = false

    // Only a copy in Dockside's own folder, or in the chosen folder, is replaced.
    func existingNote(_ g: Game) -> String {
        let dir = g.url.deletingLastPathComponent().path
        if dir == model.reviewPlace.path || dir == Paths.games.path { return "\(g.name) is already converted. Converting replaces it and keeps your save." }
        return "\(g.name) is already in \(FileManager.default.displayName(atPath: dir)). That copy stays, and the new one uses the same save."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Check the Files").font(.title2.weight(.semibold))
            Text("Add the game, its update and all its DLC before you convert. You can drop more files here.").foregroundStyle(.secondary)
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
            .frame(height: 150).background(style.tile).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(dropping ? style.accent : style.line, lineWidth: dropping ? 3 : 1) }
            HStack {
                Text("Save game to")
                Label(FileManager.default.displayName(atPath: model.reviewPlace.path), systemImage: "folder").help(model.reviewPlace.path)
                if model.reviewPlace.path == Paths.games.path { Text("in Docked").foregroundStyle(.secondary) }
                Spacer()
                Button("Change…") { model.pickDestination() }
            }
            Toggle("Skip the pipeline step", isOn: $model.quick).help("Converts faster. The game prepares its graphics itself, so its first start takes longer.")
            if model.quick { Text("Converts faster, but the game's first start takes longer and may stutter.").font(.callout).foregroundStyle(.secondary) }
            if let b = model.review.blocker { Label(b, systemImage: "exclamationmark.circle").foregroundStyle(Color(light: 0xB3261E, dark: 0xFF8A80)).font(.callout) }
            ForEach(model.review.notes, id: \.0) { n in
                Label(n.0, systemImage: n.1 ? "exclamationmark.triangle" : "checkmark.circle").foregroundStyle(n.1 ? Color(light: 0x8A4B00, dark: 0xF2B45C) : Color.secondary).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if let g = model.existing { Label(existingNote(g), systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary).font(.callout).fixedSize(horizontal: false, vertical: true) }
            if let n = model.reviewNote { Label(n, systemImage: "exclamationmark.circle").foregroundStyle(Color(light: 0xB3261E, dark: 0xFF8A80)).font(.callout) }
            if builder.running { Label("\(builder.title) is converting. You can convert this when it's done.", systemImage: "hourglass").foregroundStyle(.secondary).font(.callout) }
            HStack {
                Button("Add More Files…") { model.pickGame() }
                Spacer()
                Button("Cancel") { model.review.parts = []; dismiss() }.keyboardShortcut(.cancelAction)
                Button("Convert") { if model.convert() { dismiss() } }.keyboardShortcut(.defaultAction).tint(style.button).disabled(builder.running || model.review.blocker != nil)
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
