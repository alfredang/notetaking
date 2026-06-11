import Foundation
import Observation

/// Drives the dashboard: notebook listing, sorting, search and CRUD.
@MainActor
@Observable
final class DashboardViewModel {
    private let repository: any NotebookRepositoryProtocol
    /// When set, the view model browses this notebook's sub-notebooks instead of top-level.
    private let parent: Notebook?

    var notebooks: [Notebook] = []
    var sort: NotebookSort = .lastModified {
        didSet { reload() }
    }
    var searchText: String = ""
    var errorMessage: String?

    init(repository: any NotebookRepositoryProtocol, parent: Notebook? = nil) {
        self.repository = repository
        self.parent = parent
        reload()
    }

    /// Notebooks after applying the current search filter.
    var filteredNotebooks: [Notebook] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return notebooks }
        return notebooks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    func reload() {
        do {
            if let parent {
                notebooks = parent.orderedChildren.sorted(by: sort.comparator)
            } else {
                notebooks = try repository.allTopLevel(sortedBy: sort)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createNotebook(title: String) -> Notebook? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "Untitled Notebook" : name
        do {
            let notebook = try repository.create(title: finalName, parent: parent)
            reload()
            return notebook
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func rename(_ notebook: Notebook, to title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try repository.rename(notebook, to: name)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ notebook: Notebook) {
        do {
            try repository.delete(notebook)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicate(_ notebook: Notebook) {
        do {
            try repository.duplicate(notebook)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
