import SwiftUI

// What this Mac still needs before it can convert, and how to get the next thing, one step at a time.
// One list for the first-run guide and the Setup sheet, so both ask for the same things in the same words.
struct SetupChecklist: View {
    @EnvironmentObject var model: Model
    var note = "A game also needs about twice its own size while it converts."
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let now = nextCheck(model.checks)
            ForEach(model.checks) { c in
                HStack(spacing: 10) {
                    Image(systemName: c.ok ? "checkmark.circle.fill" : c.id == now?.id ? "arrow.right.circle.fill" : "circle")
                        .foregroundStyle(c.ok ? style.ok : c.id == now?.id ? style.accent : style.line).accessibilityLabel(c.ok ? "Done" : "Not done")
                    Text(c.title).foregroundStyle(c.ok || c.id == now?.id ? style.text : style.soft)
                    Spacer()
                    if c.ok { Text(c.detail).font(.caption).foregroundStyle(style.soft) }
                }
            }
            if let now { VStack(alignment: .leading, spacing: 8) { action(now) }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(style.tile, in: RoundedRectangle(cornerRadius: 10)) }
            else if model.checks.isEmpty { HStack { ProgressView().controlSize(.small); Text("Checking your Mac…").foregroundStyle(style.soft) } }
            else { Label("Your Mac is ready.", systemImage: "checkmark.seal.fill").foregroundStyle(style.ok) }
            SpaceCheck(estimate: spaceEstimate(bytes: 0), compact: true)
            Text(note).font(.caption).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
            if let p = model.installProblem { Label(p, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(style.danger).fixedSize(horizontal: false, vertical: true) }
        }
    }

    @ViewBuilder func action(_ c: Check) -> some View {
        if c.installs {
            Text("Docked carries its conversion tools. Putting them in place takes about a minute and 2.5 GB.").font(.callout).foregroundStyle(style.text)
            if model.installing { HStack { ProgressView().controlSize(.small); Text("Installing…") } } else { Button("Install Conversion Tools") { model.install() } }
        } else if c.title.hasPrefix("Xcode") {
            Text("Download \(c.title) from Apple and move it to Applications. You need a free Apple account. It's large, so this takes a while. \(c.detail == "Not installed" ? "" : c.detail + ".")").font(.callout).foregroundStyle(style.text).fixedSize(horizontal: false, vertical: true)
            Button("Open Apple's Download Page") { NSWorkspace.shared.open(URL(string: "https://developer.apple.com/download/all/?q=Xcode%20\(requiredXcode)")!) }
        } else if c.title == "Apple's Metal compiler" {
            Text("A free download from Apple that Docked can start for you.").font(.callout).foregroundStyle(style.text)
            if model.fetching { HStack { ProgressView().controlSize(.small); Text("Downloading from Apple…") } } else { Button("Download It") { model.fetchMetal() } }
        } else if !c.fix.isEmpty {
            Text(c.fix.hasPrefix("sudo") ? "Apple asks you to accept its licence yourself. Paste this in Terminal, press Return, type your Mac's password, then follow what it says." : "\(c.detail). Paste this in Terminal and press Return.").font(.callout).foregroundStyle(style.text).fixedSize(horizontal: false, vertical: true)
            Text(c.fix).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(style.soft).fixedSize(horizontal: false, vertical: true)
            Button(copied ? "Copied. Paste It in Terminal" : "Copy and Open Terminal") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c.fix, forType: .string); copied = true; NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")); DispatchQueue.main.asyncAfter(deadline: .now() + 6) { copied = false } }
        } else { Text(c.detail).font(.callout).foregroundStyle(style.text) }
    }
}
