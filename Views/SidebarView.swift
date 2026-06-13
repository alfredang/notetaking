import SwiftUI

/// Page thumbnail sidebar: preview, jump-to, reorder, delete, add.
struct SidebarView: View {
    @Bindable var viewModel: NotebookViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pages").font(.headline)
                Spacer()
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
            }
            .padding()

            List {
                ForEach(Array(viewModel.pages.enumerated()), id: \.element.id) { index, page in
                    pageRow(index: index, page: page)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .listRowBackground(Color.clear)
                }
                .onMove { source, dest in viewModel.movePages(from: source, to: dest) }
            }
            .listStyle(.plain)
        }
        .frame(width: 132)
        .background(Color(.secondarySystemBackground))
    }

    private func pageRow(index: Int, page: Page) -> some View {
        VStack(spacing: 4) {
            ThumbnailView(page: page, maxWidth: 96, refreshToken: viewModel.refreshToken)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.pageCornerRadius)
                        .stroke(Color.accentColor, lineWidth: index == viewModel.selectedPageIndex ? 3 : 0)
                )
            Text("Page \(index + 1)")
                .font(.caption)
                .foregroundStyle(index == viewModel.selectedPageIndex ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectedPageIndex = index }
        .contextMenu {
            Button { viewModel.duplicate(page) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { viewModel.insertPage(after: index) } label: { Label("Insert After", systemImage: "arrow.down.to.line") }
            Button(role: .destructive) { viewModel.delete(page) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}
