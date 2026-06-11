import SwiftUI
import SwiftData

/// App entry point. Installs the SwiftData container and presents the root navigation.
@main
struct NotePadApp: App {
    /// Shared model container for the whole app. Created once at launch.
    let container: ModelContainer

    init() {
        do {
            let schema = Schema([Notebook.self, Page.self])
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
