import Foundation
import CoreGraphics

/// The kind of vector item drawn on the shape-overlay layer.
/// Covers both plain shapes and flowchart components/connectors.
enum ShapeKind: String, Codable, CaseIterable, Sendable {
    // Plain shapes
    case rectangle
    case circle
    case triangle
    case diamond
    case line
    case arrow
    // Flowchart nodes
    case process        // rounded rectangle
    case decision       // diamond with text
    case startEnd       // capsule (terminator)
    // Flowchart connector
    case connector
    // Sticky note (filled card with text)
    case stickyNote

    var isNode: Bool {
        switch self {
        case .process, .decision, .startEnd: true
        default: false
        }
    }

    var isConnector: Bool { self == .connector }

    /// Items that render an editable text label (flowchart nodes + sticky notes).
    var hasLabel: Bool { isNode || self == .stickyNote }

    /// Line-like shapes are defined by two endpoints rather than a rect.
    var isLineLike: Bool {
        switch self {
        case .line, .arrow, .connector: true
        default: false
        }
    }
}

/// An RGBA color encoded as Codable components (SwiftUI/UIColor are not Codable).
struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static let black = RGBAColor(red: 0, green: 0, blue: 0)
    static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
    static let blue = RGBAColor(red: 0.0, green: 0.48, blue: 1.0)
}

/// A single vector item on a page's overlay layer.
/// Shapes use `frame`; line-like items use `start`/`end`; connectors may bind to node ids.
struct CanvasItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var kind: ShapeKind

    // Rect-based geometry (shapes & nodes), in A4 page coordinates.
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    // Line-like geometry (line/arrow/connector). When nil, derived from frame.
    var startX: CGFloat?
    var startY: CGFloat?
    var endX: CGFloat?
    var endY: CGFloat?

    // Styling
    var strokeColor: RGBAColor
    var fillColor: RGBAColor
    var lineWidth: CGFloat
    var opacity: CGFloat

    // Flowchart connector bindings (optional). Anchor is a unit point on the node edge.
    var sourceItemID: UUID?
    var targetItemID: UUID?

    // Optional label (flowchart nodes).
    var text: String?

    init(
        id: UUID = UUID(),
        kind: ShapeKind,
        frame: CGRect = .zero,
        start: CGPoint? = nil,
        end: CGPoint? = nil,
        strokeColor: RGBAColor = .black,
        fillColor: RGBAColor = .clear,
        lineWidth: CGFloat = 2,
        opacity: CGFloat = 1,
        sourceItemID: UUID? = nil,
        targetItemID: UUID? = nil,
        text: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.x = frame.origin.x
        self.y = frame.origin.y
        self.width = frame.size.width
        self.height = frame.size.height
        self.startX = start?.x
        self.startY = start?.y
        self.endX = end?.x
        self.endY = end?.y
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.sourceItemID = sourceItemID
        self.targetItemID = targetItemID
        self.text = text
    }

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = newValue.size.width
            height = newValue.size.height
        }
    }

    var start: CGPoint {
        get { CGPoint(x: startX ?? x, y: startY ?? y) }
        set { startX = newValue.x; startY = newValue.y }
    }

    var end: CGPoint {
        get { CGPoint(x: endX ?? (x + width), y: endY ?? (y + height)) }
        set { endX = newValue.x; endY = newValue.y }
    }

    /// Center point used as a connection anchor for flowchart connectors.
    var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }
}
