import SwiftUI

// Docked's look, in one place: colours, the mark, and the game tiles. Drawn with shapes only, so it adds no images and no work while idle.
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255) }
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { a in
            let h = a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
        })
    }
}

// A theme is Docked's own look, whatever the Mac's light or dark setting. Dark ones first: Docked is a place to sit back and play.
struct Style: Identifiable, Equatable {
    var id: String, name: String
    var top, bottom, text, soft, accent, tile, line, button: Color
    var ok = Color(hex: 0x6FCF8A), warn = Color(hex: 0xF2B45C), danger = Color(hex: 0xFF8A80)
    var dark = true, shelf = false
    static func == (a: Style, b: Style) -> Bool { a.id == b.id }

    // Warm charcoal with the logo's brass and oxblood, like a lamp-lit shelf.
    static let hearth = Style(id: "hearth", name: "Hearth", top: Color(hex: 0x211D20), bottom: Color(hex: 0x171416), text: Color(hex: 0xF1E8D6), soft: Color(hex: 0xB5A9A4),
                              accent: Color(hex: 0xD8B26A), tile: Color(hex: 0x2C272A), line: Color(hex: 0x3A3437), button: Color(hex: 0x8A2840), shelf: true)
    // The logo's own colours across the whole window.
    static let oxblood = Style(id: "oxblood", name: "Oxblood", top: Color(hex: 0x4A1522), bottom: Color(hex: 0x2A0A14), text: Color(hex: 0xF1E8D6), soft: Color(hex: 0xD6C2B4),
                               accent: Color(hex: 0xD8B26A), tile: Color(hex: 0x5A2030), line: Color(hex: 0x6B3040), button: Color(hex: 0xA8324D))
    // Cool harbour blue-grey at night.
    static let harbor = Style(id: "harbor", name: "Harbor", top: Color(hex: 0x1B242A), bottom: Color(hex: 0x12191D), text: Color(hex: 0xE6EEF1), soft: Color(hex: 0xA3B5BD),
                              accent: Color(hex: 0x7CC4CF), tile: Color(hex: 0x26323A), line: Color(hex: 0x3B4B54), button: Color(hex: 0x1F6675), shelf: true)
    // The same harbour by day, for anyone who wants a light window.
    static let daylight = Style(id: "daylight", name: "Daylight", top: Color(hex: 0xEEF2F4), bottom: Color(hex: 0xE0E7EB), text: Color(hex: 0x14242B), soft: Color(hex: 0x4B5F68),
                                accent: Color(hex: 0x1F5E6B), tile: Color(hex: 0xFFFFFF), line: Color(hex: 0xB9C7CE), button: Color(hex: 0x1F6675),
                                ok: Color(hex: 0x1E7A3C), warn: Color(hex: 0x8A4B00), danger: Color(hex: 0xB3261E), dark: false, shelf: true)

    static let all = [hearth, oxblood, harbor, daylight]
    static func named(_ id: String?) -> Style { all.first { $0.id == id } ?? hearth }
    static var current = named(UserDefaults.standard.string(forKey: "theme"))
    // Menus, alerts, sheets and controls follow the theme, not the Mac's setting.
    static func apply() { NSApp?.appearance = NSAppearance(named: current.dark ? .darkAqua : .aqua) }
}
var style: Style { Style.current }

struct Backdrop: View { var s = style; var body: some View { LinearGradient(colors: [s.top, s.bottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea() } }   // holds the theme, so a new one redraws it

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
    private let look = style   // a new theme redraws the tile
    let game: Game, icon: NSImage
    var favorite = false, running = false, note = ""
    var chosen = false, small = false
    let select: () -> Void, play: () -> Void
    var fave: () -> Void = {}
    @ViewBuilder var actions: () -> AnyView
    @State private var over = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var still
    private var side: CGFloat { small ? 84 : 124 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: select) {
                VStack(spacing: 8) {
                    Image(nsImage: icon).resizable().frame(width: side, height: side)
                        .overlay { if over { Button(action: play) { Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(.white).padding(15).background(.black.opacity(0.62), in: Circle()).contentShape(Circle()) }.buttonStyle(.plain).help("Play \(game.name)").accessibilityLabel("Play \(game.name)") } }
                        .scaleEffect(over && !still ? 1.03 : 1)
                    if style.shelf { Capsule().fill(style.line).frame(width: side + 4, height: 3) }
                    VStack(spacing: 2) {
                        Text(game.name).font(small ? .callout.weight(.medium) : .body.weight(.medium)).foregroundStyle(style.text).lineLimit(2).multilineTextAlignment(.center)
                        HStack(spacing: 4) {
                            if running { Circle().fill(style.ok).frame(width: 7, height: 7).accessibilityHidden(true) }
                            if favorite { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(style.accent).accessibilityLabel("Favorite") }
                            Text(note).font(.caption).foregroundStyle(style.soft).lineLimit(1)
                        }
                    }
                }
                .padding(small ? 8 : 12).frame(maxWidth: .infinity, minHeight: small ? 150 : 208, alignment: .top)
                .background(over || focused || chosen ? style.tile : .clear, in: RoundedRectangle(cornerRadius: 14))
                .overlay { if focused || chosen { RoundedRectangle(cornerRadius: 14).strokeBorder(style.accent, lineWidth: 2) } }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focused($focused).noFocusRing().simultaneousGesture(TapGesture(count: 2).onEnded(play)).accessibilityLabel(game.name).accessibilityAddTraits(chosen ? .isSelected : []).accessibilityAction(named: "Play", play)
            HStack(spacing: 0) {
                if over || focused { FaveButton(on: favorite, name: game.name, tint: style.text, action: fave) }
                Menu { actions() } label: { Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(style.text).frame(width: 28, height: 28).contentShape(Circle()) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .opacity(over || focused ? 1 : 0.45).accessibilityLabel("More for \(game.name)").help("More")
            }.padding(6)
        }
        .onHover { over = $0 }
        .animation(still ? nil : .easeOut(duration: 0.14), value: over)
        .contextMenu { actions() }
    }
}

// The heart beside a tile's ••• button, shown while the pointer is over it: one click to favorite, or to take it back.
struct FaveButton: View {
    let on: Bool, name: String, tint: Color
    var backed = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "heart.fill" : "heart").font(.system(size: 12, weight: .semibold)).foregroundStyle(on ? style.accent : tint)
                .frame(width: 28, height: 28).background { if backed { Circle().fill(.black.opacity(0.5)) } }.contentShape(Circle())
        }.buttonStyle(.plain).help(on ? "Remove from Favorites" : "Favorite").accessibilityLabel(on ? "Remove \(name) from Favorites" : "Favorite \(name)")
    }
}

// A converting game, coming into dock: it fills from the waterline up as the steps finish.
struct ArrivingTile: View {
    @EnvironmentObject var builder: Builder
    @EnvironmentObject var model: Model
    private var known: NSImage? { model.arrivingIcon }

    var level: Double { max(0.03, builder.overall()) }

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
