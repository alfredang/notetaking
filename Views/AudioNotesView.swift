import SwiftUI
import SwiftData

/// A sheet listing a notebook's voice memos with record / play / delete.
struct AudioNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let notebook: Notebook

    @State private var recorder = AudioRecorderService()
    @State private var player = AudioPlayerController()
    @State private var micDenied = false

    var body: some View {
        NavigationStack {
            Group {
                if notebook.orderedAudioNotes.isEmpty {
                    ContentUnavailableView(
                        "No Voice Memos",
                        systemImage: "waveform",
                        description: Text("Tap the record button to capture a voice memo for this notebook.")
                    )
                } else {
                    List {
                        ForEach(notebook.orderedAudioNotes) { note in
                            row(note)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { recordBar }
            .navigationTitle("Voice Memos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { player.stop(); dismiss() }
                }
            }
            .onDisappear { player.stop() }
            .alert("Microphone Access Needed", isPresented: $micDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable microphone access in Settings to record voice memos.")
            }
        }
    }

    private func row(_ note: AudioNote) -> some View {
        Button {
            player.toggle(note)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: player.playingID == note.id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title.isEmpty ? "Voice Memo" : note.title)
                        .foregroundStyle(.primary)
                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Self.durationLabel(note.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var recordBar: some View {
        VStack(spacing: 6) {
            if recorder.isRecording {
                Text(Self.durationLabel(recorder.elapsed))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.red)
            }
            Button(action: toggleRecording) {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(recorder.isRecording ? Color.red : Color.accentColor, in: Circle())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private func toggleRecording() {
        if recorder.isRecording {
            guard let result = recorder.stop() else { return }
            let note = AudioNote(
                title: "Voice Memo",
                duration: result.duration,
                audioData: result.data,
                notebook: notebook
            )
            modelContext.insert(note)
            notebook.touch()
            try? modelContext.save()
        } else {
            Task {
                let granted = await recorder.requestPermission()
                if granted {
                    recorder.start()
                } else {
                    micDenied = true
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let notes = notebook.orderedAudioNotes
        for index in offsets {
            let note = notes[index]
            if player.playingID == note.id { player.stop() }
            modelContext.delete(note)
        }
        try? modelContext.save()
    }

    static func durationLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
