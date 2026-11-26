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

// A bar in the app's Dock icon while one game converts. The tile is AppKit's, so every change is made on the main thread and the default icon is put back when it clears.
enum DockProgress {
    private static var shown = false, last: Double = -1

    static func fraction(_ value: Double) -> Double { min(max(value, 0), 1) }

    static func show(_ value: Double) { onMain { update(fraction(value)) } }
    static func clear() { onMain {
        if shown, let app = NSApp { app.dockTile.contentView = nil; app.dockTile.display() }
        shown = false; last = -1
    } }

    private static func onMain(_ work: @escaping () -> Void) { if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) } }

    private static func update(_ f: Double) {
        guard let app = NSApp, let icon = app.applicationIconImage else { return }
        let tile = app.dockTile
        guard tile.size.width > 0, tile.size.height > 0 else { return }
        if shown, last == f, tile.contentView is NSImageView { return }
        last = f
        let view: NSImageView
        if shown, let existing = tile.contentView as? NSImageView { view = existing }
        else {
            view = NSImageView(frame: NSRect(origin: .zero, size: tile.size))
            view.imageScaling = .scaleProportionallyUpOrDown
            view.autoresizingMask = [.width, .height]
            tile.contentView = view; shown = true
        }
        if view.frame.size != tile.size { view.frame = NSRect(origin: .zero, size: tile.size) }
        view.image = image(f, from: icon)
        tile.display()
    }

    // The app icon with a track at the bottom, filled to however far this game has got.
    static func image(_ f: Double, from icon: NSImage) -> NSImage {
        let value = fraction(f)
        return NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)
            let h = max(4, rect.height * 0.06), x = rect.width * 0.08
            let track = NSRect(x: x, y: rect.height * 0.09, width: rect.width - x * 2, height: h)
            NSColor.black.withAlphaComponent(0.75).setFill(); NSBezierPath(roundedRect: track, xRadius: h / 2, yRadius: h / 2).fill()
            let filled = NSRect(x: track.minX, y: track.minY, width: max(h, track.width * CGFloat(value)), height: track.height)
            NSColor.controlAccentColor.withAlphaComponent(value > 0 ? 1 : 0.6).setFill(); NSBezierPath(roundedRect: filled, xRadius: h / 2, yRadius: h / 2).fill()
            return true
        }
    }
}
