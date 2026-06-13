import SwiftUI

/// A request to export, used as a `.sheet(item:)` payload.
enum ExportRequest: Identifiable {
    case page(Page, ExportFormat)
    case notebook(Notebook)
    /// Shareable `.notebook` archive (full copy: pages, backgrounds, audio).
    case notebookArchive(Notebook)

    var id: String {
        switch self {
        case .page(let p, let f): "page-\(p.id)-\(f.rawValue)"
        case .notebook(let n): "notebook-\(n.id)"
        case .notebookArchive(let n): "archive-\(n.id)"
        }
    }
}

/// Renders the export and presents a share sheet.
struct ExportSheet: View {
    let request: ExportRequest
    @Environment(\.dismiss) private var dismiss

    @State private var url: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let url {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.badge.arrow.up")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor)
                        Text(url.lastPathComponent).font(.headline)
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(40)
                } else if let errorMessage {
                    ContentUnavailableView("Export Failed", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else {
                    ProgressView("Preparing…")
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        do {
            switch request {
            case .page(let page, let format):
                url = try ExportService.exportPage(page, as: format, name: "Page")
            case .notebook(let notebook):
                url = try ExportService.exportNotebookPDF(notebook)
            case .notebookArchive(let notebook):
                url = try NotebookArchiveService.export(notebook)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
