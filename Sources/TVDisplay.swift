import AppKit
import ObjectiveC

// While a stream plays, a screen the TV's exact size and refresh rate. The Mac's own screens mirror it,
// so Sunshine sends the TV a full 16:9 (or whatever it is) picture with nothing scaled and no side bars.
// macOS has no public way to make one; CGVirtualDisplay is what DeskPad and BetterDisplay use. It is looked up
// at run time, so if a later macOS drops it, streaming carries on at the Mac's own size.
final class TVDisplay {
    static let shared = TVDisplay()
    private var display: NSObject?   // macOS takes the screen away when this is let go
    private var made: (w: Int, h: Int, fps: Int)?
    private var activity: NSObjectProtocol?
    var madeCouch = false   // Couch Mode was opened for the stream, so it closes with it

    func start(width: Int, height: Int, fps: Int, done: @escaping () -> Void) {
        // Keeps Docked out of App Nap and the Mac awake, with timers on time, while the TV is playing
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical, .idleDisplaySleepDisabled], reason: "Streaming to a TV")
        }
        if display != nil, let m = made, m.w == width, m.h == height, m.fps == fps { done(); return }
        display = nil; made = nil
        guard let d = TVDisplay.make(width: width, height: height, fps: fps) else { done(); return }
        display = d.object; made = (width, height, fps)
        mirror(onto: d.id, tries: 12, done: done)
    }

    func stop() {
        display = nil; made = nil
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
    }

    // The new screen takes a moment to come online. Then every other screen mirrors it, so it is the main one.
    private func mirror(onto id: CGDirectDisplayID, tries: Int, done: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.display != nil else { done(); return }
            let screens = TVDisplay.online()
            guard screens.contains(id) else { if tries > 0 { self.mirror(onto: id, tries: tries - 1, done: done) } else { done() }; return }
            var cfg: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&cfg) == .success {
                for other in screens where other != id { CGConfigureDisplayMirrorOfDisplay(cfg, other, id) }
                _ = CGCompleteDisplayConfiguration(cfg, .forSession)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: done)   // the screens settle before Sunshine looks
        }
    }

    static func online() -> [CGDirectDisplayID] {
        var n: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &n) == .success, n > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
        guard CGGetOnlineDisplayList(n, &ids, &n) == .success else { return [] }
        return Array(ids.prefix(Int(n)))
    }

    // Sizes Moonlight asks for, kept sane. A 4K TV gets a Retina screen, so Couch Mode isn't drawn tiny.
    static func plan(width: Int, height: Int, fps: Int) -> (points: (Int, Int), pixels: (Int, Int), hiDPI: Bool, fps: Int)? {
        guard (640...7680).contains(width), (360...4320).contains(height) else { return nil }
        let rate = min(max(fps, 24), 240)
        let retina = width >= 2560 && width % 2 == 0 && height % 2 == 0
        return (retina ? (width / 2, height / 2) : (width, height), (width, height), retina, rate)
    }

    private typealias ModeInit = @convention(c) (UnsafeMutableRawPointer, Selector, UInt32, UInt32, Double) -> UnsafeMutableRawPointer?
    private typealias ObjectInit = @convention(c) (UnsafeMutableRawPointer, Selector, AnyObject) -> UnsafeMutableRawPointer?
    private typealias Apply = @convention(c) (AnyObject, Selector, AnyObject) -> ObjCBool

    private static func make(width: Int, height: Int, fps: Int) -> (object: NSObject, id: CGDirectDisplayID)? {
        guard let p = plan(width: width, height: height, fps: fps),
              let Descriptor = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let Settings = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let Mode = NSClassFromString("CGVirtualDisplayMode"), let Display = NSClassFromString("CGVirtualDisplay") else { return nil }
        let d = Descriptor.init()
        d.setValue(DispatchQueue.main, forKey: "queue")
        d.setValue("Docked TV", forKey: "name")
        d.setValue(p.pixels.0, forKey: "maxPixelsWide")
        d.setValue(p.pixels.1, forKey: "maxPixelsHigh")
        d.setValue(NSValue(size: NSSize(width: 1210, height: 1210 * Double(p.pixels.1) / Double(p.pixels.0))), forKey: "sizeInMillimeters")   // about a 55" TV
        d.setValue(0xD0C, forKey: "vendorID"); d.setValue(0x7001, forKey: "productID"); d.setValue(1, forKey: "serialNum")
        let ended: @convention(block) (AnyObject?, AnyObject?) -> Void = { _, _ in }
        d.setValue(unsafeBitCast(ended, to: AnyObject.self), forKey: "terminationHandler")

        guard let mode = create(Mode, "initWithWidth:height:refreshRate:", { o, s, imp in
            unsafeBitCast(imp, to: ModeInit.self)(o, s, UInt32(p.points.0), UInt32(p.points.1), Double(p.fps))
        }), let screen = create(Display, "initWithDescriptor:", { o, s, imp in unsafeBitCast(imp, to: ObjectInit.self)(o, s, d) }) else { return nil }

        let settings = Settings.init()
        settings.setValue(p.hiDPI ? 1 : 0, forKey: "hiDPI")
        settings.setValue([mode], forKey: "modes")
        let apply = NSSelectorFromString("applySettings:")
        guard let imp = class_getMethodImplementation(Display, apply), class_respondsToSelector(Display, apply),
              unsafeBitCast(imp, to: Apply.self)(screen, apply, settings).boolValue,
              let id = (screen.value(forKey: "displayID") as? NSNumber)?.uint32Value, id != 0 else { return nil }
        return (screen, id)
    }

    // alloc, then an init that takes plain numbers, which perform(_:) can't pass
    private static func create(_ cls: AnyClass, _ initName: String, _ call: (UnsafeMutableRawPointer, Selector, IMP) -> UnsafeMutableRawPointer?) -> NSObject? {
        let sel = NSSelectorFromString(initName)
        guard class_respondsToSelector(cls, sel), let imp = class_getMethodImplementation(cls, sel),
              let raw = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.toOpaque(),
              let made = call(raw, sel, imp) else { return nil }
        return Unmanaged<NSObject>.fromOpaque(made).takeRetainedValue()
    }
}

// docked://tv links come from tv.sh, which Sunshine runs as a stream starts and ends
struct TVRequest: Equatable {
    var start: Bool
    var width = 0, height = 0, fps = 60
    var play: String? = nil   // a title ID: Docked starts the game once the screen is ready
    var couch = false
}
