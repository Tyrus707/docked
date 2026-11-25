import SwiftUI

let xcodeSteps: [(title: String, detail: String)] = [
    ("Sign in to Xcode", "In Xcode's menu, choose Settings, then Apple Accounts, and add your own Apple account. Only needed once."),
    ("Connect the iPhone or iPad", "Use a cable. Unlock it and tap Trust."),
    ("Turn on Developer Mode", "On the device: Settings, Privacy & Security, Developer Mode. It restarts. The setting appears once Xcode has seen the device."),
    ("Choose your team", "In Xcode, select the game's DmIOS project on the left, then the DmIOS target, then Signing & Capabilities. Turn on automatic signing and choose your name under Team."),
    ("Press Run", "At the top of Xcode, choose the game and then your device, and press the play button. The first time takes several minutes."),
    ("Trust yourself", "If the device won't open the app: Settings, General, VPN & Device Management, then your account."),
]
let xcodeNotes = [
    "With a free Apple account the app stops opening after 7 days. Press Run again to renew it. Don't delete it from the device first, because that deletes its saves.",
    "If Xcode says your account can't use Increased Memory Limit, remove it under Signing & Capabilities. Bigger games may then close by themselves.",
]
struct XcodeStepsView: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Install with Xcode").font(.title2.weight(.semibold))
                    Text("Needs an \(phoneNeeds)").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(xcodeSteps.enumerated()), id: \.offset) { n, s in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(n + 1)").font(.headline.monospacedDigit()).foregroundStyle(style.accent).frame(width: 16, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) { Text(s.title).font(.headline); Text(s.detail).fixedSize(horizontal: false, vertical: true) }
                        }.accessibilityElement(children: .combine)
                    }
                    Divider()
                    ForEach(xcodeNotes, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction); Button("Open in Xcode") { openInXcode { model.message = $0 }; dismiss() }.keyboardShortcut(.defaultAction).tint(style.button) }.padding(16)
        }.frame(width: 560, height: 680).background(AllowQuit()).background(Backdrop())
    }
}
