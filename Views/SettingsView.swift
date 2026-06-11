import SwiftUI

/// App settings and defaults.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("allowsFingerDrawing") private var allowsFingerDrawing = false
    @AppStorage("defaultPenWidth") private var defaultPenWidth = 2.0
    @AppStorage("showPageNumbers") private var showPageNumbers = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Pencil") {
                    Toggle("Allow finger drawing", isOn: $allowsFingerDrawing)
                    Text("When off, fingers pan and zoom while Apple Pencil draws.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Defaults") {
                    Picker("Default pen width", selection: $defaultPenWidth) {
                        ForEach(ToolDefaults.penSizes, id: \.self) { size in
                            Text("\(Int(size)) px").tag(Double(size))
                        }
                    }
                    Toggle("Show page numbers", isOn: $showPageNumbers)
                }
                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Platform", value: "iPadOS 18+")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
