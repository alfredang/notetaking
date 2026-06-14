import PencilKit
import UIKit

/// Converts a freehand stroke into a clean straight segment between its first and
/// last points — used by the "draw a line and hold the end" gesture so a wobbly
/// pencil line snaps to a ruler-straight one.
@MainActor
enum StrokeStraightener {
    /// Returns a copy of `drawing` whose most recent stroke has been straightened,
    /// or nil if there's nothing to straighten.
    static func straightenLast(in drawing: PKDrawing) -> PKDrawing? {
        var strokes = drawing.strokes
        guard let last = strokes.popLast(), let straight = straighten(last) else { return nil }
        strokes.append(straight)
        return PKDrawing(strokes: strokes)
    }

    static func straighten(_ stroke: PKStroke) -> PKStroke? {
        let path = stroke.path
        guard path.count >= 2 else { return nil }
        let t = stroke.transform
        let first = path[0]
        let last = path[path.count - 1]
        let p0 = first.location.applying(t)
        let p1 = last.location.applying(t)
        let dist = hypot(p1.x - p0.x, p1.y - p0.y)
        guard dist > 2 else { return nil }

        // Sample evenly along the straight segment, copying the original stroke's
        // dynamics (size / pressure) from the nearer endpoint so taper is kept.
        let steps = max(2, min(64, Int(dist / 8)))
        let totalTime = max(last.timeOffset - first.timeOffset, 0.001)
        var points: [PKStrokePoint] = []
        points.reserveCapacity(steps + 1)
        for i in 0...steps {
            let f = CGFloat(i) / CGFloat(steps)
            let loc = CGPoint(x: p0.x + (p1.x - p0.x) * f, y: p0.y + (p1.y - p0.y) * f)
            let ref = f < 0.5 ? first : last
            points.append(PKStrokePoint(
                location: loc,
                timeOffset: first.timeOffset + Double(f) * totalTime,
                size: ref.size,
                opacity: ref.opacity,
                force: ref.force,
                azimuth: ref.azimuth,
                altitude: ref.altitude
            ))
        }
        let newPath = PKStrokePath(controlPoints: points, creationDate: path.creationDate)
        return PKStroke(ink: stroke.ink, path: newPath, transform: .identity, mask: stroke.mask)
    }
}
