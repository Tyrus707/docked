import Foundation
import IOKit.ps
import CoreGraphics

// The Mac's power and whether someone is using it, for Convert When (Core.swift). Tells when the power source changes.
final class Power {
    static let shared = Power()
    var changed: () -> Void = {}
    private var source: CFRunLoopSource?
    var onPower: Bool {
        guard let i = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let t = IOPSGetProvidingPowerSourceType(i)?.takeUnretainedValue() else { return true }
        return (t as String) == kIOPSACPowerValue
    }
    var lowPower: Bool { if #available(macOS 12, *) { return ProcessInfo.processInfo.isLowPowerModeEnabled }; return false }
    var idle: Double { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) }
    func start() {
        guard source == nil else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ ctx in guard let ctx else { return }; let p = Unmanaged<Power>.fromOpaque(ctx).takeUnretainedValue(); DispatchQueue.main.async { p.changed() } }, me)?.takeRetainedValue()
        if let s = source { CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode) }
        if #available(macOS 12, *) { NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.changed() } }
    }
    func wait(_ w: ConvertWhen) -> String? { convertWait(w, onPower: onPower, lowPower: lowPower, hour: Calendar.current.component(.hour, from: Date()), idle: idle) }
}
