import Foundation
import SwiftData
import CoreGraphics

/// A single A4 page. Stores the PencilKit drawing as raw data and the vector
/// overlay items as JSON-encoded `Data`.
@Model
final class Page {
    // CloudKit requires every attribute to be optional or carry a default value,
    // and forbids `.unique` constraints — UUIDs stay unique by generation.
    var id: UUID = UUID()
    var pageIndex: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// Serialized `PKDrawing` (`drawing.dataRepresentation()`).
    @Attribute(.externalStorage) var drawingData: Data = Data()

    /// JSON-encoded `[CanvasItem]` for the shape/flowchart overlay.
    @Attribute(.externalStorage) var shapesData: Data = Data()

    /// Text recognized from the handwriting + shape labels (Vision OCR), kept in
    /// sync after edits so the dashboard can search inside notes.
    var recognizedText: String = ""

    /// Optional page background raster (PNG) — e.g. an imported PDF page that the
    /// user annotates on top of. Empty for blank pages.
    @Attribute(.externalStorage) var backgroundData: Data = Data()

    /// How many stacked A4 heights this page spans. 1 = a standard page; larger
    /// values give an extended, continuous ("infinite") vertical canvas.
    var heightUnits: Int = 1

    /// Owning notebook (inverse of `Notebook.pages`).
    var notebook: Notebook?

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        drawingData: Data = Data(),
        shapesData: Data = Data(),
        recognizedText: String = "",
        backgroundData: Data = Data(),
        heightUnits: Int = 1,
        notebook: Notebook? = nil
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.drawingData = drawingData
        self.shapesData = shapesData
        self.recognizedText = recognizedText
        self.backgroundData = backgroundData
        self.heightUnits = heightUnits
        self.notebook = notebook
    }

    /// The page's canvas size in points — A4 width, height scaled by `heightUnits`.
    var canvasSize: CGSize {
        CGSize(width: PageGeometry.a4.width, height: PageGeometry.a4.height * CGFloat(max(1, heightUnits)))
    }

    /// Decoded overlay items. Setting re-encodes to `shapesData`.
    var items: [CanvasItem] {
        get {
            guard !shapesData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([CanvasItem].self, from: shapesData)) ?? []
        }
        set {
            shapesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    func touch(_ date: Date = .now) {
        updatedAt = date
        notebook?.touch(date)
    }
}
