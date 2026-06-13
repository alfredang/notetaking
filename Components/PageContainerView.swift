import UIKit
import PencilKit

/// A `PKCanvasView` that owns its own undo manager so undo/redo reverse the
/// strokes drawn on this specific page (the responder-chain undo manager is
/// unreliable inside a SwiftUI hierarchy).
final class StrokeCanvasView: PKCanvasView {
    private let strokeUndoManager = UndoManager()
    override var undoManager: UndoManager? { strokeUndoManager }
}

/// A single A4 page: white rounded card hosting a PencilKit canvas with a
/// vector overlay on top.
final class PageContainerView: UIView {
    let page: Page
    let canvas: PKCanvasView
    let overlay: ShapeOverlayView
    private let contentView = UIView()
    private let backgroundImageView = UIImageView()
    private let footerLabel = UILabel()

    private static let footerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, h:mm a"
        return f
    }()

    init(page: Page) {
        self.page = page
        let pageSize = page.canvasSize
        self.canvas = StrokeCanvasView(frame: CGRect(origin: .zero, size: pageSize))
        self.overlay = ShapeOverlayView(frame: CGRect(origin: .zero, size: pageSize))
        super.init(frame: CGRect(origin: .zero, size: pageSize))

        // Soft shadow on the outer view.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)

        // Paper surface (white paper or dark blackboard).
        contentView.backgroundColor = PageContainerView.surfaceColor(for: page.paperStyle)
        contentView.layer.cornerRadius = Theme.pageCornerRadius
        contentView.clipsToBounds = true
        contentView.frame = bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(contentView)

        // Imported page background (e.g. a PDF page) below the ink.
        backgroundImageView.contentMode = .scaleAspectFit
        backgroundImageView.frame = contentView.bounds
        backgroundImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundImageView.image = page.backgroundData.isEmpty ? nil : UIImage(data: page.backgroundData)
        contentView.addSubview(backgroundImageView)

        // PencilKit canvas.
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        // PencilKit adapts ink colors to the interface style; in dark mode that
        // turns black ink light, making it invisible on the white page. Pin the
        // canvas to light so ink renders with its literal color.
        canvas.overrideUserInterfaceStyle = .light
        canvas.frame = contentView.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let drawing = try? PKDrawing(data: page.drawingData) {
            canvas.drawing = drawing
        }
        contentView.addSubview(canvas)

        // Vector overlay above the ink.
        overlay.frame = contentView.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.items = page.items
        overlay.isUserInteractionEnabled = false
        contentView.addSubview(overlay)

        // Page number + date/time stamp, bottom-right.
        footerLabel.font = .systemFont(ofSize: 19, weight: .medium)
        footerLabel.textAlignment = .right
        footerLabel.frame = CGRect(x: pageSize.width - 360, y: pageSize.height - 44,
                                   width: 336, height: 24)
        footerLabel.autoresizingMask = [.flexibleTopMargin, .flexibleLeftMargin]
        footerLabel.isUserInteractionEnabled = false
        contentView.addSubview(footerLabel)
        updateFooter()
    }

    /// Refreshes the bottom-right "Page N · date time" stamp.
    func updateFooter() {
        let show = UserDefaults.standard.object(forKey: "showPageNumbers") as? Bool ?? true
        footerLabel.isHidden = !show
        let onDark = page.paperStyle == .blackboard
        footerLabel.textColor = (onDark ? UIColor.white : UIColor.black).withAlphaComponent(0.45)
        let date = PageContainerView.footerDateFormatter.string(from: page.updatedAt)
        footerLabel.text = "Page \(page.pageIndex + 1)  ·  \(date)"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { page.canvasSize }

    /// Reloads visual content from the model (after clear / external change).
    func reloadFromModel() {
        if page.drawingData.isEmpty {
            canvas.drawing = PKDrawing()
        } else if let drawing = try? PKDrawing(data: page.drawingData) {
            canvas.drawing = drawing
        } else {
            canvas.drawing = PKDrawing()
        }
        overlay.items = page.items
        backgroundImageView.image = page.backgroundData.isEmpty ? nil : UIImage(data: page.backgroundData)
        contentView.backgroundColor = PageContainerView.surfaceColor(for: page.paperStyle)
        updateFooter()
    }

    // MARK: - Handwriting (ink) lasso selection

    /// Indices into `canvas.drawing.strokes` that are currently lasso-selected.
    private var selectedInkIndices: [Int] = []

    /// Selects strokes whose sampled path is mostly inside `polygon` (page
    /// coordinates); returns the union of their render bounds, or nil if none.
    func selectInk(in polygon: [CGPoint]) -> CGRect? {
        let strokes = canvas.drawing.strokes
        var indices: [Int] = []
        var bounds = CGRect.null
        for (i, stroke) in strokes.enumerated() {
            let pts = Self.sampledPoints(of: stroke)
            guard !pts.isEmpty else { continue }
            let inside = pts.reduce(0) { $0 + (Self.pointInPolygon($1, polygon) ? 1 : 0) }
            if inside * 2 >= pts.count {                 // majority of the stroke enclosed
                indices.append(i)
                bounds = bounds.union(stroke.renderBounds)
            }
        }
        selectedInkIndices = indices
        return indices.isEmpty ? nil : bounds
    }

    func clearInkSelection() { selectedInkIndices = [] }

    /// Recolors the selected strokes, preserving each stroke's ink type and geometry.
    func recolorSelectedInk(_ color: UIColor) {
        mutateSelectedInk { stroke in
            PKStroke(ink: PKInk(stroke.ink.inkType, color: color),
                     path: stroke.path, transform: stroke.transform, mask: stroke.mask)
        }
    }

    /// Translates the selected strokes by `offset`.
    func moveSelectedInk(by offset: CGSize) {
        let t = CGAffineTransform(translationX: offset.width, y: offset.height)
        mutateSelectedInk { stroke in
            PKStroke(ink: stroke.ink, path: stroke.path,
                     transform: stroke.transform.concatenating(t), mask: stroke.mask)
        }
    }

    func deleteSelectedInk() {
        guard !selectedInkIndices.isEmpty else { return }
        let drop = Set(selectedInkIndices)
        let kept = canvas.drawing.strokes.enumerated()
            .filter { !drop.contains($0.offset) }
            .map { $0.element }
        canvas.drawing = PKDrawing(strokes: kept)
        selectedInkIndices = []
    }

    private func mutateSelectedInk(_ transform: (PKStroke) -> PKStroke) {
        guard !selectedInkIndices.isEmpty else { return }
        var strokes = canvas.drawing.strokes
        for i in selectedInkIndices where i < strokes.count {
            strokes[i] = transform(strokes[i])
        }
        canvas.drawing = PKDrawing(strokes: strokes)
    }

    /// Evenly sampled points along a stroke, in page coordinates.
    private static func sampledPoints(of stroke: PKStroke) -> [CGPoint] {
        stroke.path.interpolatedPoints(by: .distance(16))
            .map { $0.location.applying(stroke.transform) }
    }

    private static func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        guard poly.count > 2 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if ((a.y > p.y) != (b.y > p.y)),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// The fill color for a given paper template.
    static func surfaceColor(for style: PaperStyle) -> UIColor {
        switch style {
        case .white: .white
        case .blackboard: UIColor(red: 0.09, green: 0.16, blue: 0.13, alpha: 1) // chalkboard green-black
        }
    }
}
