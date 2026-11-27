import Foundation

enum StreamingPermissionState { case allowed, asked, unknown }

// TV streaming needs these permissions. A controller pairs straight to the Mac by Bluetooth,
// so there is no Accessibility prompt and no extra hop for its input.
enum StreamingPermission: String, CaseIterable, Identifiable {
    case screen, local, sound

    var id: String { rawValue }
    var title: String {
        switch self {
        case .screen: return "Screen Recording"
        case .local: return "Local Network"
        case .sound: return "Sound"
        }
    }
    var text: String {
        switch self {
        case .screen: return "Lets Moonlight see what's on this Mac. Sunshine asks for this when it first starts; if no prompt appears, allow it in System Settings › Privacy & Security › Screen Recording."
        case .local: return "Lets this Mac find your TV, iPad or another Mac on your network. macOS may ask when Sunshine first looks for devices. Ethernet or 5 GHz Wi-Fi works best."
        case .sound: return StreamingSound.sink().map { "While you stream, this Mac's sound goes to the TV through \($0), then comes back here. Allow Microphone if macOS asks; that's how Sunshine hears it." }
            ?? "For sound on the TV, install BlackHole 2ch (free, from existential.audio), then turn Streaming off and on. Docked does the rest."
        }
    }
    var button: String { "Got it" }
    private var key: String { "streaming.permission.\(rawValue)" }

    // Docked cannot read another app's permission, so this only records that the note was shown.
    var state: StreamingPermissionState {
        UserDefaults.standard.bool(forKey: key) ? .asked : .unknown
    }

    func ask() { UserDefaults.standard.set(true, forKey: key) }
}
