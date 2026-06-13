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
    }

    /// The fill color for a given paper template.
    static func surfaceColor(for style: PaperStyle) -> UIColor {
        switch style {
        case .white: .white
        case .blackboard: UIColor(red: 0.09, green: 0.16, blue: 0.13, alpha: 1) // chalkboard green-black
        }
    }
}
