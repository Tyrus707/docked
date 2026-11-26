import SwiftUI

// A short notice in the tray. Good news goes by itself after a few seconds; anything else stays until it's closed.
struct Notice: Identifiable, Equatable { let id = UUID(); var text: String; var good = true }

// What happened this session, newest first. Kept in memory only: no history file, no account.
struct ActivityEntry: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String?
    let at: Date
    let warn: Bool
    let report: String?
}

extension Model {
    // For news and small answers. Errors the player must act on still use `message`, a window alert.
    func tell(_ text: String, good: Bool = true) {
        let n = Notice(text: text, good: good); notice = n
        guard good else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in if self?.notice?.id == n.id { self?.notice = nil } }
    }

    func logActivity(_ title: String, detail: String? = nil, warn: Bool = false, report: String? = nil) {
        let entry = ActivityEntry(title: title, detail: detail, at: Date(), warn: warn, report: report)
        activity.insert(entry, at: 0)
        if activity.count > 40 { activity = Array(activity.prefix(40)) }
    }
}

// The one strip at the foot of the window: what Docked is doing on the left, one notice on the right.
// Replaces the bars that used to stack up there. The conversion's steps and the queue open above it when asked.
struct Tray: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var builder: Builder
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var open = false
    @State private var showActivity = false

    private var waiting: Int { model.queue.waiting.count }
    private var hasTask: Bool { builder.running || model.retro != nil || model.moving != nil || model.filing != nil || model.removing || model.checkingGame || model.engineBusy || model.updating || waiting > 0 }
    private var hasDetails: Bool { builder.running || builder.error != nil || waiting > 0 || !model.queue.problems.isEmpty }
    private var hasNotice: Bool { (builder.error != nil && !builder.running) || !model.queue.problems.isEmpty || model.update != nil || model.engine != nil || !model.xcodeReady.isEmpty || !model.phoneReady.isEmpty || model.newlyAdded != nil || model.notice != nil }

    var body: some View {
        if hasTask || hasNotice || !model.activity.isEmpty {
            VStack(spacing: 0) {
                Divider()
                if open && hasDetails {
                    if builder.running || builder.error != nil { BuildBar() }
                    if waiting > 0 || !model.queue.problems.isEmpty { QueueBar() }
                    Divider()
                }
                if showActivity && !model.activity.isEmpty { ActivityList() }
                HStack(spacing: 14) {
                    task
                    Spacer(minLength: 12)
                    if !model.activity.isEmpty {
                        Button { withAnimation(still ? nil : .easeOut(duration: 0.18)) { showActivity.toggle() } } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showActivity ? "chevron.down" : "clock.arrow.circlepath")
                                Text("Activity")
                            }.font(.caption).foregroundStyle(style.text).padding(.horizontal, 10).frame(height: 24).background(style.line.opacity(0.6), in: Capsule())
                        }.buttonStyle(.plain).help(showActivity ? "Hide activity" : "What happened this session").accessibilityLabel(showActivity ? "Hide activity" : "Show activity")
                    }
                    notice.transition(still ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
                .padding(.horizontal, 16).frame(minHeight: 56)
                .animation(still ? nil : .easeOut(duration: 0.2), value: noticeKey)
            }
            .background(style.tile.opacity(0.45))
            .overlay(alignment: .topLeading) { if builder.running, let f = builder.frac { GeometryReader { g in Rectangle().fill(style.accent).frame(width: g.size.width * min(max(f, 0), 1), height: 2) }.frame(height: 2).accessibilityHidden(true) } }   // a hairline of how far the conversion is
            .whenChanged(hasDetails) { if !hasDetails { open = false } }
        }
    }

    // ---- left: one task at a time ----
    @ViewBuilder var task: some View {
        if builder.running {
            TimelineView(.periodic(from: .now, by: 5)) { t in
                HStack(spacing: 12) {
                    art(model.arrivingIcon)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Converting \(builder.title)").font(.callout.weight(.semibold)).foregroundStyle(style.text).lineLimit(1)
                            Spacer(minLength: 10)
                            Text(builder.remaining(t.date).map { shortTime($0) + " left" } ?? (builder.stageCount > 0 ? "Step \(builder.stageIndex) of \(builder.stageCount)" : "Starting")).font(.caption).foregroundStyle(style.soft).lineLimit(1)
                        }
                        ProgressView(value: builder.overall(t.date)).tint(style.accent).accessibilityLabel("Conversion progress")
                    }.frame(width: 300)
                }
            }
            chip(waiting > 0 ? "\(waiting) more waiting" : "Details")
        } else if let w = model.retro {
            working(w.what, w.fraction)
        } else if let m = model.moving { working("Moving \(m)…")
        } else if let f = model.filing { working(f)
        } else if model.removing { working("Cleaning up…")
        } else if model.checkingGame { working("Checking the converted game…")
        } else if model.engineBusy { working("Updating the conversion engine…")
        } else if model.updating { working("Updating Docked…")
        } else if waiting > 0 {
            HStack(spacing: 10) {
                Image(systemName: model.queue.paused ? "pause.circle" : "clock").foregroundStyle(style.accent).accessibilityHidden(true)
                Text(waiting == 1 ? "1 game waiting to convert" : "\(waiting) games waiting to convert").font(.callout).foregroundStyle(style.text)
                if model.queue.paused { Text("Paused").font(.caption).foregroundStyle(style.warn) }
            }
            if model.queue.paused { Button("Continue") { model.resumeQueue() } }
            chip("Details")
        }
    }
    func working(_ what: String, _ fraction: Double? = nil) -> some View {
        HStack(spacing: 12) {
            if let fraction {
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(what).font(.callout.weight(.semibold)).foregroundStyle(style.text).lineLimit(1); Spacer(minLength: 10); Text("\(Int(fraction * 100))%").font(.caption).monospacedDigit().foregroundStyle(style.soft) }
                    ProgressView(value: fraction).tint(style.accent).accessibilityLabel("Download progress")
                }.frame(width: 300)
            } else {
                ProgressView().controlSize(.small)
                Text(what).font(.callout).foregroundStyle(style.text).lineLimit(1)
            }
        }
    }
    func art(_ i: NSImage?) -> some View {
        Group { if let i { Image(nsImage: i).resizable() } else { DPad().fill(style.accent).padding(7) } }
            .frame(width: 34, height: 34).background(style.tile, in: RoundedRectangle(cornerRadius: 8)).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
    }
    func chip(_ t: String) -> some View {
        Button { withAnimation(still ? nil : .easeOut(duration: 0.18)) { open.toggle() } } label: {
            HStack(spacing: 4) { Text(t); Image(systemName: open ? "chevron.down" : "chevron.up").font(.caption2.weight(.bold)) }
                .font(.caption).foregroundStyle(style.text).padding(.horizontal, 10).frame(height: 24).background(style.line.opacity(0.6), in: Capsule())
        }.buttonStyle(.plain).help(open ? "Hide the details" : "Show the steps and the queue").accessibilityLabel(open ? "Hide details" : "\(t), show details")
    }

    // ---- right: one notice at a time, the most pressing first ----
    private var noticeKey: String {
        if builder.error != nil && !builder.running { return "error" }
        if let p = model.queue.problems.first { return p.id.uuidString }
        if let v = model.update { return "update" + v }
        if model.engine != nil { return "engine" }
        if let n = model.xcodeReady.first { return "xcode" + n }
        if let u = model.phoneReady.first { return u.path }
        if let n = model.newlyAdded { return "added" + n }
        return model.notice?.id.uuidString ?? ""
    }
    @ViewBuilder var notice: some View {
        if let e = builder.error, !builder.running {
            card("exclamationmark.triangle", "\(builder.title) stopped converting", e, warn: true) {
                Button("Details") { open = true }
                Button("Report Problem") { model.reportProblem(builder.report) }
            } close: { builder.error = nil }
        } else if let p = model.queue.problems.first {
            card("exclamationmark.triangle", p.title, p.reason, warn: true) {
                Button(model.queue.problems.count > 1 ? "All \(model.queue.problems.count)" : "Details") { open = true }
            } close: { model.queue.problems.removeAll { $0.id == p.id } }
        } else if let v = model.update {
            card("arrow.down.circle", "Docked \(v) is ready", "You have \(appVersion). Your games and settings stay.") {
                if model.updating { ProgressView().controlSize(.small) } else {
                    Button("What's New") { model.showReleaseNotes = true }
                    Button("Update and Reopen") { model.installUpdate(v) }.buttonStyle(.borderedProminent).tint(style.button)
                }
            } close: { model.update = nil }
        } else if let e = model.engine {
            card("gearshape.2", "A newer conversion engine is ready", e.summary.isEmpty ? "From \(e.when.map(engineDay) ?? e.date)." : e.summary) {
                if !model.engineBusy { Button("Update Engine") { model.installEngine() } }
            } close: { model.engine = nil }
        } else if let n = model.xcodeReady.first {
            card("hammer", "\(n) is ready for Xcode", "Xcode signs it with your Apple account and puts it on your iPhone or iPad.") {
                Button("Show Steps") { model.showXcode = true }
            } close: { model.xcodeReady.removeFirst() }
        } else if let u = model.phoneReady.first {
            card("iphone", "\(u.deletingPathExtension().lastPathComponent) is ready for iPhone and iPad", "Install the .ipa with a sideloading tool such as AltStore or Sideloadly. Turn on Increased Memory Limit if it's offered.") {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
            } close: { model.phoneReady.removeFirst() }
        } else if let n = model.newlyAdded {
            card("tray.and.arrow.down", n, nil) {
                Button("Show") { model.section = .all; model.sort = .added; model.newlyAdded = nil }
            } close: { model.newlyAdded = nil }
        } else if let n = model.notice {
            card(n.good ? "checkmark.circle" : "info.circle", n.text, nil) { EmptyView() } close: { model.notice = nil }
        }
    }
    func card<B: View>(_ symbol: String, _ title: String, _ detail: String?, warn: Bool = false, @ViewBuilder buttons: () -> B, close: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(warn ? style.warn : style.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium)).foregroundStyle(style.text).lineLimit(detail == nil ? 2 : 1).fixedSize(horizontal: false, vertical: true)
                if let detail { Text(detail).font(.caption).foregroundStyle(style.soft).lineLimit(1).help(detail) }
            }.frame(maxWidth: 380, alignment: .leading)
            buttons().controlSize(.small)
            Button(action: close) { Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(style.soft).frame(width: 22, height: 22).contentShape(Rectangle()) }
                .buttonStyle(.plain).help("Not Now").accessibilityLabel("Close \(title)")
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
        .background(style.tile, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(warn ? style.warn.opacity(0.55) : style.line, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}

// The tray's history: what Docked finished or flagged this session, newest first.
private struct ActivityList: View {
    @EnvironmentObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity").font(.headline).foregroundStyle(style.text)
                Spacer()
                Button("Clear") { model.activity = [] }.font(.caption)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.activity) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: e.warn ? "exclamationmark.triangle" : "checkmark.circle").foregroundStyle(e.warn ? style.warn : style.ok).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(e.title).font(.callout.weight(.medium)).foregroundStyle(style.text)
                                    Text(e.at.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                                if let d = e.detail { Text(d).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                                if let r = e.report { Button("Copy Report") { model.copyReport(r) }.font(.caption) }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }.frame(maxHeight: 220)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(style.tile.opacity(0.5))
    }
}
