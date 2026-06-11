import UIKit
import PencilKit

/// A single A4 page: white rounded card hosting a PencilKit canvas with a
/// vector overlay on top.
final class PageContainerView: UIView {
    let page: Page
    let canvas: PKCanvasView
    let overlay: ShapeOverlayView
    private let contentView = UIView()

    init(page: Page) {
        self.page = page
        self.canvas = PKCanvasView(frame: CGRect(origin: .zero, size: PageGeometry.a4))
        self.overlay = ShapeOverlayView(frame: CGRect(origin: .zero, size: PageGeometry.a4))
        super.init(frame: CGRect(origin: .zero, size: PageGeometry.a4))

        // Soft shadow on the outer view.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)

        // White rounded paper.
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = Theme.pageCornerRadius
        contentView.clipsToBounds = true
        contentView.frame = bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(contentView)

        // PencilKit canvas.
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
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

    override var intrinsicContentSize: CGSize { PageGeometry.a4 }

    /// Reloads visual content from the model (after clear / external change).
    func reloadFromModel() {
        if let drawing = try? PKDrawing(data: page.drawingData) {
            canvas.drawing = drawing
        } else {
            canvas.drawing = PKDrawing()
        }
        overlay.items = page.items
    }
}
