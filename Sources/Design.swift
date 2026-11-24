import SwiftUI

// Dockside's look, in one place: colours, the mark, and the game tiles. Drawn with shapes only, so it adds no images and no work while idle.
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255) }
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { a in
            let h = a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
        })
    }
}

struct Style {
    var top, bottom, text, soft, accent, tile, line, button: Color
    var alwaysDark = false, shelf = false

    // Quiet neutrals with the logo's oxblood and brass; follows the Mac's light or dark setting.
    static let quay = Style(top: Color(light: 0xF6F5F7, dark: 0x211D20), bottom: Color(light: 0xECEAEE, dark: 0x171416), text: Color(light: 0x241A1D, dark: 0xF1E8D6),
                            soft: Color(light: 0x655A5E, dark: 0xB5A9A4), accent: Color(light: 0x7A2136, dark: 0xD8B26A), tile: Color(light: 0xFFFFFF, dark: 0x2C272A), line: Color(light: 0xD9D4D8, dark: 0x3A3437), button: Color(hex: 0x8A2840))
    // The logo's own colours across the whole window.
    static let oxblood = Style(top: Color(hex: 0x4A1522), bottom: Color(hex: 0x2A0A14), text: Color(hex: 0xF1E8D6), soft: Color(hex: 0xD6C2B4), accent: Color(hex: 0xD8B26A),
                               tile: Color(hex: 0x5A2030), line: Color(hex: 0x6B3040), button: Color(hex: 0xA8324D), alwaysDark: true)
    // Cool harbour blue-grey, with games standing on a shelf.
    static let slate = Style(top: Color(light: 0xEEF2F4, dark: 0x1B242A), bottom: Color(light: 0xE0E7EB, dark: 0x12191D), text: Color(light: 0x14242B, dark: 0xE6EEF1), soft: Color(light: 0x4B5F68, dark: 0xA3B5BD),
                             accent: Color(light: 0x1F5E6B, dark: 0x7CC4CF), tile: Color(light: 0xFFFFFF, dark: 0x26323A), line: Color(light: 0xB9C7CE, dark: 0x3B4B54), button: Color(hex: 0x1F6675), shelf: true)

    static var current = slate
}
var style: Style { Style.current }

struct Backdrop: View { var body: some View { LinearGradient(colors: [style.top, style.bottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea() } }

// The direction pad from the logo.
struct DPad: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height), w = s * 0.34, k = s * 0.07
        let a = Path(roundedRect: CGRect(x: r.midX - w/2, y: r.midY - s/2, width: w, height: s), cornerRadius: k)
        var cuts = Path(ellipseIn: CGRect(x: r.midX - s*0.055, y: r.midY - s*0.055, width: s*0.11, height: s*0.11))
        for i in 0..<4 {   // the arrows, without which it reads as a medical cross
            let t = CGFloat(i) * .pi / 2
            func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: r.midX + s*(u*cos(t) - v*sin(t)), y: r.midY + s*(u*sin(t) + v*cos(t))) }
            cuts.move(to: p(0.425, 0)); cuts.addLine(to: p(0.29, 0.085)); cuts.addLine(to: p(0.29, -0.085)); cuts.closeSubpath()
        }
        let across = Path(roundedRect: CGRect(x: r.midX - s/2, y: r.midY - w/2, width: s, height: w), cornerRadius: k)
        if #available(macOS 14, *) { return a.union(across).subtracting(cuts) }
        var plain = a; plain.addPath(across); return plain
    }
}

struct GameTile: View {
    let game: Game, icon: NSImage
    var favorite = false, running = false, note = ""
    let play: () -> Void
    @ViewBuilder var actions: () -> AnyView
    @State private var over = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: play) {
                VStack(spacing: 8) {
                    Image(nsImage: icon).resizable().frame(width: 124, height: 124)
                        .overlay { if over || focused { Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(.white).padding(15).background(.black.opacity(0.62), in: Circle()).accessibilityHidden(true) } }
                        .scaleEffect(over && !still ? 1.03 : 1)
                    if style.shelf { Capsule().fill(style.line).frame(width: 128, height: 3) }
                    VStack(spacing: 2) {
                        Text(game.name).font(.body.weight(.medium)).foregroundStyle(style.text).lineLimit(2).multilineTextAlignment(.center)
                        HStack(spacing: 4) {
                            if running { Circle().fill(Color(light: 0x1E7A3C, dark: 0x6FCF8A)).frame(width: 7, height: 7).accessibilityHidden(true) }
                            if favorite { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(style.accent).accessibilityLabel("Favorite") }
                            Text(note).font(.caption).foregroundStyle(style.soft).lineLimit(1)
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: 208, alignment: .top)
                .background(over || focused ? style.tile : .clear, in: RoundedRectangle(cornerRadius: 14))
                .overlay { if focused { RoundedRectangle(cornerRadius: 14).strokeBorder(style.accent, lineWidth: 2) } }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focused($focused).noFocusRing().help("Play \(game.name)").accessibilityLabel("Play \(game.name)")
            Menu { actions() } label: { Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(style.text).frame(width: 28, height: 28).contentShape(Circle()) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().padding(6)
                .opacity(over || focused ? 1 : 0.45).accessibilityLabel("More for \(game.name)").help("More")
        }
        .onHover { over = $0 }
        .animation(still ? nil : .easeOut(duration: 0.14), value: over)
        .contextMenu { actions() }
    }
}

// A converting game, coming into dock: it fills from the waterline up as the steps finish.
struct ArrivingTile: View {
    @EnvironmentObject var builder: Builder
    @EnvironmentObject var model: Model
    private var known: NSImage? { model.arrivingIcon }

    var level: Double {
        guard builder.stageCount > 0 else { return 0.03 }
        return min(1, max(0.03, (Double(builder.stageIndex - 1) + (builder.frac ?? 0)) / Double(builder.stageCount)))
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(style.tile)
                art.opacity(0.28)
                art.mask(alignment: .bottom) { Rectangle().frame(height: 102 * level) }
                RoundedRectangle(cornerRadius: 24).strokeBorder(style.line, lineWidth: 1)
                Rectangle().fill(style.accent).frame(height: 2).offset(y: 51 - 102 * level)
            }
            .frame(width: 102, height: 102).clipShape(RoundedRectangle(cornerRadius: 24)).padding(11)
            if style.shelf { Capsule().fill(style.line).frame(width: 128, height: 3) }
            VStack(spacing: 2) {
                Text(builder.title).font(.body.weight(.medium)).foregroundStyle(style.text).lineLimit(2).multilineTextAlignment(.center)
                Text(builder.stageCount > 0 ? "Step \(builder.stageIndex) of \(builder.stageCount)" : "Starting").font(.caption).foregroundStyle(style.soft)
            }
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 208, alignment: .top)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(builder.title), converting").accessibilityValue("Step \(builder.stageIndex) of \(builder.stageCount)")
    }

    @ViewBuilder var art: some View {
        if let known { Image(nsImage: known).resizable().frame(width: 124, height: 124).clipped() }
        else { DPad().fill(style.accent).frame(width: 58, height: 58) }
    }
}

extension View { @ViewBuilder func noFocusRing() -> some View { if #available(macOS 14, *) { focusEffectDisabled() } else { self } } }
extension View { @ViewBuilder func whenChanged<V: Equatable>(_ v: V, _ f: @escaping () -> Void) -> some View { if #available(macOS 14, *) { onChange(of: v) { f() } } else { onChange(of: v) { _ in f() } } } }
