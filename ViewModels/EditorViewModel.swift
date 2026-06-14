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
    /// Whether fingers can draw. Off by default (GoodNotes-style): the Apple
    /// Pencil draws while a single finger scrolls/pans — so swiping up scrolls
    /// the page and can append a new one. Toggle on to draw with a finger.
    var allowsFingerDrawing: Bool = false

    /// Hides the floating tool palette (toggled by a double-tap on the Pencil).
    var isPaletteHidden: Bool = false

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

    /// A value that changes whenever any tool/ink setting changes. The editor's
    /// canvas host reads this so SwiftUI re-renders (and pushes the new tool to
    /// the `PKCanvasView`) the moment the user picks a tool, color, or width.
    var toolStateToken: String {
        "\(tool)|\(penColor)|\(penWidth)|\(highlighterColor)|\(highlighterWidth)|\(eraserWidth)|\(allowsFingerDrawing)"
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
                text: kind.defaultLabel
            )
        }
        // Flowchart nodes default to a solid white fill (so labels are readable
        // and they look like proper boxes, not just outlines).
        let fill = kind.isNode ? RGBAColor(red: 1, green: 1, blue: 1) : shapeFillColor
        return CanvasItem(
            kind: kind,
            frame: frame,
            start: start,
            end: end,
            strokeColor: shapeStrokeColor,
            fillColor: fill,
            lineWidth: shapeLineWidth,
            opacity: shapeOpacity,
            text: kind.hasLabel ? kind.defaultLabel : nil
        )
    }
}
