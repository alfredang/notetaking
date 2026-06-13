import Foundation
import SwiftData

/// Repository abstraction over notebook persistence.
@MainActor
protocol NotebookRepositoryProtocol {
    func allTopLevel(sortedBy sort: NotebookSort) throws(StorageError) -> [Notebook]
    @discardableResult
    func create(title: String, parent: Notebook?) throws(StorageError) -> Notebook
    func rename(_ notebook: Notebook, to title: String) throws(StorageError)
    func delete(_ notebook: Notebook) throws(StorageError)
    @discardableResult
    func duplicate(_ notebook: Notebook) throws(StorageError) -> Notebook
    func save() throws(StorageError)
}

/// Repository abstraction over page persistence.
@MainActor
protocol PageRepositoryProtocol {
    @discardableResult
    func addPage(to notebook: Notebook, at index: Int?) throws(StorageError) -> Page
    /// Appends one page per background raster (e.g. imported PDF pages).
    @discardableResult
    func appendPages(withBackgrounds backgrounds: [Data], to notebook: Notebook) throws(StorageError) -> [Page]
    func delete(_ page: Page, from notebook: Notebook) throws(StorageError)
    @discardableResult
    func duplicate(_ page: Page, in notebook: Notebook) throws(StorageError) -> Page
    func clear(_ page: Page) throws(StorageError)
    func move(in notebook: Notebook, from source: IndexSet, to destination: Int) throws(StorageError)
    func save() throws(StorageError)
}

/// How notebooks are ordered on the dashboard.
enum NotebookSort: String, CaseIterable, Identifiable {
    case lastModified = "Last Modified"
    case createdDate = "Created Date"
    case alphabetical = "Alphabetical"

    var id: String { rawValue }
}

// MARK: - SwiftData-backed implementations

@MainActor
final class NotebookRepository: NotebookRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func allTopLevel(sortedBy sort: NotebookSort) throws(StorageError) -> [Notebook] {
        let descriptor = FetchDescriptor<Notebook>(
            predicate: #Predicate { $0.parent == nil }
        )
        let notebooks: [Notebook]
        do {
            notebooks = try context.fetch(descriptor)
        } catch {
            throw StorageError.saveFailed(error.localizedDescription)
        }
        return notebooks.sorted(by: sort.comparator)
    }

    @discardableResult
    func create(title: String, parent: Notebook?) throws(StorageError) -> Notebook {
        let siblingsCount = parent?.children?.count ?? (try? allTopLevel(sortedBy: .createdDate).count) ?? 0
        let notebook = Notebook(title: title, sortIndex: siblingsCount, parent: parent)
        context.insert(notebook)
        parent?.touch()
        try save()
        return notebook
    }

    func rename(_ notebook: Notebook, to title: String) throws(StorageError) {
        notebook.title = title
        notebook.touch()
        try save()
    }

    func delete(_ notebook: Notebook) throws(StorageError) {
        context.delete(notebook)
        try save()
    }

    @discardableResult
    func duplicate(_ notebook: Notebook) throws(StorageError) -> Notebook {
        let copy = Notebook(
            title: notebook.title + " Copy",
            sortIndex: notebook.sortIndex + 1,
            parent: notebook.parent
        )
        context.insert(copy)
        // Deep-copy pages.
        for page in notebook.orderedPages {
            let pageCopy = Page(
                pageIndex: page.pageIndex,
                drawingData: page.drawingData,
                shapesData: page.shapesData,
                notebook: copy
            )
            context.insert(pageCopy)
            copy.pages = (copy.pages ?? []) + [pageCopy]
        }
        try save()
        return copy
    }

    func save() throws(StorageError) {
        do {
            try context.save()
        } catch {
            throw StorageError.saveFailed(error.localizedDescription)
        }
    }
}

@MainActor
final class PageRepository: PageRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func addPage(to notebook: Notebook, at index: Int?) throws(StorageError) -> Page {
        var pages = notebook.orderedPages
        let insertIndex = index ?? pages.count
        let clamped = max(0, min(insertIndex, pages.count))
        let page = Page(pageIndex: clamped, notebook: notebook)
        context.insert(page)
        pages.insert(page, at: clamped)
        reindex(pages)
        notebook.pages = pages
        notebook.touch()
        try save()
        return page
    }

    @discardableResult
    func appendPages(withBackgrounds backgrounds: [Data], to notebook: Notebook) throws(StorageError) -> [Page] {
        var pages = notebook.orderedPages
        var created: [Page] = []
        for background in backgrounds {
            let page = Page(pageIndex: pages.count, backgroundData: background, notebook: notebook)
            context.insert(page)
            pages.append(page)
            created.append(page)
        }
        reindex(pages)
        notebook.pages = pages
        notebook.touch()
        try save()
        return created
    }

    func delete(_ page: Page, from notebook: Notebook) throws(StorageError) {
        context.delete(page)
        var pages = notebook.orderedPages.filter { $0.id != page.id }
        reindex(pages)
        notebook.pages = pages
        notebook.touch()
        try save()
    }

    @discardableResult
    func duplicate(_ page: Page, in notebook: Notebook) throws(StorageError) -> Page {
        var pages = notebook.orderedPages
        let insertIndex = (pages.firstIndex { $0.id == page.id } ?? pages.count - 1) + 1
        let copy = Page(
            pageIndex: insertIndex,
            drawingData: page.drawingData,
            shapesData: page.shapesData,
            notebook: notebook
        )
        context.insert(copy)
        pages.insert(copy, at: min(insertIndex, pages.count))
        reindex(pages)
        notebook.pages = pages
        notebook.touch()
        try save()
        return copy
    }

    func clear(_ page: Page) throws(StorageError) {
        page.drawingData = Data()
        page.shapesData = Data()
        page.touch()
        try save()
    }

    func move(in notebook: Notebook, from source: IndexSet, to destination: Int) throws(StorageError) {
        var pages = notebook.orderedPages
        pages.move(fromOffsets: source, toOffset: destination)
        reindex(pages)
        notebook.pages = pages
        notebook.touch()
        try save()
    }

    func save() throws(StorageError) {
        do {
            try context.save()
        } catch {
            throw StorageError.saveFailed(error.localizedDescription)
        }
    }

    private func reindex(_ pages: [Page]) {
        for (i, page) in pages.enumerated() {
            page.pageIndex = i
        }
    }
}

// MARK: - Sorting

extension NotebookSort {
    var comparator: (Notebook, Notebook) -> Bool {
        switch self {
        case .lastModified: { $0.updatedAt > $1.updatedAt }
        case .createdDate: { $0.createdAt > $1.createdAt }
        case .alphabetical: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}
