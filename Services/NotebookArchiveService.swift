import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Portable, Codable snapshot of a notebook for sharing as a `.notebook` file.
private struct NotebookArchive: Codable {
    var title: String
    var pages: [PageArchive]
    var audioNotes: [AudioArchive]
}

private struct PageArchive: Codable {
    var pageIndex: Int
    var drawingData: Data
    var shapesData: Data
    var backgroundData: Data
    var recognizedText: String
    var heightUnits: Int
}

private struct AudioArchive: Codable {
    var title: String
    var duration: Double
    var audioData: Data
}

/// Exports a notebook to a shareable `.notebook` bundle and imports it back.
/// This is the app's "sharing" path: send the file to someone (AirDrop, mail,
/// Files…) and they import a full copy — pages, PDF backgrounds, voice memos.
@MainActor
enum NotebookArchiveService {
    static let fileExtension = "notebook"

    /// The custom document type (declared in Info.plist), falling back to data.
    static var contentType: UTType { UTType("com.tertiaryinfotech.notepadapp.notebook") ?? .data }

    /// Writes the notebook to a temp `.notebook` file and returns its URL.
    static func export(_ notebook: Notebook) throws -> URL {
        let archive = NotebookArchive(
            title: notebook.title,
            pages: notebook.orderedPages.map {
                PageArchive(
                    pageIndex: $0.pageIndex,
                    drawingData: $0.drawingData,
                    shapesData: $0.shapesData,
                    backgroundData: $0.backgroundData,
                    recognizedText: $0.recognizedText,
                    heightUnits: $0.heightUnits
                )
            },
            audioNotes: notebook.orderedAudioNotes.map {
                AudioArchive(title: $0.title, duration: $0.duration, audioData: $0.audioData)
            }
        )
        let data = try JSONEncoder().encode(archive)
        let safeName = notebook.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName.isEmpty ? "Notebook" : safeName)
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Imports a `.notebook` file as a brand-new top-level notebook.
    @discardableResult
    static func importArchive(from url: URL, into context: ModelContext) throws -> Notebook {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let archive = try JSONDecoder().decode(NotebookArchive.self, from: data)

        let notebook = Notebook(title: archive.title.isEmpty ? "Imported Notebook" : archive.title)
        context.insert(notebook)

        var pages: [Page] = []
        for pa in archive.pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            let page = Page(
                pageIndex: pa.pageIndex,
                drawingData: pa.drawingData,
                shapesData: pa.shapesData,
                recognizedText: pa.recognizedText,
                backgroundData: pa.backgroundData,
                heightUnits: pa.heightUnits,
                notebook: notebook
            )
            context.insert(page)
            pages.append(page)
        }
        notebook.pages = pages

        for aa in archive.audioNotes {
            let note = AudioNote(title: aa.title, duration: aa.duration, audioData: aa.audioData, notebook: notebook)
            context.insert(note)
        }

        try context.save()
        return notebook
    }
}
