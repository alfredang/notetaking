import Foundation
import SwiftData

/// A voice memo attached to a notebook. The recording is stored inline (external
/// storage) so it syncs through CloudKit alongside the notebook's pages.
@Model
final class AudioNote {
    // CloudKit-compatible: defaulted attributes, no unique constraint.
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    /// Recording length in seconds.
    var duration: Double = 0

    /// Encoded audio (m4a / AAC).
    @Attribute(.externalStorage) var audioData: Data = Data()

    /// Owning notebook (inverse of `Notebook.audioNotes`).
    var notebook: Notebook?

    init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = .now,
        duration: Double = 0,
        audioData: Data = Data(),
        notebook: Notebook? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioData = audioData
        self.notebook = notebook
    }
}
