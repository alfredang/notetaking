import UIKit

/// Shared paper-template rendering: the solid surface color plus the ruled /
/// gridded / dotted overlay drawn on top. Used by the live page view
/// (`PageContainerView`) and the raster renderer (thumbnails / export).
enum PaperPattern {
    /// The fill color for a paper template.
    static func surfaceColor(for style: PaperStyle) -> UIColor {
        switch style {
        case .blackboard: UIColor(red: 0.09, green: 0.16, blue: 0.13, alpha: 1) // chalkboard green-black
        default: .white
        }
    }

    /// Ruling spacing (points), tuned to the A4 page width (794 pt).
    private static let gridSpacing: CGFloat = 32
    private static let dotSpacing: CGFloat = 28
    private static let lineSpacing: CGFloat = 40

    /// Draws the template's ruled pattern across `rect`. No-op for plain
    /// templates (white / blackboard).
    static func drawPattern(for style: PaperStyle, in rect: CGRect, context ctx: CGContext) {
        switch style {
        case .grid:
            ctx.saveGState()
            ctx.setStrokeColor(UIColor(white: 0, alpha: 0.10).cgColor)
            ctx.setLineWidth(0.75)
            var x = rect.minX + gridSpacing
            while x < rect.maxX {
                ctx.move(to: CGPoint(x: x, y: rect.minY))
                ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += gridSpacing
            }
            var y = rect.minY + gridSpacing
            while y < rect.maxY {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += gridSpacing
            }
            ctx.strokePath()
            ctx.restoreGState()

        case .dotted:
            ctx.saveGState()
            ctx.setFillColor(UIColor(white: 0, alpha: 0.25).cgColor)
            let r: CGFloat = 1.3
            var y = rect.minY + dotSpacing
            while y < rect.maxY {
                var x = rect.minX + dotSpacing
                while x < rect.maxX {
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += dotSpacing
                }
                y += dotSpacing
            }
            ctx.restoreGState()

        case .lined:
            ctx.saveGState()
            ctx.setStrokeColor(UIColor(red: 0.30, green: 0.45, blue: 0.85, alpha: 0.18).cgColor)
            ctx.setLineWidth(0.75)
            var y = rect.minY + lineSpacing
            while y < rect.maxY {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += lineSpacing
            }
            ctx.strokePath()
            ctx.restoreGState()

        case .white, .blackboard:
            break
        }
    }
}

/// A UIView that paints a page's paper template (solid surface + ruled pattern).
/// Lives below the ink/overlay inside `PageContainerView`.
final class PaperBackgroundView: UIView {
    var style: PaperStyle = .white {
        didSet {
            backgroundColor = PaperPattern.surfaceColor(for: style)
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        contentMode = .redraw
        backgroundColor = PaperPattern.surfaceColor(for: style)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        PaperPattern.drawPattern(for: style, in: bounds, context: ctx)
    }
}
