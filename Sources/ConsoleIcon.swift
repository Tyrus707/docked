import SwiftUI

// A small original line drawing for each kind of console, drawn in a 24-point square like the sidebar's other symbols.
// Shapes, not logos: a hybrid with its two side controllers, a pad, a handheld held upright or sideways, a folding handheld, a joystick, a wand.
struct ConsoleGlyph: Shape {
    enum Kind { case hybrid, dogbone, flatPad, trident, gripPad, crescent, tall, wide, clamshell, wand, joystick, cube }
    let kind: Kind

    static func kind(_ id: String) -> Kind {
        switch id {
        case "switch", "switch2": return .hybrid
        case "snes": return .dogbone
        case "nes", "sms", "pce": return .flatPad
        case "n64": return .trident
        case "ps1", "ps2", "dreamcast", "saturn": return .gripPad
        case "genesis": return .crescent
        case "gb", "gbc": return .tall
        case "gba", "psp", "gg": return .wide
        case "ds", "3ds": return .clamshell
        case "wii": return .wand
        case "a26": return .joystick
        case "gc": return .cube
        default: return .flatPad
        }
    }

    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 24, o = CGPoint(x: r.midX - 12 * s, y: r.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: CGFloat) -> Path { Path(roundedRect: CGRect(x: o.x + x * s, y: o.y + y * s, width: w * s, height: h * s), cornerRadius: c * s) }
        func dot(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat = 1.6) -> Path { Path(ellipseIn: CGRect(x: o.x + (x - d / 2) * s, y: o.y + (y - d / 2) * s, width: d * s, height: d * s)) }
        func cross(_ x: CGFloat, _ y: CGFloat) -> Path { var q = Path(); q.move(to: p(x - 1.8, y)); q.addLine(to: p(x + 1.8, y)); q.move(to: p(x, y - 1.8)); q.addLine(to: p(x, y + 1.8)); return q }
        var q = Path()
        switch kind {
        case .hybrid:
            q.addPath(rect(6.5, 6, 11, 12, 1.2)); q.addPath(rect(2, 6, 4.5, 12, 2.25)); q.addPath(rect(17.5, 6, 4.5, 12, 2.25))
            q.addPath(dot(4.25, 9.5)); q.addPath(dot(19.75, 14.5))
        case .dogbone:
            q.addPath(rect(1.5, 7, 21, 10, 5)); q.addPath(cross(6.5, 12)); q.addPath(dot(16.5, 10.3)); q.addPath(dot(18.8, 12.3)); q.addPath(dot(14.2, 12.3)); q.addPath(dot(16.5, 14.3))
        case .flatPad:
            q.addPath(rect(2, 7.5, 20, 9, 1.5)); q.addPath(cross(6.5, 12)); q.addPath(dot(15.5, 13, 2)); q.addPath(dot(18.5, 13, 2))
        case .trident:
            q.move(to: p(3, 9)); q.addQuadCurve(to: p(21, 9), control: p(12, 5))
            q.addLine(to: p(19.5, 17)); q.addQuadCurve(to: p(16, 15), control: p(17.5, 18))
            q.addLine(to: p(13.3, 12.5)); q.addLine(to: p(13.3, 19.5)); q.addQuadCurve(to: p(10.7, 19.5), control: p(12, 21)); q.addLine(to: p(10.7, 12.5))
            q.addLine(to: p(8, 15)); q.addQuadCurve(to: p(4.5, 17), control: p(6.5, 18)); q.closeSubpath()
            q.addPath(dot(17, 10)); q.addPath(cross(6.8, 10))
        case .gripPad:
            q.move(to: p(5, 7)); q.addLine(to: p(19, 7)); q.addQuadCurve(to: p(22, 17), control: p(22.5, 9)); q.addQuadCurve(to: p(16.5, 15), control: p(19.5, 19.5))
            q.addLine(to: p(7.5, 15)); q.addQuadCurve(to: p(2, 17), control: p(4.5, 19.5)); q.addQuadCurve(to: p(5, 7), control: p(1.5, 9)); q.closeSubpath()
            q.addPath(cross(6.5, 10.5)); q.addPath(dot(17.5, 9.3)); q.addPath(dot(17.5, 12.3)); q.addPath(dot(16, 10.8)); q.addPath(dot(19, 10.8))
        case .crescent:
            q.move(to: p(3, 10)); q.addQuadCurve(to: p(21, 10), control: p(12, 4.5)); q.addQuadCurve(to: p(15, 18), control: p(22, 18)); q.addQuadCurve(to: p(9, 18), control: p(12, 16))
            q.addQuadCurve(to: p(3, 10), control: p(2, 18)); q.closeSubpath()
            q.addPath(cross(7, 11.5)); q.addPath(dot(14.5, 12.5)); q.addPath(dot(16.8, 11.5)); q.addPath(dot(19, 10.5))
        case .tall:
            q.addPath(rect(6, 2, 12, 20, 1.6)); q.addPath(rect(8, 4, 8, 7, 0.8)); q.addPath(cross(9.6, 15.5)); q.addPath(dot(14.8, 15)); q.addPath(dot(16.4, 13.6))
        case .wide:
            q.addPath(rect(1.5, 6.5, 21, 11, 4)); q.addPath(rect(7.5, 8.5, 9, 7, 0.8)); q.addPath(cross(4.6, 12)); q.addPath(dot(19.4, 11)); q.addPath(dot(19.4, 13.6))
        case .clamshell:
            q.addPath(rect(4, 2.5, 16, 9, 1.2)); q.addPath(rect(4, 12.5, 16, 9, 1.2)); q.addPath(rect(7, 4.3, 10, 5.4, 0.5)); q.addPath(rect(8.5, 14.3, 7, 5.4, 0.5))
        case .wand:
            q.addPath(rect(8.5, 1.5, 7, 21, 2.5)); q.addPath(cross(12, 5.5)); q.addPath(dot(12, 10, 2.4)); q.addPath(dot(12, 16)); q.addPath(dot(12, 18.5))
        case .joystick:
            q.addPath(rect(4, 14, 16, 7, 1.2)); q.move(to: p(12, 14)); q.addLine(to: p(12, 6.5)); q.addPath(dot(12, 5, 4)); q.addPath(dot(7.5, 17.5, 2))
        case .cube:
            q.addPath(rect(2, 7, 20, 10, 5)); q.addPath(dot(16, 12, 3.6)); q.addPath(dot(19.3, 9.6, 1.6)); q.addPath(dot(6.5, 11, 2.6)); q.addPath(dot(9.8, 15, 1.8))
        }
        return q
    }
}

struct ConsoleIcon: View {
    let id: String
    var body: some View { ConsoleGlyph(kind: ConsoleGlyph.kind(id)).stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).frame(width: 18, height: 18).accessibilityHidden(true) }
}
