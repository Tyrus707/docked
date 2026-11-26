import SwiftUI
import CoreImage

// Covers are made once at the size they are shown, from art already on this Mac, and kept in memory while Docked is open. Nothing is downloaded.
enum Cover {
    static let size = NSSize(width: 312, height: 372)   // shown at 156 x 186: close to the square art most games have, so little is left to fill
    static let shape: CGFloat = 312.0 / 372
    static func custom(_ g: Game) -> URL { Paths.root.appendingPathComponent("Artwork/" + g.titleID.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-") + ".png") }
    static func aspect(_ i: NSImage) -> CGFloat { guard let r = i.representations.max(by: { $0.pixelsWide < $1.pixelsWide }), r.pixelsHigh > 0 else { return i.size.height > 0 ? i.size.width / i.size.height : 1 }; return CGFloat(r.pixelsWide) / CGFloat(r.pixelsHigh) }

    static func bitmap(_ w: Int, _ h: Int, _ draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep); NSGraphicsContext.current?.imageInterpolation = .high; draw(); NSGraphicsContext.restoreGraphicsState(); return rep
    }
    static func small(_ i: NSImage, _ px: Int) -> NSImage { let o = NSImage(size: NSSize(width: px / 2, height: px / 2)); o.addRepresentation(bitmap(px, px) { i.draw(in: NSRect(x: 0, y: 0, width: px, height: px)) }); return o }
    static func context() -> CIContext { CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true]) }   // made when needed and let go
    // The art's own colours, blurred and a little brighter. part: which of it, in fractions.
    static func glow(_ art: NSImage, _ part: NSRect, width: Int, height: Int, blur: Double) -> NSImage {
        let size = NSSize(width: width, height: height), rep = bitmap(width, height) {
            var p = NSRect(x: part.minX * art.size.width, y: part.minY * art.size.height, width: part.width * art.size.width, height: part.height * art.size.height)
            let want = CGFloat(width) / CGFloat(height)
            if p.width / p.height > want { let w = p.height * want; p.origin.x += (p.width - w) / 2; p.size.width = w } else { let h = p.width / want; p.origin.y += (p.height - h) / 2; p.size.height = h }
            art.draw(in: NSRect(origin: .zero, size: size), from: p, operation: .copy, fraction: 1)
        }
        if let i = CIImage(bitmapImageRep: rep) {
            let r = i.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur]).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35]).cropped(to: i.extent)
            if let c = context().createCGImage(r, from: i.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) { return NSImage(cgImage: c, size: size) }
        }
        let o = NSImage(size: size); o.addRepresentation(rep); return o
    }
    // Portrait art fills the cover. Square art, such as a Switch game's own, reaches both edges and fades into its own colours below.
    static func make(art: NSImage) -> NSImage {
        let box = NSRect(origin: .zero, size: size), a = aspect(art), rep = bitmap(Int(size.width), Int(size.height)) {
            if a < 0.9 { let k = max(size.width / a, size.height), w = k * a, h = k; art.draw(in: NSRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)); return }
            let g = glow(art, NSRect(x: 0, y: 0, width: 1, height: 1), width: 156, height: 186, blur: 20), zoom: CGFloat = a > 1.2 ? 1 : 1.13, w = size.width * zoom, h = w / a, top = a > 1.2 ? (size.height - h) / 2 : size.height - h, r = NSRect(x: (size.width - w) / 2, y: top, width: w, height: h)
            art.draw(in: r)
            // The colours over what is left, melting into the art's edge
            guard let c = NSGraphicsContext.current?.cgContext else { return }
            func veil(_ clear: CGFloat, _ full: CGFloat) {
                c.saveGState(); c.beginTransparencyLayer(auxiliaryInfo: nil); g.draw(in: box); NSColor(white: 0, alpha: 0.16).setFill(); box.fill(using: .sourceOver)
                c.setBlendMode(.destinationIn); let m = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0, 1])!
                c.drawLinearGradient(m, start: CGPoint(x: 0, y: full), end: CGPoint(x: 0, y: clear), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]); c.endTransparencyLayer(); c.restoreGState()
            }
            if r.minY > 1 { veil(r.minY + 30, r.minY + 2) }
            if r.maxY < size.height - 1 { veil(r.maxY - 30, r.maxY - 2) }
        }
        let o = NSImage(size: NSSize(width: size.width / 2, height: size.height / 2)); o.addRepresentation(rep); return o
    }
    static let queue = DispatchQueue(label: "covers", qos: .userInitiated)
    // A picture the player chose, made small enough to load at once
    static func keep(_ i: NSImage, at u: URL) -> Bool {
        let a = aspect(i); guard i.size.width > 0, a.isFinite, a > 0.2, a < 5 else { return false }
        let w = a >= 1 ? 640 : 640 * a, h = w / a
        let rep = bitmap(max(1, Int(w)), max(1, Int(h))) { i.draw(in: NSRect(x: 0, y: 0, width: w, height: h)) }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let d = rep.representation(using: .png, properties: [:]) else { return false }; return (try? d.write(to: u, options: .atomic)) != nil
    }
}
let pictureTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "tiff"]
enum Look: String { case covers = "Covers", icons = "Icons" }

// The last few games played. It moves only when the player moves it.
struct Carousel: View {
    @EnvironmentObject var model: Model
    let games: [Game]
    @State private var at: String?
    @State private var over = false
    @Environment(\.accessibilityReduceMotion) private var still
    private var index: Int { games.firstIndex { $0.id == at } ?? 0 }
    private func go(_ n: Int, _ p: ScrollViewProxy) { let i = min(max(n, 0), games.count - 1); at = games[i].id; withAnimation(still ? nil : .easeInOut(duration: 0.28)) { p.scrollTo(games[i].id, anchor: .leading) } }
    var body: some View {
        GeometryReader { geo in
            let w = games.count > 1 ? max(320, geo.size.width - 64) : geo.size.width
            ScrollViewReader { p in
                ScrollView(.horizontal, showsIndicators: false) { LazyHStack(spacing: 12) { ForEach(games) { g in Hero(game: g).frame(width: w).id(g.id) } }.paged() }
                    .pagedScroll($at)
                    .whenChanged(model.cursor) { if let k = model.cursor, k.row == "recent", let i = games.firstIndex(where: { $0.id == k.game }) { go(i, p) } }
                    .overlay(alignment: .leading) { if over, index > 0 { arrow("chevron.left", "Previous game") { go(index - 1, p) }.padding(.leading, 10) } }
                    .overlay(alignment: .trailing) { if over, index < games.count - 1 { arrow("chevron.right", "Next game") { go(index + 1, p) }.padding(.trailing, 10) } }
                    .overlay(alignment: .bottom) { if games.count > 1 { HStack(spacing: 7) { ForEach(Array(games.enumerated()), id: \.element.id) { n, g in Button { go(n, p) } label: { Capsule().fill(.white.opacity(n == index ? 0.95 : 0.42)).frame(width: n == index ? 18 : 7, height: 7).padding(.vertical, 6).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Show \(g.name)") } }.animation(still ? nil : .easeOut(duration: 0.2), value: index).padding(.bottom, 4) } }
            }
        }.frame(height: 196).onHover { over = $0 }
    }
    func arrow(_ s: String, _ l: String, _ f: @escaping () -> Void) -> some View { Button(action: f) { Image(systemName: s).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 36, height: 36).background(.black.opacity(0.55), in: Circle()) }.buttonStyle(.plain).accessibilityLabel(l) }
}
extension View {
    @ViewBuilder func paged() -> some View { if #available(macOS 14, *) { scrollTargetLayout() } else { self } }
    @ViewBuilder func pagedScroll(_ at: Binding<String?>) -> some View { if #available(macOS 14, *) { scrollTargetBehavior(.viewAligned).scrollPosition(id: at) } else { self } }
}

struct CoverTile: View {
    @EnvironmentObject var model: Model
    let game: Game, art: NSImage?
    var favorite = false, running = false, note = ""
    var chosen = false
    let select: () -> Void, play: () -> Void
    var fave: () -> Void = {}
    @ViewBuilder var actions: () -> AnyView
    @State private var over = false
    @State private var landed = true
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var still
    private var lit: Bool { over || focused }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: select) {
                VStack(spacing: 0) {
                    Group { if let art { Image(nsImage: art).resizable().transition(.opacity) } else { Rectangle().fill(style.tile) } }.aspectRatio(Cover.shape, contentMode: .fit).animation(still ? nil : .easeOut(duration: 0.2), value: art != nil).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(focused || chosen ? style.accent : Color.white.opacity(lit ? 0.22 : 0.10), lineWidth: focused || chosen ? 3 : 1) }
                        .overlay(alignment: .bottomLeading) { if over { Button(action: play) { Image(systemName: "play.fill").font(.system(size: 16)).foregroundStyle(.white).padding(12).background(.black.opacity(0.7), in: Circle()).contentShape(Circle()) }.buttonStyle(.plain).padding(8).help("Play \(game.name)").accessibilityLabel("Play \(game.name)") } }
                        .overlay(alignment: .topLeading) { if favorite { Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(.white).padding(6).background(.black.opacity(0.5), in: Circle()).padding(7).accessibilityLabel("Favorite") } }
                        .opacity(game.cannot == nil ? 1 : 0.5)
                        .shadow(color: .black.opacity(lit ? 0.35 : 0), radius: lit ? 10 : 0, y: lit ? 7 : 0)
                        .offset(y: still ? 0 : !landed ? -26 : over ? -5 : 0)
                    if style.shelf { Capsule().fill(style.line).frame(height: 3).padding(.horizontal, -3).padding(.top, 4) }
                    VStack(spacing: 2) {
                        Text(game.name).font(.callout.weight(.medium)).foregroundStyle(style.text).lineLimit(2).multilineTextAlignment(.center)
                        HStack(spacing: 4) { if running { Circle().fill(style.ok).frame(width: 7, height: 7).accessibilityHidden(true) }; Text(note).font(.caption).foregroundStyle(style.soft).lineLimit(1) }
                    }.padding(.top, 8)
                }.padding(.horizontal, 8).padding(.top, 8).frame(maxWidth: .infinity, alignment: .top).contentShape(Rectangle())
            }.buttonStyle(Press(still: still)).focused($focused).noFocusRing().simultaneousGesture(TapGesture(count: 2).onEnded(play)).accessibilityLabel(game.name).accessibilityAddTraits(chosen ? .isSelected : []).accessibilityAction(named: "Play", play)
            HStack(spacing: 4) {
                if lit { FaveButton(on: favorite, name: game.name, tint: .white, backed: true, action: fave) }
                Menu { actions() } label: { Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(width: 28, height: 28).background(.black.opacity(0.5), in: Circle()).contentShape(Circle()) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().opacity(lit ? 1 : 0).accessibilityLabel("More for \(game.name)").help("More")
            }.padding(.trailing, 15).padding(.top, 15)
        }
        .onHover { over = $0 }
        .animation(still ? nil : .easeOut(duration: 0.16), value: over)
        .contextMenu { actions() }
        .onAppear { if model.arrived == game.titleID.uppercased(), !still { landed = false; DispatchQueue.main.async { withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { landed = true }; model.arrived = nil } } }
    }
}
struct Press: ButtonStyle { var still: Bool; func makeBody(configuration c: Configuration) -> some View { c.label.scaleEffect(c.isPressed && !still ? 0.97 : 1).animation(still ? nil : .easeOut(duration: 0.1), value: c.isPressed) } }
