import SwiftUI

// Game Settings: the converted game's own launch settings, inside Docked. Changes save as you make them and are used the next time the game starts.
struct GameSettingsView: View {
    @EnvironmentObject var model: Model
    let game: Game
    let gs: GameSettings
    @State private var tick = 0   // redraws after a change, since the values live in the game's preferences
    @State private var more = false

    var body: some View {
        let _ = tick
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(game.name) Settings").font(.title2.weight(.semibold)).foregroundStyle(style.text)
                Text("The same settings the game shows when you hold Option as it opens. Changes are saved for its next start.").font(.callout).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
            }
            if model.isRunning(game) { Label("\(game.name) is running. Changes apply the next time it starts.", systemImage: "info.circle").font(.callout).foregroundStyle(style.accent) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(gs.sections, id: \.self) { sec in
                        let rows = gs.settings.filter { $0.section == sec && ($0.basic || more) }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(sec).font(.callout.weight(.semibold)).foregroundStyle(style.soft).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
                                VStack(spacing: 0) { ForEach(Array(rows.enumerated()), id: \.1.id) { i, s in if i > 0 { Divider().overlay(style.line) }; row(s) } }
                                    .padding(.horizontal, 12).background(style.tile, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    if gs.settings.contains(where: { !$0.basic }) {
                        Button { withAnimation(.easeOut(duration: 0.15)) { more.toggle() } } label: { Label(more ? "Fewer Settings" : "Advanced Settings", systemImage: more ? "chevron.up" : "chevron.down").font(.callout).foregroundStyle(style.accent) }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 2)
            }.frame(maxHeight: 460)
            HStack {
                Button("Reset to Tested Defaults") { gs.reset(); tick += 1 }.disabled(!gs.changed).help("Brings back all settings this game was tested with.")
                Spacer()
                Button("Play") { model.tuning = nil; model.play(game) }.disabled(game.missing)
                Button("Done") { model.tuning = nil }.keyboardShortcut(.defaultAction).tint(style.button)
            }
        }.padding(24).frame(width: 500).background(Backdrop())
    }

    @ViewBuilder func row(_ s: LaunchSetting) -> some View {
        let on = gs.applies(s) && !gs.isFixed(s)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 12) {
                Text(s.label).foregroundStyle(style.text)
                Spacer(minLength: 8)
                control(s).disabled(!on)
            }
            if gs.isFixed(s) { Text("Set by this game's conversion.").font(.caption).foregroundStyle(style.soft) }
            else if !s.note.isEmpty { Text(s.note).font(.caption).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true) }
        }.padding(.vertical, 9).opacity(on ? 1 : 0.55)
    }

    @ViewBuilder func control(_ s: LaunchSetting) -> some View {
        let v = gs.value(s)
        switch s.kind {
        case .choice:
            Picker(s.label, selection: Binding(get: { v }, set: { gs.set(s, $0); tick += 1 })) {
                ForEach(s.options ?? [], id: \.self) { o in Text(o.count > 1 ? o[1] : o.first ?? "").tag(o.first ?? "") }
            }.labelsHidden().fixedSize()
        case .toggle:
            Toggle(s.label, isOn: Binding(get: { v == (s.on ?? "1") }, set: { gs.set(s, $0 ? s.on ?? "1" : s.off ?? "0"); tick += 1 })).labelsHidden().toggleStyle(.switch).tint(style.button)
        case .range:
            let lo = s.min ?? 0, hi = Swift.max(s.max ?? 1, lo + (s.step ?? 0.1))
            HStack(spacing: 8) {
                Slider(value: Binding(get: { Swift.min(hi, Swift.max(lo, Double(v) ?? lo)) }, set: { gs.set(s, s.text($0)); tick += 1 }), in: lo...hi, step: s.step ?? 0.1).frame(width: 150).tint(style.accent).accessibilityLabel(s.label)
                Text(s.text(Double(v) ?? lo)).monospacedDigit().foregroundStyle(style.soft).frame(width: 36, alignment: .trailing)
            }
        }
    }
}

// The game's settings, or a note when this conversion has none Docked can read
extension Model {
    func openSettings(_ g: Game) {
        guard g.rom == nil, !g.missing else { return }
        if GameSettings(app: g.url) != nil { tuning = g } else { play(g, settings: true) }
    }
}
