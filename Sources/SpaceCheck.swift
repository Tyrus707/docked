import SwiftUI

// One reading of the room a conversion needs, shared by Setup Check and the review screen.
// The work happens on the startup disk; the finished game lands on the chosen disk, which may be another one.
struct SpaceCheck: View {
    let estimate: SpaceEstimate
    var destination: String? = nil
    var compact = false

    private var workLine: String { "\(byteText(estimate.need)) needed · \(byteText(estimate.free)) free" }
    private var destinationLine: String? {
        guard let name = destination, let free = estimate.destinationFree, let need = estimate.destinationNeed else { return nil }
        return "\(name): \(byteText(free)) free · \(byteText(need)) for the finished game"
    }

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: estimate.short ? "exclamationmark.triangle.fill" : "internaldrive")
                        .foregroundStyle(estimate.short ? style.warn : style.ok)
                        .accessibilityHidden(true)
                    Text("Room to convert").font(.callout.weight(.medium)).foregroundStyle(style.text)
                    Spacer(minLength: 8)
                    Text(workLine).font(.caption).foregroundStyle(.secondary)
                }
                if let destinationLine { Text(destinationLine).font(.caption).foregroundStyle(.secondary) }
                if estimate.short { Text(spaceAdvice(estimate)).font(.caption).foregroundStyle(style.warn).fixedSize(horizontal: false, vertical: true) }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: estimate.short ? "exclamationmark.triangle.fill" : "internaldrive")
                        .foregroundStyle(estimate.short ? style.warn : style.ok)
                        .accessibilityHidden(true)
                    Text(estimate.short ? "Not enough room" : "Room to convert").font(.callout.weight(.semibold)).foregroundStyle(style.text)
                    Spacer(minLength: 8)
                    Text(estimate.short ? "Check before you convert" : "Checked before you convert").font(.caption).foregroundStyle(.secondary)
                }
                row("Work space", workLine)
                row("Left on this Mac", roomText(free: estimate.free, need: estimate.need))
                if let destinationLine {
                    Divider()
                    row("Game folder", destinationLine)
                    if let free = estimate.destinationFree, let need = estimate.destinationNeed {
                        row("Left there", roomText(free: free, need: need))
                    }
                }
                if estimate.short {
                    Text(spaceAdvice(estimate)).font(.callout).foregroundStyle(style.warn).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(style.tile.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(estimate.short ? style.warn.opacity(0.55) : style.line, lineWidth: 1) }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 108, alignment: .leading)
            Text(value).font(.callout).foregroundStyle(style.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
