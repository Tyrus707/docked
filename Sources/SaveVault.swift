import SwiftUI

// The save copies Docked already keeps, in plain language. No new store, no account, no sending anywhere.
struct SaveVaultView: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss
    let game: Game

    private var data: GameData { GameData(game.titleID) }

    var body: some View {
        let backups = data.list()
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Save Vault").font(.title2.weight(.semibold))
                Text("Dated copies of \(game.name)'s progress, kept on this Mac. Nothing is sent anywhere.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Image(systemName: data.hasSave ? "checkmark.circle.fill" : "circle").foregroundStyle(data.hasSave ? style.ok : Color.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.hasSave ? "Current save" : "No save yet").font(.callout.weight(.medium))
                    Text(data.hasSave ? "\(byteText(GameData.size(data.save))) on this Mac." : "Play the game once and its save will appear here.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if data.hasSave {
                    Button("Back Up Now") { model.backUpSave(game) }
                    Button("Copy Out…") { model.exportSave(game) }
                }
            }
            Divider()
            if backups.isEmpty {
                Label("No saved copies yet. Docked makes one before converting, updating Docked, offloading or moving this game to the Trash.", systemImage: "clock")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(backups, id: \.url) { b in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(b.date.formatted(date: .abbreviated, time: .shortened)) · \(b.reason)").font(.callout.weight(.medium)).foregroundStyle(style.text)
                                    Text("\(byteText(b.bytes)) · \(b.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(b.name)
                                }
                                Spacer(minLength: 8)
                                Button("Use") { let u = b.url; dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { model.restoreSave(game, from: u) } }
                                Button("Copy Out…") { model.exportSave(game, from: b.url, label: b.reason) }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }.frame(maxHeight: 280)
            }
            Text("Using a copy keeps the save you have now as another dated copy first.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Show Saves in Finder") { model.reveal(data.hasSave ? data.save : data.backups) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).tint(style.button)
            }
        }
        .padding(24).frame(width: 580).background(AllowQuit()).background(Backdrop())
    }
}
