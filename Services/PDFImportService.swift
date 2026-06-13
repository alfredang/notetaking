import UIKit
import PDFKit

/// Renders an imported PDF into per-page raster backgrounds sized to the app's
/// A4 page, so the pages can be annotated with the normal drawing tools.
@MainActor
enum PDFImportService {
    /// Returns one PNG `Data` per PDF page, each drawn to fit the A4 page size
    /// (aspect-preserved, centered on white). Returns an empty array on failure.
    static func renderBackgrounds(from url: URL) -> [Data] {
        // Security-scoped access is needed for files chosen via the document picker.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else { return [] }

        let pageSize = PageGeometry.a4
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: pageSize, format: format)

        var results: [Data] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let pdfBounds = page.bounds(for: .mediaBox)
            let scale = min(pageSize.width / pdfBounds.width, pageSize.height / pdfBounds.height)
            let drawSize = CGSize(width: pdfBounds.width * scale, height: pdfBounds.height * scale)
            let origin = CGPoint(
                x: (pageSize.width - drawSize.width) / 2,
                y: (pageSize.height - drawSize.height) / 2
            )

            let image = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: pageSize))

                let cg = ctx.cgContext
                cg.saveGState()
                // Flip into PDF (bottom-left origin) coordinates within the draw rect.
                cg.translateBy(x: origin.x, y: origin.y + drawSize.height)
                cg.scaleBy(x: scale, y: -scale)
                cg.translateBy(x: -pdfBounds.origin.x, y: -pdfBounds.origin.y)
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
            }
            if let data = image.pngData() { results.append(data) }
        }
        return results
    }
}
