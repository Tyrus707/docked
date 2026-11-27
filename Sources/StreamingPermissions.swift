import CoreGraphics
import Foundation

enum StreamingPermissionState { case allowed, asked, unknown }

// Only the permissions Docked itself needs. A controller pairs straight to the Mac by Bluetooth,
// so there is no Accessibility prompt and no extra hop for its input.
enum StreamingPermission: String, CaseIterable, Identifiable {
    case screen, local

    var id: String { rawValue }
    var title: String {
        switch self {
        case .screen: return "Screen Recording"
        case .local: return "Local Network"
        }
    }
    var text: String {
        switch self {
        case .screen: return "Lets Moonlight see what's on this Mac. Docked asks only when you turn Streaming on; no password or Terminal."
        case .local: return "Lets this Mac find your TV, iPad or another Mac on your network. Ethernet or 5 GHz Wi-Fi works best."
        }
    }
    var button: String {
        switch self {
        case .screen: return "Allow Screen"
        case .local: return "Got it"
        }
    }
    private var key: String { "streaming.permission.\(rawValue)" }

    var state: StreamingPermissionState {
        UserDefaults.standard.bool(forKey: key) ? .asked : .unknown
    }

    func ask() {
        switch self {
        case .screen: _ = CGRequestScreenCaptureAccess()
        case .local: break   // macOS asks when Sunshine first looks for devices; the usage note is in Info.plist
        }
        UserDefaults.standard.set(true, forKey: key)
    }
}
