import SwiftUI

struct SmartEditor: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss
    @State var s: SmartCollection
    @State private var problem = ""
    var isNew: Bool { !model.library.smart.contains { $0.id == s.id } }
    var matches: Int { model.games.reduce(0) { $0 + (s.holds($1, model.library.entry($1.titleID)) ? 1 : 0) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Smart Collection" : "Smart Collection").font(.title2.weight(.semibold))
            Text("It fills itself with every game that matches all of these.").foregroundStyle(.secondary)
            if isNew { HStack { ForEach(SmartCollection.ready) { r in Button(r.name) { var c = r; c.id = s.id; s = c } } }.controlSize(.small) }
            Form {
                TextField("Name", text: $s.name)
                Picker("Console", selection: $s.console) { Text("Any").tag(String?.none); ForEach(model.consolesShown, id: \.id) { Text($0.name).tag(String?.some($0.id)) } }
                Picker("Progress", selection: $s.status) { Text("Any").tag(Entry.Status?.none); ForEach(Entry.Status.allCases, id: \.self) { Text($0.rawValue).tag(Entry.Status?.some($0)) } }
                Toggle("Favorites only", isOn: $s.favorite)
                Toggle("Never played", isOn: $s.neverPlayed)
                days("Played in the last", $s.playedWithin); days("Not played for", $s.notPlayedFor); days("Added in the last", $s.addedWithin)
                Picker("Played for more than", selection: $s.moreThanHours) { Text("Any").tag(Int?.none); ForEach([1, 5, 10, 25, 50, 100], id: \.self) { Text($0 == 1 ? "1 hour" : "\($0) hours").tag(Int?.some($0)) } }
            }
            HStack {
                Text(problem.isEmpty ? (s.empty ? "Choose at least one rule." : matches == 1 ? "1 game matches now." : "\(matches) games match now.") : problem).font(.callout).foregroundStyle(problem.isEmpty ? Color.secondary : style.danger)
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { if model.library.keepSmart(s) { let k = model.library.smart.first { $0.id == s.id }; if let k { model.section = .smart(k) }; dismiss() } else { problem = s.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Give it a name." : "That name is taken." } }.keyboardShortcut(.defaultAction).tint(style.button).disabled(s.empty)
            }
        }.padding(24).frame(width: 520).background(AllowQuit()).background(Backdrop())
    }
    func days(_ t: String, _ v: Binding<Int?>) -> some View { Picker(t, selection: v) { Text("Any").tag(Int?.none); ForEach([7, 14, 30, 90, 180, 365], id: \.self) { Text("\($0) days").tag(Int?.some($0)) } } }
}
