import SwiftUI

struct HelpTopic: Identifiable {
    var id: String { title }
    var title: String, symbol: String, lines: [String]
}

let helpTopics: [HelpTopic] = [
    HelpTopic(title: "What you need", symbol: "checklist", lines: [
        "A game you own and dumped yourself. Docked reads .nsp, .xci, .nsz, .xcz and .nup files, and dump folders.",
        "For .nsp, .xci, .nsz and .xcz: the prod.keys file from your own Switch. A .nup file or dump folder needs no keys.",
        "Free space of about twice the game's size, plus 10 GB.",
    ]),
    HelpTopic(title: "Convert a game", symbol: "square.and.arrow.down", lines: [
        "1. Drop the game in the window, then add its update and DLC. Nothing starts yet.",
        "2. Check the list and any warnings, then choose Convert. If asked, choose your prod.keys file.",
        "3. Wait 10 to 60 minutes the first time. Stay plugged in with the lid open.",
        "4. When it finishes, the game appears in the window. Click it for its details; double-click it, or press Play, to start it.",
        "To add an update or DLC later, open the game's ••• menu and choose Add Update or DLC (also in the File menu). It converts again, reusing what it can, and keeps your save.",
        "Choose where the game is saved before you convert, or open its ••• menu later and choose Move to Folder. Use Docked to move it, so it stays in the window.",
        "Add more games while one converts: they wait in a queue and start by themselves. Docked remembers the queue if you quit.",
        "To save space, choose Clean Up from a game's ••• menu or the Options menu, and pick what to remove. Docked keeps a link to each original file, so deleting one in Finder alone doesn't free its space.",
    ]),
    HelpTopic(title: "About prod.keys", symbol: "key", lines: [
        "They belong to the Switch system, not to a game. One file works for many games.",
        "They must be at least as new as the game needs. If a new game or update can't be unlocked, dump your keys again after updating your Switch.",
        "Keep the file private. Some of its keys belong only to your console. Docked remembers where it is and never copies it. A prod.keys file in the Dockside folder in your home folder is found automatically.",
    ]),
    HelpTopic(title: "Play", symbol: "gamecontroller", lines: [
        "A controller works best: connect it in System Settings > Bluetooth before you start the game.",
        "Keyboard: WASD moves, Shift and the arrow keys turn the camera, the arrow keys alone are the D-pad.",
        "J K U I are A B X Y. Q E are L R. Z C are ZL ZR. Return is +, Tab is −, F and G press the sticks, Space shakes.",
        "To change a game's cover, drop a picture on it or choose Choose Cover from its ••• menu. Covers or Icons is in the Options menu.",
        "Full screen: Control-Command-F. Quit: Command-Q, or hold the controller's Home button for 2 seconds. Save in the game first.",
        "Open a game's ••• menu and choose Play with Settings to change frame rate, resolution or language.",
    ]),
    HelpTopic(title: "If something goes wrong", symbol: "wrench.and.screwdriver", lines: [
        "Conversion stopped: choose Details to see why. Adding the same game again continues from the finished steps.",
        "\"Nobody has tested this game yet\": Docked makes a best guess, and the game may not start.",
        "Some games can't work at all, such as older 32-bit games. Online play and amiibo aren't supported.",
        "The game opens and then closes: its log is in your Library folder, under Logs > nxnative.",
        "Low on space: choose Clean Up from the Options menu. Your games and saves stay.",
    ]),
]

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("How to Use Docked").font(.title2.weight(.semibold))
                    ForEach(helpTopics) { t in
                        VStack(alignment: .leading, spacing: 6) {
                            Label { Text(t.title) } icon: { Image(systemName: t.symbol).foregroundStyle(style.accent) }.font(.headline)
                            ForEach(t.lines, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                        }
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).tint(style.button) }.padding(16)
        }.frame(width: 560, height: 520).background(AllowQuit()).background(Backdrop())
    }
}
