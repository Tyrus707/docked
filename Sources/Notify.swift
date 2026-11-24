import AppKit
import UserNotifications

// Tells the player a conversion is over, when they are looking at something else. Asked for once, the first time a game starts converting.
enum Notify {
    private static var works: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }
    static func ask() { if works { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } } }
    static func say(_ title: String, _ body: String) {
        guard works, !NSApp.isActive else { return }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "conversion", content: c, trigger: nil))   // a newer one replaces it, so a long queue leaves one, not ten
    }
    static func text(done: String?, failed: String?, left: Int, problems: Int) -> (String, String) {
        let more = left == 0 ? "" : left == 1 ? " 1 more to go." : " \(left) more to go."
        if let f = failed { return ("\(f) could not be converted", left > 0 ? "Docked is going on with the next game." + more : "Open Docked to see why.") }
        if left == 0, problems > 0 { return ("The queue is finished", problems == 1 ? "1 game needs your attention." : "\(problems) games need your attention.") }
        return ("\(done ?? "Your game") is ready", left == 0 ? "Open Docked to play." : more.trimmingCharacters(in: .whitespaces))
    }
}
