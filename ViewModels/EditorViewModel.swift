import SwiftUI
import PencilKit
import Observation

/// Holds the editor's tool palette state and exposes the resolved `PKTool`.
@MainActor
@Observable
final class EditorViewModel {
    // Active tool
    var tool: EditorTool = .pen

    // Ink configuration
    var penColor: RGBAColor = .black
    var penWidth: CGFloat = 2
    var highlighterColor: RGBAColor = RGBAColor(red: 1.0, green: 0.84, blue: 0.0)
    var highlighterWidth: CGFloat = 10
    var eraserWidth: CGFloat = 20

    // Shape / flowchart configuration
    var shapeStrokeColor: RGBAColor = .black
    var shapeFillColor: RGBAColor = .clear
    var shapeLineWidth: CGFloat = 2
    var shapeOpacity: CGFloat = 1

    // Canvas
    var zoomScale: CGFloat = 1
    /// Whether fingers can draw (otherwise fingers pan/zoom, Pencil draws).
    var allowsFingerDrawing: Bool = false

    /// The PencilKit tool resolved from the current state.
    var pkTool: PKTool {
        switch tool {
        case .pen:
            return PKInkingTool(.pen, color: penColor.uiColor, width: penWidth)
        case .highlighter:
            return PKInkingTool(.marker, color: highlighterColor.uiColor, width: highlighterWidth)
        case .eraserPixel:
            return PKEraserTool(.bitmap, width: eraserWidth)
        case .eraserObject:
            return PKEraserTool(.vector)
        case .selection:
            return PKLassoTool()
        case .shape, .flowchart:
            // Overlay tools don't drive the PencilKit canvas; keep a no-op lasso.
            return PKLassoTool()
        }
    }

    /// The drawing policy: pencil-only unless the user opts into finger drawing.
    var drawingPolicy: PKCanvasViewDrawingPolicy {
        allowsFingerDrawing ? .anyInput : .pencilOnly
    }

    /// Style for a newly created overlay item using the current settings.
    func makeItem(kind: ShapeKind, frame: CGRect = .zero, start: CGPoint? = nil, end: CGPoint? = nil) -> CanvasItem {
        // Sticky notes ignore the active stroke/fill and use a warm card style.
        if kind == .stickyNote {
            return CanvasItem(
                kind: kind,
                frame: frame,
                strokeColor: RGBAColor(red: 0.30, green: 0.26, blue: 0.0),
                fillColor: RGBAColor(red: 1.0, green: 0.90, blue: 0.40),
                lineWidth: 0,
                opacity: 1,
                text: defaultLabel(for: kind)
            )
        }
        return CanvasItem(
            kind: kind,
            frame: frame,
            start: start,
            end: end,
            strokeColor: shapeStrokeColor,
            fillColor: shapeFillColor,
            lineWidth: shapeLineWidth,
            opacity: shapeOpacity,
            text: kind.hasLabel ? defaultLabel(for: kind) : nil
        )
    }

    private func defaultLabel(for kind: ShapeKind) -> String {
        switch kind {
        case .process: "Process"
        case .decision: "Decision"
        case .startEnd: "Start"
        case .stickyNote: "Note"
        default: ""
        }
    }
}
