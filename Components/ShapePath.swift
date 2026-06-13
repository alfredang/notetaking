import UIKit

/// Builds `UIBezierPath`s for canvas items. Shared by the interactive overlay
/// (`CAShapeLayer`) and the raster renderer (thumbnails / export).
enum ShapePath {
    /// The main outline path for an item, in the item's page coordinates.
    static func path(for item: CanvasItem) -> UIBezierPath {
        switch item.kind {
        case .rectangle:
            return UIBezierPath(rect: item.frame)
        case .process:
            return UIBezierPath(roundedRect: item.frame, cornerRadius: 12)
        case .stickyNote:
            return UIBezierPath(roundedRect: item.frame, cornerRadius: 6)
        case .circle:
            return UIBezierPath(ovalIn: item.frame)
        case .startEnd:
            return UIBezierPath(roundedRect: item.frame, cornerRadius: item.frame.height / 2)
        case .triangle:
            return trianglePath(in: item.frame)
        case .diamond, .decision:
            return diamondPath(in: item.frame)
        case .line:
            return linePath(from: item.start, to: item.end)
        case .arrow, .connector:
            return arrowPath(from: item.start, to: item.end, lineWidth: item.lineWidth)
        }
    }

    private static func trianglePath(in r: CGRect) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.close()
        return p
    }

    private static func diamondPath(in r: CGRect) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.close()
        return p
    }

    private static func linePath(from a: CGPoint, to b: CGPoint) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: a)
        p.addLine(to: b)
        return p
    }

    private static func arrowPath(from a: CGPoint, to b: CGPoint, lineWidth: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: a)
        p.addLine(to: b)
        // Arrowhead
        let headLength = max(10, lineWidth * 4)
        let angle = atan2(b.y - a.y, b.x - a.x)
        let spread = CGFloat.pi / 7
        let left = CGPoint(
            x: b.x - headLength * cos(angle - spread),
            y: b.y - headLength * sin(angle - spread)
        )
        let right = CGPoint(
            x: b.x - headLength * cos(angle + spread),
            y: b.y - headLength * sin(angle + spread)
        )
        p.move(to: b)
        p.addLine(to: left)
        p.move(to: b)
        p.addLine(to: right)
        return p
    }
}
