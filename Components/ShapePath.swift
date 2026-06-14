import UIKit

/// Builds `UIBezierPath`s for canvas items. Shared by the interactive overlay
/// (`CAShapeLayer`) and the raster renderer (thumbnails / export).
enum ShapePath {
    /// The main outline path for an item, in the item's page coordinates.
    static func path(for item: CanvasItem) -> UIBezierPath {
        switch item.kind {
        case .rectangle:
            return UIBezierPath(rect: item.frame)
        case .roundedRectangle:
            return UIBezierPath(roundedRect: item.frame,
                                cornerRadius: min(item.frame.width, item.frame.height) * 0.18)
        case .process:
            return UIBezierPath(roundedRect: item.frame, cornerRadius: 12)
        case .stickyNote:
            return UIBezierPath(roundedRect: item.frame, cornerRadius: 6)
        case .predefinedProcess:
            return predefinedProcessPath(in: item.frame)
        case .card:
            return cardPath(in: item.frame)
        case .circle, .connectorNode:
            return UIBezierPath(ovalIn: item.frame)
        case .startEnd:
            return UIBezierPath(roundedRect: item.frame, cornerRadius: item.frame.height / 2)
        case .triangle:
            return trianglePath(in: item.frame)
        case .rightTriangle:
            return rightTrianglePath(in: item.frame)
        case .diamond, .decision:
            return diamondPath(in: item.frame)
        case .pentagon:
            return regularPolygonPath(in: item.frame, sides: 5, rotation: -.pi / 2)
        case .hexagon:
            return regularPolygonPath(in: item.frame, sides: 6, rotation: 0)
        case .preparation:
            return preparationPath(in: item.frame)
        case .star:
            return starPath(in: item.frame, points: 5, innerRatio: 0.4)
        case .parallelogram, .data:
            return parallelogramPath(in: item.frame)
        case .trapezoid:
            return trapezoidPath(in: item.frame)
        case .manualInput:
            return manualInputPath(in: item.frame)
        case .manualOperation:
            return manualOperationPath(in: item.frame)
        case .offPageConnector:
            return offPagePath(in: item.frame)
        case .document:
            return documentPath(in: item.frame)
        case .database:
            return databasePath(in: item.frame)
        case .line:
            return linePath(from: item.start, to: item.end)
        case .arrow, .connector:
            return arrowPath(from: item.start, to: item.end, lineWidth: item.lineWidth)
        case .doubleArrow:
            return doubleArrowPath(from: item.start, to: item.end, lineWidth: item.lineWidth)
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

    private static func rightTrianglePath(in r: CGRect) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
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

    /// A polygon inscribed in the item's rect (ellipse-fitted, so it fills the box).
    private static func regularPolygonPath(in r: CGRect, sides: Int, rotation: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        let cx = r.midX, cy = r.midY
        let rx = r.width / 2, ry = r.height / 2
        for i in 0..<sides {
            let a = rotation + (2 * .pi * CGFloat(i) / CGFloat(sides))
            let pt = CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.close()
        return p
    }

    /// Flowchart "preparation": an elongated hexagon with points left and right.
    private static func preparationPath(in r: CGRect) -> UIBezierPath {
        let inset = r.width * 0.2
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + inset, y: r.maxY))
        p.close()
        return p
    }

    private static func starPath(in r: CGRect, points: Int, innerRatio: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        let cx = r.midX, cy = r.midY
        let rx = r.width / 2, ry = r.height / 2
        let total = points * 2
        for i in 0..<total {
            let a = -CGFloat.pi / 2 + (.pi * CGFloat(i) / CGFloat(points))
            let scale = (i % 2 == 0) ? 1 : innerRatio
            let pt = CGPoint(x: cx + rx * scale * cos(a), y: cy + ry * scale * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.close()
        return p
    }

    private static func parallelogramPath(in r: CGRect) -> UIBezierPath {
        let inset = r.width * 0.25
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.minX + inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.close()
        return p
    }

    /// Trapezoid with a narrow top and a wide bottom.
    private static func trapezoidPath(in r: CGRect) -> UIBezierPath {
        let inset = r.width * 0.22
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.minX + inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.close()
        return p
    }

    /// Inverted trapezoid (wide top, narrow bottom) — flowchart "manual operation".
    private static func manualOperationPath(in r: CGRect) -> UIBezierPath {
        let inset = r.width * 0.22
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + inset, y: r.maxY))
        p.close()
        return p
    }

    /// Flowchart "manual input": rectangle whose top edge slopes up to the right.
    private static func manualInputPath(in r: CGRect) -> UIBezierPath {
        let slant = r.height * 0.28
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.minX, y: r.minY + slant))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.close()
        return p
    }

    /// Home-plate pentagon pointing down — flowchart "off-page connector".
    private static func offPagePath(in r: CGRect) -> UIBezierPath {
        let shoulder = r.height * 0.62
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + shoulder))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + shoulder))
        p.close()
        return p
    }

    /// Rectangle with a cut top-left corner — flowchart "card".
    private static func cardPath(in r: CGRect) -> UIBezierPath {
        let cut = min(r.width, r.height) * 0.25
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
        p.close()
        return p
    }

    /// Rectangle with two vertical bars inset from each side — "predefined process".
    private static func predefinedProcessPath(in r: CGRect) -> UIBezierPath {
        let bar = r.width * 0.12
        let p = UIBezierPath(rect: r)
        p.move(to: CGPoint(x: r.minX + bar, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + bar, y: r.maxY))
        p.move(to: CGPoint(x: r.maxX - bar, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - bar, y: r.maxY))
        return p
    }

    /// Rectangle whose bottom edge is a shallow double wave — flowchart "document".
    private static func documentPath(in r: CGRect) -> UIBezierPath {
        let wave = r.height * 0.14
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - wave))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY - wave),
                   controlPoint1: CGPoint(x: r.maxX - r.width * 0.18, y: r.maxY - wave * 2.4),
                   controlPoint2: CGPoint(x: r.midX + r.width * 0.18, y: r.maxY + wave * 0.6))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - wave),
                   controlPoint1: CGPoint(x: r.midX - r.width * 0.18, y: r.maxY - wave * 2.4),
                   controlPoint2: CGPoint(x: r.minX + r.width * 0.18, y: r.maxY + wave * 0.6))
        p.close()
        return p
    }

    /// A cylinder (database): elliptical top, straight sides, rounded bottom.
    private static func databasePath(in r: CGRect) -> UIBezierPath {
        let ell = min(r.height * 0.22, r.width * 0.5)
        let p = UIBezierPath()
        // Body outline (front), starting top-left.
        p.move(to: CGPoint(x: r.minX, y: r.minY + ell / 2))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - ell / 2))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - ell / 2),
                       controlPoint: CGPoint(x: r.midX, y: r.maxY + ell / 2))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + ell / 2))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + ell / 2),
                       controlPoint: CGPoint(x: r.midX, y: r.minY - ell / 2))
        // Top ellipse rim.
        p.append(UIBezierPath(ovalIn: CGRect(x: r.minX, y: r.minY, width: r.width, height: ell)))
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
        addArrowhead(to: p, at: b, from: a, lineWidth: lineWidth)
        return p
    }

    private static func doubleArrowPath(from a: CGPoint, to b: CGPoint, lineWidth: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: a)
        p.addLine(to: b)
        addArrowhead(to: p, at: b, from: a, lineWidth: lineWidth)
        addArrowhead(to: p, at: a, from: b, lineWidth: lineWidth)
        return p
    }

    /// Appends a V-shaped arrowhead at `tip`, opening toward `from`.
    private static func addArrowhead(to p: UIBezierPath, at tip: CGPoint, from: CGPoint, lineWidth: CGFloat) {
        let headLength = max(10, lineWidth * 4)
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let spread = CGFloat.pi / 7
        let left = CGPoint(x: tip.x - headLength * cos(angle - spread),
                           y: tip.y - headLength * sin(angle - spread))
        let right = CGPoint(x: tip.x - headLength * cos(angle + spread),
                            y: tip.y - headLength * sin(angle + spread))
        p.move(to: tip)
        p.addLine(to: left)
        p.move(to: tip)
        p.addLine(to: right)
    }
}
