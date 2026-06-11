import Foundation
import SwiftData

/// A notebook. Supports nesting via a self-referential parent/children relationship.
@Model
final class Notebook {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// Manual ordering on the dashboard / within a parent.
    var sortIndex: Int

    /// Parent notebook for nesting (nil = top-level).
    @Relationship(inverse: \Notebook.children)
    var parent: Notebook?

    /// Sub-notebooks. Deleting a notebook cascades to its children.
    @Relationship(deleteRule: .cascade)
    var children: [Notebook]

    /// Pages owned by this notebook. Deleting cascades to pages.
    @Relationship(deleteRule: .cascade, inverse: \Page.notebook)
    var pages: [Page]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sortIndex: Int = 0,
        parent: Notebook? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortIndex = sortIndex
        self.parent = parent
        self.children = []
        self.pages = []
    }

    var pageCount: Int { pages.count }

    /// Pages sorted by their index, for stable display.
    var orderedPages: [Page] {
        pages.sorted { $0.pageIndex < $1.pageIndex }
    }

    /// Child notebooks sorted for stable display.
    var orderedChildren: [Notebook] {
        children.sorted { $0.sortIndex < $1.sortIndex }
    }

    func touch(_ date: Date = .now) {
        updatedAt = date
    }
}
