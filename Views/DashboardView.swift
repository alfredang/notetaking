import SwiftUI
import SwiftData

/// Navigation route values for the dashboard stack.
enum DashboardRoute: Hashable {
    case editor(Notebook)
    case folder(Notebook)
}

/// Home screen: a grid of notebooks with create / sort / search.
/// Reused for sub-notebook folders via `parent`.
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DashboardViewModel
    @State private var path = NavigationPath()
    @State private var showingNewNotebook = false
    @State private var newNotebookName = ""
    @State private var showingSettings = false
    /// Pending deletion awaiting confirmation.
    @State private var pendingDelete: Notebook?
    /// Notebook archive to share via the export sheet.
    @State private var shareItem: ExportRequest?
    @State private var showingImporter = false
    /// Notebook whose tags are being edited.
    @State private var taggingNotebook: Notebook?

    private let title: String

    init(viewModel: DashboardViewModel, title: String = "Notebooks") {
        _viewModel = State(initialValue: viewModel)
        self.title = title
    }

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 20)]

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(title)
                .navigationDestination(for: DashboardRoute.self) { route in
                    switch route {
                    case .editor(let notebook):
                        NotebookView(notebook: notebook)
                    case .folder(let notebook):
                        SubNotebookView(parent: notebook)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            if viewModel.filteredNotebooks.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(viewModel.filteredNotebooks) { notebook in
                        NotebookCard(
                            notebook: notebook,
                            onOpen: { path.append(DashboardRoute.editor(notebook)) },
                            onOpenFolder: { path.append(DashboardRoute.folder(notebook)) },
                            onRename: { viewModel.rename(notebook, to: $0) },
                            onDuplicate: { viewModel.duplicate(notebook) },
                            onDelete: { pendingDelete = notebook },
                            onAddSubNotebook: {
                                _ = viewModel.createNotebook(title: "New Folder")
                                // Created at parent scope; reload handled by VM.
                            },
                            onShare: { shareItem = .notebookArchive(notebook) },
                            onEditTags: { taggingNotebook = notebook }
                        )
                    }
                }
                .padding(24)
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search notebooks & handwriting")
        .safeAreaInset(edge: .bottom) {
            Text("Powered by Tertiary Infotech Academy Pte Ltd")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .toolbar { toolbarContent }
        .alert("New Notebook", isPresented: $showingNewNotebook) {
            TextField("Notebook name", text: $newNotebookName)
            Button("Create") {
                _ = viewModel.createNotebook(title: newNotebookName)
                newNotebookName = ""
            }
            Button("Cancel", role: .cancel) { newNotebookName = "" }
        }
        .alert(
            "Delete \(pendingDelete?.title ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let nb = pendingDelete { viewModel.delete(nb) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This permanently deletes the notebook and all of its pages and sub-notebooks.")
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(item: $shareItem) { request in
            ExportSheet(request: request)
        }
        .sheet(item: $taggingNotebook) { nb in
            TagEditorView(title: nb.title, currentTags: nb.tags, suggestions: viewModel.allTags) {
                viewModel.setTags($0, on: nb)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [NotebookArchiveService.contentType]
        ) { result in
            if case .success(let url) = result {
                viewModel.importArchive(from: url, into: modelContext)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        if !viewModel.allTags.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter by tag", selection: $viewModel.selectedTag) {
                        Text("All Notebooks").tag(String?.none)
                        ForEach(viewModel.allTags, id: \.self) { tag in
                            Label(tag, systemImage: "tag").tag(String?.some(tag))
                        }
                    }
                } label: {
                    Label("Filter by tag",
                          systemImage: viewModel.selectedTag == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: $viewModel.sort) {
                    ForEach(NotebookSort.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingImporter = true
            } label: {
                Label("Import Notebook", systemImage: "square.and.arrow.down")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingNewNotebook = true
            } label: {
                Label("New Notebook", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Notebooks", systemImage: "book.closed")
        } description: {
            Text("Create your first notebook to start taking notes.")
        } actions: {
            Button("Create Notebook") { showingNewNotebook = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 80)
    }
}

/// A nested dashboard scoped to one notebook's sub-notebooks.
struct SubNotebookView: View {
    @Environment(\.modelContext) private var modelContext
    let parent: Notebook

    var body: some View {
        DashboardView(
            viewModel: DashboardViewModel(
                repository: NotebookRepository(context: modelContext),
                parent: parent
            ),
            title: parent.title
        )
    }
}
