import SwiftUI

/// A single notebook tile on the dashboard grid.
struct NotebookCard: View {
    let notebook: Notebook
    var onOpen: () -> Void
    var onOpenFolder: () -> Void
    var onRename: (String) -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var onAddSubNotebook: () -> Void
    var onShare: () -> Void
    var onEditTags: () -> Void

    @State private var isRenaming = false
    @State private var draftTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                NotebookCoverView(notebook: notebook)
                    .softShadow()
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityLabel("Open \(notebook.title)")

            if isRenaming {
                TextField("Name", text: $draftTitle, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
            } else {
                Text(notebook.title)
                    .font(.headline)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                    .imageScale(.small)
                Text("\(notebook.pageCount) pages")
                if notebook.orderedChildren.count > 0 {
                    Text("· \(notebook.orderedChildren.count) folders")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Updated \(notebook.updatedAt.relativeDescription)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if !notebook.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(notebook.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Color(.secondarySystemBackground))
        )
        .contextMenu {
            Button { onOpen() } label: { Label("Open", systemImage: "book") }
            if notebook.orderedChildren.count > 0 {
                Button { onOpenFolder() } label: { Label("Open Sub-Notebooks", systemImage: "folder") }
            }
            Button { beginRename() } label: { Label("Rename", systemImage: "pencil") }
            Button { onEditTags() } label: { Label("Edit Tags", systemImage: "tag") }
            Button { onAddSubNotebook() } label: { Label("Add Sub-Notebook", systemImage: "folder.badge.plus") }
            Button { onDuplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { onShare() } label: { Label("Share Notebook", systemImage: "square.and.arrow.up") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func beginRename() {
        draftTitle = notebook.title
        isRenaming = true
    }

    private func commitRename() {
        isRenaming = false
        onRename(draftTitle)
    }
}
