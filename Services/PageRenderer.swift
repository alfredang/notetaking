import UIKit
import PencilKit
import AVFoundation

/// Renders a page (PencilKit drawing + vector overlay) to a raster image.
/// Used for thumbnails and PNG/JPG/PDF export.
enum PageRenderer {
    /// Renders the page at the full A4 point size, scaled by `scale`.
    static func image(for page: Page, scale: CGFloat = 1, background: UIColor = .white) -> UIImage {
        let size = page.canvasSize
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            background.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Imported background (e.g. a PDF page) sits beneath everything,
            // aspect-fit to match the on-screen image view.
            if !page.backgroundData.isEmpty, let bg = UIImage(data: page.backgroundData) {
                let rect = AVMakeRect(aspectRatio: bg.size, insideRect: CGRect(origin: .zero, size: size))
                bg.draw(in: rect)
            }

            // Vector overlay below ink? Draw overlay first, then ink on top to
            // match on-screen layering (ink can be erased independently).
            drawOverlay(items: page.items, in: ctx.cgContext)

            if let drawing = try? PKDrawing(data: page.drawingData) {
                let inkImage = drawing.image(from: CGRect(origin: .zero, size: size), scale: scale)
                inkImage.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    /// Renders a downscaled thumbnail constrained to `maxWidth`.
    static func thumbnail(for page: Page, maxWidth: CGFloat) -> UIImage {
        let scale = maxWidth / PageGeometry.a4.width
        return image(for: page, scale: max(scale, 0.1))
    }

    static func drawOverlay(items: [CanvasItem], in context: CGContext) {
        for item in items {
            context.saveGState()
            context.setAlpha(item.opacity)

            let path = ShapePath.path(for: item)
            // Fill (only closed, non-line shapes).
            if !item.kind.isLineLike, item.fillColor.alpha > 0 {
                context.setFillColor(item.fillColor.cgColor)
                context.addPath(path.cgPath)
                context.fillPath()
            }
            // Stroke
            context.setStrokeColor(item.strokeColor.cgColor)
            context.setLineWidth(item.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(path.cgPath)
            context.strokePath()

            // Node / sticky-note label
            if let text = item.text, !text.isEmpty, item.kind.hasLabel {
                // Sticky notes read as top-left text; flowchart nodes center theirs.
                let alignment: NSTextAlignment = item.kind == .stickyNote ? .natural : .center
                drawLabel(text, in: item.frame, color: item.strokeColor.uiColor, alignment: alignment)
            }
            context.restoreGState()
        }
    }

    private static func drawLabel(_ text: String, in rect: CGRect, color: UIColor, alignment: NSTextAlignment = .center) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        let inset = rect.insetBy(dx: 8, dy: 8)
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: inset.width, height: inset.height),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        // Sticky notes anchor text to the top; everything else is vertically centered.
        let drawRect = alignment == .natural
            ? CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height)
            : CGRect(x: inset.minX, y: inset.midY - bounding.height / 2, width: inset.width, height: bounding.height)
        (text as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
    }
}
