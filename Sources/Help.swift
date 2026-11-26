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
        "2. Check the list and any warnings, then choose Convert. If asked, choose your prod.keys file. Turn on Enable multiplayer - experimental to add friends play; it is off by default.",
        "3. Wait 10 to 60 minutes the first time. Stay plugged in with the lid open.",
        "4. When it finishes, the game appears in the window. Click it for its details; double-click it, or press Play, to start it.",
        "To add an update or DLC later, open the game's ••• menu and choose Add Update or DLC (also in the File menu). It converts again, reusing what it can, and keeps your save.",
        "Choose where the game is saved before you convert, or open its ••• menu later and choose Move to Folder. Use Docked to move it, so it stays in the window.",
        "Add more games while one converts: they wait in a queue and start by themselves. Docked remembers the queue if you quit.",
        "To keep playing while a game converts, open More options and set Conversion speed to Balanced or Background before you start it. You can also change it in Settings > Converting for games you add later. A conversion already running keeps the choice it started with. It takes longer, but the finished game is the same.",
        "To save space, choose Clean Up from a game's ••• menu, or in Settings, and pick what to remove. Docked keeps a link to each original file, so deleting one in Finder alone doesn't free its space.",
    ]),
    HelpTopic(title: "Your library", symbol: "books.vertical", lines: [
        "Docked keeps games in one library folder, with a folder for each console and each game named after itself. Choose where it is, even on an external drive, in Settings > Library.",
        "To bring in games you already have, choose File > Find Games on This Mac. It finds games Docked converted before, and games in OpenEmu, RetroArch and Ryujinx. Look in Another Folder reaches any folder or drive.",
        "Dropping a game, a converted game, or a whole folder in the window works too. Docked asks whether to copy the files into the library, move them, or leave them where they are. Tick Don't ask again to keep your answer; change it in Settings > Library.",
        "Watched folders, in Settings > Library, are folders whose new games are added on their own. Good for a drive full of games: plug it in and they're there.",
        "A game on a drive that isn't connected stays in the library, marked as not connected. If you moved a game yourself, open its ••• menu and choose Locate.",
        "Organize Library, in the File menu, puts games in Docked's folders where they belong, after showing you the list. Saves follow their game. Games you keep anywhere else are never moved.",
    ]),
    HelpTopic(title: "About prod.keys", symbol: "key", lines: [
        "They belong to the Switch system, not to a game. One file works for many games.",
        "They must be at least as new as the game needs. If a new game or update can't be unlocked, dump your keys again after updating your Switch.",
        "Keep the file private. Some of its keys belong only to your console. Docked remembers where it is and never copies it. A prod.keys file in the Docked folder in your home folder is found automatically.",
    ]),
    HelpTopic(title: "Play", symbol: "gamecontroller", lines: [
        "A controller works best: connect it in System Settings > Bluetooth before you start the game.",
        "Keyboard: WASD moves, Shift and the arrow keys turn the camera, the arrow keys alone are the D-pad.",
        "J K U I are A B X Y. Q E are L R. Z C are ZL ZR. Return is +, Tab is −, F and G press the sticks, Space shakes.",
        "Move around with a controller or the arrow keys: A or Return opens a game's details, and again plays it. B or Escape goes back, L and R change section.",
        "To give a game theme music, drop a sound file on it or choose Choose Theme Music in its details. It plays while the game is selected. Theme music in Settings turns it off everywhere.",
        "A smart collection fills itself. Choose + beside Collections, then New Smart Collection.",
        "Docked opens filling the screen and looks for a new version once at launch. Both can be switched off in Settings.",
        "Choose a theme in Settings, under General. Docked keeps its own look, whatever your Mac's light or dark setting.",
        "To change a game's cover, drop a picture on it or choose Choose Cover from its ••• menu. Covers or Icons is in Settings.",
        "Games from other consoles can get their cover, year and description found for them, if you say yes the first time. A wrong one? Choose Find Details Again from its ••• menu. Find covers and details is in Settings.",
        "Converted games get a critic score, popularity, year and genre when they finish, if Find covers and details is on. Find Details looks them up again; Edit Metadata lets you choose the right Wikidata page yourself. What you choose stays when the details refresh.",
        "Full screen: Control-Command-F. Quit: Command-Q, or hold the controller's Home button for 2 seconds. Save in the game first.",
        "Open a game's ••• menu and choose Play with Settings to change frame rate, resolution or language.",
    ]),
    HelpTopic(title: "Couch Mode", symbol: "tv", lines: [
        "Couch Mode fills the screen and shows several rows of games at once. The shelves are across the top; the arrows or D-pad move left and right inside a row, and up and down move to the row above or below.",
        "LB and RB, or Shift-Tab and Tab, move to the previous or next shelf and wrap around. A or Return plays the chosen game, Y or F favorites it, and B or Escape leaves Couch Mode.",
        "Scroll down to find collections that fill themselves from your library: Critically Acclaimed, Enjoy the 90's, and Hidden Gems. They use details already on this Mac, so nothing new is looked up.",
        "The chosen game's own artwork sits behind the rows. After 45 seconds without input the controls fade away; moving the mouse or pressing one of the keys or controller buttons named above brings them back. That first press only wakes them.",
    ]),
    HelpTopic(title: "iPhone and iPad", symbol: "iphone", lines: [
        "When you add a game, choose iPhone or iPad beside Make it for. Then choose how to install it.",
        "Needs an \(phoneNeeds)",
        "Xcode: Docked prepares a project, and Xcode signs it with your Apple account and installs it. The steps are in Settings, under Converting. If Xcode asks you to prepare the game again, add the game again in Docked.",
        ".ipa file: Docked makes it in the iPhone folder, inside the Docked folder. You install it with a sideloading tool, such as AltStore or Sideloadly. Many can't install a file as big as these games.",
        "With a free Apple account, apps stop opening after 7 days and have to be renewed.",
    ]),
    HelpTopic(title: "If something goes wrong", symbol: "wrench.and.screwdriver", lines: [
        "Conversion stopped: choose Details to see why. Adding the same game again continues from the finished steps.",
        "\"Nobody has tested this game yet\": Docked makes a best guess, and the game may not start.",
        "Some games can't work at all, such as older 32-bit games. Online play and amiibo aren't supported.",
        "The game opens and then closes: its log is in your Library folder, under Logs > nxnative.",
        "Low on space: choose Clean Up in Settings, under Converting. Your games and saves stay.",
    ]),
]

struct HelpView: View {
    private let look = style
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
