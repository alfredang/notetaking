import SwiftUI

/// Renders a page thumbnail (drawing + overlay) with the paper card styling.
struct ThumbnailView: View {
    let page: Page
    var maxWidth: CGFloat = 180
    /// Bump this to force a re-render when the page content changes.
    var refreshToken: Int = 0

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.pageCornerRadius)
                .fill(Theme.paper)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(PageGeometry.aspectRatio, contentMode: .fit)
            }
        }
        .aspectRatio(PageGeometry.aspectRatio, contentMode: .fit)
        .frame(maxWidth: maxWidth)
        .clipShape(RoundedRectangle(cornerRadius: Theme.pageCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.pageCornerRadius)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .task(id: TaskKey(id: page.id, token: refreshToken)) {
            // SwiftData models aren't Sendable, so render on the main actor.
            // UIGraphicsImageRenderer work is fast for thumbnail sizes.
            image = PageRenderer.thumbnail(for: page, maxWidth: maxWidth * 2)
        }
    }

    private struct TaskKey: Equatable {
        let id: UUID
        let token: Int
    }
}

/// A simple cover thumbnail for a notebook (its first page, or a placeholder).
struct NotebookCoverView: View {
    let notebook: Notebook
    var refreshToken: Int = 0

    var body: some View {
        Group {
            if let first = notebook.orderedPages.first {
                ThumbnailView(page: first, maxWidth: 240, refreshToken: refreshToken)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.pageCornerRadius)
                        .fill(Theme.paper)
                    Image(systemName: "book.closed")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(PageGeometry.aspectRatio, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.pageCornerRadius)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }
}
