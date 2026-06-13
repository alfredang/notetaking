import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// An open notebook: thumbnail sidebar + page editor, with page/export actions.
struct NotebookView: View {
    @Environment(\.modelContext) private var modelContext
    let notebook: Notebook

    @State private var notebookVM: NotebookViewModel
    @State private var editorVM = EditorViewModel()
    @State private var controller = CanvasController()
    @State private var autoSave: AutoSaveService
    @State private var showSidebar = false
    /// Persisted finger-drawing preference (shared with Settings). Off by
    /// default so a finger scrolls and never creates strokes/shapes.
    @AppStorage("allowsFingerDrawing") private var allowsFingerDrawing = false
    @State private var showAudioNotes = false
    @State private var showPDFImporter = false
    @State private var exportItem: ExportRequest?

    init(notebook: Notebook) {
        self.notebook = notebook
        // Build dependencies from the shared context.
        let context = notebook.modelContext ?? ModelContext(try! ModelContainer(for: Notebook.self, Page.self, AudioNote.self))
        _notebookVM = State(initialValue: NotebookViewModel(
            notebook: notebook,
            repository: PageRepository(context: context)
        ))
        _autoSave = State(initialValue: AutoSaveService(context: context))
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(viewModel: notebookVM)
                    .transition(.move(edge: .leading))
                Divider()
            }
            EditorView(
                pages: notebookVM.pages,
                editor: editorVM,
                autoSave: autoSave,
                controller: controller,
                structureToken: notebookVM.refreshToken
            )
        }
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onChange(of: notebookVM.selectedPageIndex) { _, newValue in
            controller.scrollToPage(newValue)
        }
        .onAppear {
            // Swiping up past the last page appends a new blank page.
            controller.requestNewPageAtEnd = {
                notebookVM.addPageAtEnd()
            }
            editorVM.allowsFingerDrawing = allowsFingerDrawing
            // Default ink to the notebook's template so it's visible (white
            // chalk on a blackboard, black on white paper).
            let ink = notebookVM.paperStyle.defaultInkColor
            editorVM.penColor = ink
            editorVM.shapeStrokeColor = ink
            // Wire the in-toolbar template control + thumbnail refresh.
            controller.currentPaperStyle = { notebookVM.paperStyle }
            controller.setPaperStyle = { style in
                notebookVM.setPaperStyle(style)
                controller.reloadAllPages()
                editorVM.penColor = style.defaultInkColor
                editorVM.shapeStrokeColor = style.defaultInkColor
            }
            controller.refreshThumbnails = { notebookVM.bump() }
        }
        .onChange(of: allowsFingerDrawing) { _, newValue in
            editorVM.allowsFingerDrawing = newValue
            controller.applyTool()
        }
        .onDisappear { autoSave.saveNow() }
        .sheet(item: $exportItem) { request in
            ExportSheet(request: request)
        }
        .sheet(isPresented: $showAudioNotes) {
            AudioNotesView(notebook: notebook)
        }
        .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                notebookVM.importPDF(from: url)
                controller.scrollToPage(notebookVM.selectedPageIndex)
            }
        }
    }


    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .accessibilityLabel("Toggle pages sidebar")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Toggle(isOn: $allowsFingerDrawing) {
                Image(systemName: "hand.draw")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Finger drawing")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    notebookVM.extendCurrentPage()
                    controller.scrollToPage(notebookVM.selectedPageIndex)
                } label: { Label("Extend Page", systemImage: "arrow.down.to.line") }
                Button {
                    notebookVM.resetCurrentPageHeight()
                } label: { Label("Reset Page Height", systemImage: "arrow.up.to.line") }
            } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .accessibilityLabel("Page size")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showPDFImporter = true
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .accessibilityLabel("Import PDF")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showAudioNotes = true
            } label: {
                Image(systemName: "waveform")
            }
            .accessibilityLabel("Audio notes")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let page = notebookVM.selectedPage {
                    Section("Export Page") {
                        Button("PNG") { exportItem = .page(page, .png) }
                        Button("JPG") { exportItem = .page(page, .jpg) }
                        Button("PDF") { exportItem = .page(page, .pdf) }
                    }
                }
                Section("Export Notebook") {
                    Button("PDF") { exportItem = .notebook(notebook) }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Export")
        }
    }
}
