import SwiftUI

struct CleanItem: Identifiable {
    enum Kind { case leftovers(Leftovers), originals(Originals), keys(String) }
    let id = UUID(); var kind: Kind, game: Game? = nil, name: String, bytes: Int64, on: Bool, blocked: String? = nil, xcode = false
    var title: String { switch kind { case .leftovers: return "Conversion leftovers"; case .originals: return "Original game files"; case .keys: return "Your keys file, \(name)" } }
    var detail: String {
        if let b = blocked { return b }
        switch kind {
        case .leftovers: return xcode ? "Xcode needs these to install this game on an iPhone or iPad. Deleted for good." : game == nil ? "From a game that is no longer in Docked. Deleted for good." : "Made while converting. Deleted for good. Adding an update later takes the full time."
        case let .originals(o): return (o.files.isEmpty ? o.links : o.files).prefix(3).map(\.lastPathComponent).joined(separator: ", ") + ((o.files.isEmpty ? o.links : o.files).count > 3 ? " and more" : "") + ". To the Trash. You need these to convert again or add an update."
        case .keys: return "To the Trash. You need it to convert .nsp and .xci games. Keep a copy somewhere."
        }
    }
}
struct CleanUp { var one: Game?; var items: [CleanItem] = []; var ready = false; init(one: Game?) { self.one = one } }

struct CleanUpView: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss
    var items: [CleanItem] { model.cleaning?.items ?? [] }
    var chosen: [CleanItem] { items.filter { $0.on && $0.blocked == nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.cleaning?.one.map { "Clean Up \($0.name)" } ?? "Clean Up").font(.title2.weight(.semibold))
            Text("Your games, saves and settings always stay. Open a game and check that it works first.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.cleaning?.ready != true { HStack { ProgressView().controlSize(.small); Text("Measuring…").foregroundStyle(.secondary) }.frame(height: 80) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { i in
                            HStack(alignment: .top) {
                                Toggle(isOn: .init(get: { i.on && i.blocked == nil }, set: { v in if let k = model.cleaning?.items.firstIndex(where: { $0.id == i.id }) { model.cleaning?.items[k].on = v } })) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.cleaning?.one == nil && i.title != "Your keys file, \(i.name)" ? "\(i.name): \(i.title.lowercased())" : i.title)
                                        Text(i.detail).font(.caption).foregroundStyle(i.blocked == nil ? Color.secondary : Color(light: 0x8A4B00, dark: 0xF2B45C)).fixedSize(horizontal: false, vertical: true)
                                    }
                                }.disabled(i.blocked != nil)
                                Spacer()
                                if i.bytes > 0 { Text(ByteCountFormatter.string(fromByteCount: i.bytes, countStyle: .file)).font(.callout).foregroundStyle(.secondary) }
                            }.padding(10)
                            Divider()
                        }
                    }
                }.frame(height: min(330, CGFloat(items.count) * 60 + 4)).background(style.tile).clipShape(RoundedRectangle(cornerRadius: 8))
                Text(chosen.isEmpty ? "Nothing chosen." : "Up to \(ByteCountFormatter.string(fromByteCount: chosen.reduce(0) { $0 + $1.bytes }, countStyle: .file)). Less is freed where files share space with the game.").font(.callout).foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button("Cancel") { model.cleaning = nil }.keyboardShortcut(.cancelAction); Button("Remove") { if let c = model.cleaning { model.doCleanUp(c) } }.disabled(chosen.isEmpty) }
        }.padding(24).frame(width: 560).background(AllowQuit()).background(Backdrop())
    }
}

struct QueueBar: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var builder: Builder
    @State private var open = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.queue.problems) { p in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Color(light: 0xB3261E, dark: 0xFF8A80)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) { Text(p.title).font(.callout.weight(.medium)); Text(p.reason).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled) }
                    Spacer(); if let r = p.report { Button("Copy Report") { model.copyReport(r) } }; Button("Dismiss") { model.queue.problems.removeAll { $0.id == p.id } }
                }
            }
            if !model.queue.waiting.isEmpty {
                HStack {
                    Button { open.toggle() } label: { Label(model.queue.waiting.count == 1 ? "1 game waiting" : "\(model.queue.waiting.count) games waiting", systemImage: open ? "chevron.down" : "chevron.right") }.buttonStyle(.plain).font(.headline).foregroundStyle(style.text)
                    if model.queue.paused { Text("Paused").font(.callout).foregroundStyle(Color(light: 0x8A4B00, dark: 0xF2B45C)) }
                    Spacer()
                    if model.queue.paused { Button(builder.running ? "Continue After This" : "Continue") { model.resumeQueue() } } else if builder.running { Button("Pause After This") { model.queue.paused = true } }
                }
                let s = spaceText(need: spaceForQueue(model.queue.waiting), free: freeSpace())
                Text(s.text).font(.caption).foregroundStyle(s.short ? Color(light: 0x8A4B00, dark: 0xF2B45C) : Color.secondary)
                if open {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(model.queue.waiting.enumerated()), id: \.element.id) { n, j in
                                HStack {
                                    Text("\(n + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18)
                                    Text(j.title).lineLimit(1); Spacer()
                                    Text(shortTime(builder.whole(quick: j.quick, phone: j.phone, xcode: j.xcode))).font(.caption).foregroundStyle(.secondary)
                                    Button { model.queue.up(j.id) } label: { Image(systemName: "arrow.up") }.buttonStyle(.plain).disabled(n == 0).accessibilityLabel("Move \(j.title) up")
                                    Button { model.queue.remove(j.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Remove \(j.title) from the queue")
                                }
                            }
                        }
                    }.frame(height: min(120, CGFloat(model.queue.waiting.count) * 26))
                }
            }
        }.padding(16)
    }
}
