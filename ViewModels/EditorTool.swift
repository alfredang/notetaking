import SwiftUI

/// The active editing tool.
enum EditorTool: Equatable {
    case pen
    case highlighter
    case eraserPixel
    case eraserObject
    case selection
    case shape(ShapeKind)
    case flowchart(ShapeKind)

    var isInking: Bool { self == .pen || self == .highlighter }
    var isEraser: Bool { self == .eraserPixel || self == .eraserObject }

    /// Whether this tool draws on the vector overlay rather than the PencilKit canvas.
    var isOverlayTool: Bool {
        switch self {
        case .shape, .flowchart, .selection: true
        default: false
        }
    }

    /// The overlay shape kind this tool creates, if any.
    var overlayKind: ShapeKind? {
        switch self {
        case .shape(let k), .flowchart(let k): k
        default: nil
        }
    }
}

/// Predefined pen widths (px), per spec.
enum ToolDefaults {
    static let penSizes: [CGFloat] = [1, 2, 4, 6, 8, 12, 16, 20]
    static let highlighterSizes: [CGFloat] = [5, 10, 20, 30]
    static let shapeWidths: [CGFloat] = [1, 2, 4, 6, 8, 10]

    /// Standard color palette, per spec.
    static let palette: [RGBAColor] = [
        RGBAColor(.black),
        RGBAColor(red: 0.0, green: 0.48, blue: 1.0),   // Blue
        RGBAColor(red: 0.96, green: 0.26, blue: 0.21),  // Red
        RGBAColor(red: 0.30, green: 0.69, blue: 0.31),  // Green
        RGBAColor(red: 1.0, green: 0.60, blue: 0.0),    // Orange
        RGBAColor(red: 0.61, green: 0.15, blue: 0.69),  // Purple
        RGBAColor(red: 1.0, green: 0.84, blue: 0.0),    // Yellow
        RGBAColor(red: 0.50, green: 0.50, blue: 0.50)   // Gray
    ]
}
