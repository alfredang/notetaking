import Foundation
import SwiftData

/// A single A4 page. Stores the PencilKit drawing as raw data and the vector
/// overlay items as JSON-encoded `Data`.
@Model
final class Page {
    @Attribute(.unique) var id: UUID
    var pageIndex: Int
    var createdAt: Date
    var updatedAt: Date

    /// Serialized `PKDrawing` (`drawing.dataRepresentation()`).
    @Attribute(.externalStorage) var drawingData: Data

    /// JSON-encoded `[CanvasItem]` for the shape/flowchart overlay.
    @Attribute(.externalStorage) var shapesData: Data

    /// Owning notebook (inverse of `Notebook.pages`).
    var notebook: Notebook?

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        drawingData: Data = Data(),
        shapesData: Data = Data(),
        notebook: Notebook? = nil
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.drawingData = drawingData
        self.shapesData = shapesData
        self.notebook = notebook
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
