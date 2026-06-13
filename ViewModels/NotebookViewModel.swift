import Foundation
import Observation

/// Drives a single open notebook: page list and page management.
@MainActor
@Observable
final class NotebookViewModel {
    let notebook: Notebook
    private let repository: any PageRepositoryProtocol

    /// Index of the page currently focused in the editor.
    var selectedPageIndex: Int = 0
    /// Token bumped to invalidate thumbnails after edits.
    var refreshToken: Int = 0
    var errorMessage: String?

    init(notebook: Notebook, repository: any PageRepositoryProtocol) {
        self.notebook = notebook
        self.repository = repository
        // Ensure a notebook always has at least one page.
        if notebook.orderedPages.isEmpty {
            _ = try? repository.addPage(to: notebook, at: nil)
        }
    }

    var pages: [Page] { notebook.orderedPages }

    var selectedPage: Page? {
        guard pages.indices.contains(selectedPageIndex) else { return pages.first }
        return pages[selectedPageIndex]
    }

    // MARK: - Page actions

    func addPageAtEnd() {
        perform { try repository.addPage(to: notebook, at: nil) }
        selectedPageIndex = pages.count - 1
    }

    func insertPage(before index: Int) {
        perform { try repository.addPage(to: notebook, at: index) }
        selectedPageIndex = index
    }

    func insertPage(after index: Int) {
        perform { try repository.addPage(to: notebook, at: index + 1) }
        selectedPageIndex = min(index + 1, pages.count - 1)
    }

    func duplicate(_ page: Page) {
        perform { try repository.duplicate(page, in: notebook) }
    }

    func delete(_ page: Page) {
        guard pages.count > 1 else { return } // keep at least one page
        let removedIndex = pages.firstIndex { $0.id == page.id } ?? 0
        do {
            try repository.delete(page, from: notebook)
            selectedPageIndex = min(removedIndex, pages.count - 1)
            bump()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear(_ page: Page) {
        do {
            try repository.clear(page)
            bump()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func movePages(from source: IndexSet, to destination: Int) {
        do {
            try repository.move(in: notebook, from: source, to: destination)
            bump()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func bump() { refreshToken &+= 1 }

    private func perform(_ action: () throws -> Page) {
        do {
            _ = try action()
            bump()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
