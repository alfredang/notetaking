import SwiftUI

/// Sheet for adding/removing a notebook's tags, with suggestions from tags
/// already used elsewhere.
struct TagEditorView: View {
    let title: String
    let suggestions: [String]
    let onSave: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String]
    @State private var newTag = ""

    init(title: String, currentTags: [String], suggestions: [String], onSave: @escaping ([String]) -> Void) {
        self.title = title
        self.suggestions = suggestions
        self.onSave = onSave
        _tags = State(initialValue: currentTags)
    }

    private var unusedSuggestions: [String] {
        suggestions.filter { !tags.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tags") {
                    if tags.isEmpty {
                        Text("No tags yet").foregroundStyle(.secondary)
                    }
                    ForEach(tags, id: \.self) { tag in
                        HStack {
                            Label(tag, systemImage: "tag")
                            Spacer()
                            Button(role: .destructive) {
                                tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(tag)")
                        }
                    }
                    HStack {
                        TextField("Add a tag", text: $newTag)
                            .submitLabel(.done)
                            .onSubmit(addTag)
                        Button("Add", action: addTag)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if !unusedSuggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(unusedSuggestions, id: \.self) { tag in
                            Button {
                                tags.append(tag)
                            } label: {
                                Label(tag, systemImage: "plus")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags · \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(tags); dismiss() }
                }
            }
        }
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else {
            newTag = ""
            return
        }
        tags.append(t)
        newTag = ""
    }
}
