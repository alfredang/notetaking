import SwiftUI

/// Page thumbnail sidebar: preview, jump-to, add, multi-select delete, and
/// drag-to-reorder (in Select mode).
struct SidebarView: View {
    @Bindable var viewModel: NotebookViewModel

    @State private var editMode: EditMode = .inactive
    @State private var selectedIDs: Set<UUID> = []

    private var selecting: Bool { editMode == .active }

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                ForEach(Array(viewModel.pages.enumerated()), id: \.element.id) { index, page in
                    pageRow(index: index, page: page)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .listRowBackground(Color.clear)
                }
                .onMove { source, dest in viewModel.movePages(from: source, to: dest) }
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
        }
        .frame(width: 132)
        .background(Color(.secondarySystemBackground))
    }

    private var header: some View {
        HStack(spacing: 14) {
            // Select / done toggle (drag handles + multi-select appear in select mode).
            Button {
                withAnimation {
                    if selecting { editMode = .inactive; selectedIDs.removeAll() }
                    else { editMode = .active }
                }
            } label: {
                Image(systemName: selecting ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .accessibilityLabel(selecting ? "Done selecting" : "Select pages")

            Spacer()

            if selecting {
                Button(role: .destructive) {
                    viewModel.deletePages(ids: selectedIDs)
                    selectedIDs.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedIDs.isEmpty)
                .foregroundStyle(selectedIDs.isEmpty ? Color.secondary : Color.red)
                .accessibilityLabel("Delete selected pages")
            } else {
                Menu {
                    Button { viewModel.addPageAtEnd() } label: { Label("Add at End", systemImage: "plus") }
                    Button { viewModel.insertPage(before: viewModel.selectedPageIndex) } label: {
                        Label("Insert Before", systemImage: "arrow.up.to.line")
                    }
                    Button { viewModel.insertPage(after: viewModel.selectedPageIndex) } label: {
                        Label("Insert After", systemImage: "arrow.down.to.line")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Add page")
            }
        }
        .font(.title3)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func pageRow(index: Int, page: Page) -> some View {
        let isSelected = selectedIDs.contains(page.id)
        let isCurrent = index == viewModel.selectedPageIndex
        return VStack(spacing: 4) {
            ThumbnailView(page: page, maxWidth: 96, refreshToken: viewModel.refreshToken)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.pageCornerRadius)
                        .stroke(selecting ? (isSelected ? Color.red : .clear) : (isCurrent ? Color.accentColor : .clear),
                                lineWidth: 3)
                )
                .overlay(alignment: .topTrailing) {
                    if selecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.red : Color.secondary)
                            .background(Circle().fill(.background))
                            .padding(4)
                    }
                }
            Text("Page \(index + 1)")
                .font(.caption)
                .foregroundStyle(isCurrent && !selecting ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting {
                if isSelected { selectedIDs.remove(page.id) } else { selectedIDs.insert(page.id) }
            } else {
                viewModel.selectedPageIndex = index
            }
        }
        .contextMenu {
            Button { viewModel.duplicate(page) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { viewModel.insertPage(after: index) } label: { Label("Insert After", systemImage: "arrow.down.to.line") }
            Button(role: .destructive) { viewModel.delete(page) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}
