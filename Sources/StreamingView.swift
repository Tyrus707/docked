import SwiftUI

struct TVSettings: View {
    @EnvironmentObject var model: Model
    @ObservedObject var stream: Streaming
    @State private var pin = ""
    @State private var chosenID = ""

    private var selectedPairing: StreamingPairing? {
        stream.pairings.first { $0.id == chosenID } ?? stream.pairings.first
    }

    var body: some View {
        VStack(spacing: 14) {
            settingsRow("Streaming", "Runs Sunshine quietly in the background, with its own settings and port. Docked stops it when you quit.") {
                Toggle("Streaming", isOn: Binding(get: { stream.on }, set: { model.setStreaming($0) }))
                    .labelsHidden().toggleStyle(.switch).tint(style.button)
            }
            settingsRow("Status", stream.detail.isEmpty ? stream.status.label : stream.status.label + " · " + stream.detail) {
                HStack(spacing: 7) {
                    Circle().fill(stream.status == .running ? style.ok : stream.status == .error ? style.danger : style.soft)
                        .frame(width: 9, height: 9).accessibilityLabel(stream.status.label)
                    Button("Refresh") { stream.refreshPairings(); stream.refreshClients() }.disabled(!stream.on)
                }
            }
            if !stream.notice.isEmpty {
                HStack { Text(stream.notice).font(.caption).foregroundStyle(style.accent); Spacer(); Button("Dismiss") { stream.notice = "" }.font(.caption) }
            }
            settingsRow("Picture", stream.quality.note) {
                Picker("Picture", selection: Binding(get: { stream.quality }, set: { stream.setQuality($0) })) {
                    ForEach(StreamingQuality.allCases, id: \.self) { Text($0.label).tag($0) }
                }.labelsHidden().fixedSize()
            }
            settingsRow("Every game in Moonlight", "Off, Moonlight shows one Docked tile that opens Couch Mode. On, each game gets its own tile too.") {
                Toggle("Every game in Moonlight", isOn: $stream.everyGame).labelsHidden().toggleStyle(.switch).tint(style.button)
            }
            Divider()
            ForEach(StreamingPermission.allCases) { p in
                settingsRow(p.title, p.text) {
                    Group {
                        switch p.state {
                        case .allowed: Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(style.ok).font(.caption)
                        case .asked: Text("Requested").font(.caption).foregroundStyle(style.soft)
                        case .unknown: Button(p.button) { p.ask(); stream.permissionsChanged() }
                        }
                    }
                }
            }
            Divider()
            settingsRow("Pair a device", "On Moonlight, pick this Mac. It shows a four-digit PIN; choose the device below and type it here.") {
                Button("Look for Devices") { stream.refreshPairings(); stream.refreshClients() }.disabled(!stream.on)
            }
            if let device = selectedPairing {
                settingsRow("Asking to pair", "\(device.name) · \(device.address)") {
                    Picker("Device", selection: Binding(get: { device.id }, set: { chosenID = $0 })) {
                        ForEach(stream.pairings) { Text($0.name).tag($0.id) }
                    }.labelsHidden().fixedSize()
                }
            }
            settingsRow("PIN", "The four digits on your TV, iPad or other Mac.") {
                HStack(spacing: 8) {
                    TextField("0000", text: $pin).textFieldStyle(.roundedBorder).frame(width: 72)
                    Button("Pair") { if let device = selectedPairing { stream.pair(device, pin: pin); pin = "" } }
                        .disabled(selectedPairing == nil || pin.count != 4)
                }
            }
            if !stream.clients.isEmpty {
                Divider()
                ForEach(stream.clients) { c in
                    settingsRow(c.name, c.enabled ? "Paired and ready to play." : "Turned off in Sunshine.") {
                        Button("Remove") { stream.unpair(c) }
                    }
                }
            }
            Divider()
            settingsRow("A good connection", "Use Ethernet, or 5 GHz Wi-Fi if you can, and turn on your TV's Game Mode. While you play, Docked gives this Mac a screen the TV's exact size, so there are no side bars and nothing is scaled.") {
                Button("How to Pair…") { model.leaveSettings { model.showStreamingWelcome = true } }
            }
            settingsRow("Sunshine's log", "The most recent messages from the streaming host, if something goes wrong.") {
                Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([StreamingPaths.log]) }
            }
        }
        .onAppear { if stream.on { stream.refreshPairings(); stream.refreshClients() } }
    }
}

struct StreamingWelcome: View {
    @ObservedObject var stream: Streaming
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "tv.and.hifispeaker.fill").font(.system(size: 38)).foregroundStyle(style.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Play on any screen").font(.title2.weight(.semibold)).foregroundStyle(style.text)
                    Text("Your Docked library, on a TV, iPad or another Mac.").font(.callout).foregroundStyle(style.soft)
                }
            }
            step("1", "Install Moonlight", "On your TV, iPad or other Mac, install Moonlight from moonlight-stream.org. It's free and open source.")
            step("2", "Pick this Mac", "Streaming is on. Docked sets up its own copy of Sunshine quietly, then Moonlight will see this Mac on your network. If macOS asks about Screen Recording or Local Network, each has a short note in Settings › TV.")
            step("3", "Type the PIN", "Moonlight shows a four-digit PIN while it pairs. Come back to Settings › TV, choose the device and type the PIN. Docked approves it there.")
            Text("Pair a controller with this Mac by Bluetooth for the quickest input. For sound, set this Mac's output to BlackHole; Settings › TV has the note.")
                .font(.caption).foregroundStyle(style.soft)
            HStack {
                Button("Moonlight's Site") { NSWorkspace.shared.open(URL(string: "https://moonlight-stream.org/")!) }
                Spacer()
                Button("Got it") { dismiss(); stream.refreshPairings(); stream.refreshClients() }
                    .buttonStyle(.borderedProminent).tint(style.button).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).frame(width: 520).background(AllowQuit()).background(Backdrop())
    }

    func step(_ n: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.callout.weight(.bold)).foregroundStyle(style.text)
                .frame(width: 25, height: 25).background(style.tile, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(style.text)
                Text(text).font(.caption).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
