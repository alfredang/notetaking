import Foundation
import Vision
import CoreGraphics
import ImageIO

/// Recognizes text — including handwriting — from a rendered page image using
/// the Vision framework. Used to build a searchable text index per page.
enum TextRecognitionService {
    /// Recognizes text from rendered page PNG data.
    ///
    /// Runs off the main actor. We pass PNG `Data` (which is `Sendable`) rather
    /// than a `CGImage`/`UIImage` so nothing non-`Sendable` crosses the task
    /// boundary under Swift 6 strict concurrency.
    static func recognizeText(fromPNG data: Data) async -> String {
        await Task.detached(priority: .utility) {
            guard !data.isEmpty,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return "" }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate          // best effort on handwriting
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return ""
            }
            let lines = (request.results ?? []).compactMap {
                $0.topCandidates(1).first?.string
            }
            return lines.joined(separator: " ")
        }.value
    }
}
