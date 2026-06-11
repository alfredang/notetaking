import Foundation
import SwiftData

/// Debounced auto-save. Every stroke / shape change schedules a save that
/// coalesces rapid edits into a single context save (~0.4s after the last edit).
@MainActor
final class AutoSaveService {
    private let context: ModelContext
    private var pendingTask: Task<Void, Never>?
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
