import SwiftUI

struct ReleaseNotesView: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) var dismiss

    private func lines(_ note: ReleaseNote) -> [String] { releaseLines(note.body) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Release Notes").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.escape)
            }.padding(16)
            Divider()
            Group {
                if let notes = model.releaseNotes {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(notes) { note in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(note.title).font(.headline)
                                        Spacer()
                                        Text(note.tag).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if lines(note).isEmpty {
                                        Text("No notes were published for this release.").font(.callout).foregroundStyle(.secondary)
                                    } else {
                                        ForEach(lines(note), id: \.self) { Text($0).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                                    }
                                    if let url = note.url { Button("View on GitHub") { NSWorkspace.shared.open(url) }.buttonStyle(.link).font(.caption) }
                                }
                            }
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if model.releaseNotesFailed {
                    VStack(spacing: 12) {
                        Text("Couldn't load the notes. Check your connection and try again.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { model.loadReleaseNotes(true) }.tint(style.button)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("Loading notes…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                Button("All Releases on GitHub") { NSWorkspace.shared.open(allReleasesPage) }.buttonStyle(.link)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).tint(style.button)
            }.padding(16)
        }.frame(width: 560, height: 520).background(AllowQuit()).background(Backdrop()).onAppear { model.loadReleaseNotes() }
    }
}
