import SwiftUI

/// A small outlined preview of a `ShapeKind`, drawn with the exact same geometry
/// (`ShapePath`) used on the canvas — so the palette icon always matches what the
/// tool actually draws. Inherits the surrounding `foregroundStyle`.
struct ShapeGlyph: View {
    let kind: ShapeKind
    var lineWidth: CGFloat = 1.7

    var body: some View {
        GeometryReader { geo in
            let item = Self.item(for: kind, in: geo.size)
            Path(ShapePath.path(for: item).cgPath)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    private static func item(for kind: ShapeKind, in size: CGSize) -> CanvasItem {
        let r = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
        if kind.isLineLike {
            let start: CGPoint
            let end: CGPoint
            if kind == .line {
                start = CGPoint(x: r.minX, y: r.maxY)
                end = CGPoint(x: r.maxX, y: r.minY)
            } else {
                start = CGPoint(x: r.minX, y: r.midY)
                end = CGPoint(x: r.maxX, y: r.midY)
            }
            return CanvasItem(kind: kind, start: start, end: end, lineWidth: 1.6)
        }
        return CanvasItem(kind: kind, frame: r, lineWidth: 1.6)
    }
}

/// A small preview tile of a paper template: its surface color plus a scaled-down
/// hint of its ruled / gridded / dotted pattern.
struct PaperSwatch: View {
    let style: PaperStyle
    var size = CGSize(width: 44, height: 32)

    var body: some View {
        Canvas { ctx, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            ctx.fill(Path(rect), with: .color(Color(PaperPattern.surfaceColor(for: style))))
            drawPattern(in: &ctx, rect: rect)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.18), lineWidth: 1))
    }

    private func drawPattern(in ctx: inout GraphicsContext, rect: CGRect) {
        switch style {
        case .grid:
            var path = Path()
            var x = rect.minX + 7
            while x < rect.maxX { path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY)); x += 7 }
            var y = rect.minY + 7
            while y < rect.maxY { path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y)); y += 7 }
            ctx.stroke(path, with: .color(.black.opacity(0.22)), lineWidth: 0.5)
        case .dotted:
            var y = rect.minY + 7
            while y < rect.maxY {
                var x = rect.minX + 7
                while x < rect.maxX {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)),
                             with: .color(.black.opacity(0.35)))
                    x += 7
                }
                y += 7
            }
        case .lined:
            var path = Path()
            var y = rect.minY + 8
            while y < rect.maxY { path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y)); y += 8 }
            ctx.stroke(path, with: .color(Color(red: 0.30, green: 0.45, blue: 0.85).opacity(0.5)), lineWidth: 0.5)
        case .white, .blackboard:
            break
        }
    }
}
