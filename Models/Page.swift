import Foundation
import SwiftData
import CoreGraphics

/// Visual template for a page's paper surface.
enum PaperStyle: String, CaseIterable, Identifiable, Sendable {
    case white
    case blackboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: "White"
        case .blackboard: "Blackboard"
        }
    }

    /// A sensible default ink color so strokes are visible on this surface
    /// (dark ink on white paper, white chalk on a blackboard).
    var defaultInkColor: RGBAColor {
        switch self {
        case .white: .black
        case .blackboard: RGBAColor(red: 1, green: 1, blue: 1)
        }
    }
}

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

    /// The page's paper template (white paper vs. dark blackboard). Stored as a
    /// raw string for CloudKit compatibility; read through `paperStyle`.
    var paperStyleRaw: String = PaperStyle.white.rawValue

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
        paperStyle: PaperStyle = .white,
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
        self.paperStyleRaw = paperStyle.rawValue
        self.notebook = notebook
    }

    /// The page's paper template, derived from `paperStyleRaw`.
    var paperStyle: PaperStyle {
        get { PaperStyle(rawValue: paperStyleRaw) ?? .white }
        set { paperStyleRaw = newValue.rawValue }
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
