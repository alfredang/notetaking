import UIKit
import PDFKit

/// Output formats for a single page export.
enum ExportFormat: String {
    case png, jpg, pdf
    var fileExtension: String { rawValue }
}

/// Renders pages / notebooks to shareable files (PNG, JPG, PDF).
@MainActor
enum ExportService {
    /// Writes a single page to a temporary file and returns its URL.
    static func exportPage(_ page: Page, as format: ExportFormat, name: String) throws -> URL {
        let data: Data
        switch format {
        case .png:
            data = PageRenderer.image(for: page, scale: 2).pngData() ?? Data()
        case .jpg:
            data = PageRenderer.image(for: page, scale: 2).jpegData(compressionQuality: 0.9) ?? Data()
        case .pdf:
            data = pdfData(for: [page])
        }
        return try write(data, name: name, ext: format.fileExtension)
    }

    /// Writes all of a notebook's pages to a combined PDF.
    static func exportNotebookPDF(_ notebook: Notebook) throws -> URL {
        let data = pdfData(for: notebook.orderedPages)
        return try write(data, name: notebook.title, ext: "pdf")
    }

    // MARK: - PDF rendering

    private static func pdfData(for pages: [Page]) -> Data {
        let bounds = CGRect(origin: .zero, size: PageGeometry.a4)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            for page in pages {
                ctx.beginPage()
                let image = PageRenderer.image(for: page, scale: 2)
                image.draw(in: bounds)
            }
            if pages.isEmpty { ctx.beginPage() }
        }
    }

    // MARK: - File output

    private static func write(_ data: Data, name: String, ext: String) throws -> URL {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName.isEmpty ? "Export" : safeName)
            .appendingPathExtension(ext)
        try data.write(to: url, options: .atomic)
        return url
    }
}
