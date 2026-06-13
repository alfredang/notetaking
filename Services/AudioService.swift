import Foundation
import AVFoundation
import Observation

/// Records voice memos to AAC/m4a and reports live elapsed time.
@MainActor
@Observable
final class AudioRecorderService {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var ticker: Task<Void, Never>?

    /// Requests microphone permission (iOS 17+ API).
    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Begins recording to a fresh temp file. Returns false if it couldn't start.
    @discardableResult
    func start() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            return false
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.record()
            recorder = r
            fileURL = url
            isRecording = true
            elapsed = 0
            startTicker()
            return true
        } catch {
            return false
        }
    }

    /// Stops recording and returns the encoded audio plus its duration.
    func stop() -> (data: Data, duration: TimeInterval)? {
        ticker?.cancel()
        ticker = nil
        guard let recorder, let url = fileURL else { isRecording = false; return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return (data, max(duration, elapsed))
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                self.elapsed = recorder.currentTime
            }
        }
    }
}

/// Plays back stored voice memos, tracking which note is currently playing.
@MainActor
@Observable
final class AudioPlayerController: NSObject, AVAudioPlayerDelegate {
    private(set) var playingID: UUID?

    private var player: AVAudioPlayer?
    private var tempURL: URL?

    /// Toggles playback for a note: starts it, or stops it if already playing.
    func toggle(_ note: AudioNote) {
        if playingID == note.id {
            stop()
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        do {
            try note.audioData.write(to: url, options: .atomic)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            tempURL = url
            playingID = note.id
        } catch {
            cleanupTemp()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
        cleanupTemp()
    }

    private func cleanupTemp() {
        if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        tempURL = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
