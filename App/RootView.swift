import SwiftUI
import SwiftData

/// Top-level router. Shows the dashboard; opening a notebook pushes the editor.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        DashboardView(viewModel: DashboardViewModel(repository: NotebookRepository(context: modelContext)))
    }
}
