import Foundation
import SwiftData

/// Debounced auto-save. Every stroke / shape change schedules a save that
/// coalesces rapid edits into a single context save (~0.4s after the last edit).
@MainActor
final class AutoSaveService {
    private let context: ModelContext
    private var pendingTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private let debounce: Duration

    init(context: ModelContext, debounce: Duration = .milliseconds(400)) {
        self.context = context
        self.debounce = debounce
    }

    /// Schedules a debounced save. `touch` runs immediately to update timestamps.
    func scheduleSave(touching page: Page?) {
        page?.touch()
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounce)
            if Task.isCancelled { return }
            self.saveNow()
        }
        scheduleTextIndex(for: page)
    }

    /// Re-runs OCR for the edited page on a longer debounce (it's expensive) and
    /// persists the recognized text so the dashboard search stays current.
    private func scheduleTextIndex(for page: Page?) {
        guard let page else { return }
        indexTask?.cancel()
        indexTask = Task { [weak self, weak page] in
            try? await Task.sleep(for: .seconds(1.5))
            if Task.isCancelled { return }
            guard let self, let page else { return }
            let png = PageRenderer.image(for: page, scale: 1).pngData() ?? Data()
            let text = await TextRecognitionService.recognizeText(fromPNG: png)
            if Task.isCancelled { return }
            guard page.recognizedText != text else { return }
            page.recognizedText = text
            self.saveNow()
        }
    }

    /// Saves immediately (e.g. on leaving the editor or backgrounding).
    func saveNow() {
        pendingTask?.cancel()
        pendingTask = nil
        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            // Auto-save is best-effort; surface in console for debugging.
            print("AutoSave failed: \(error)")
        }
    }
}
