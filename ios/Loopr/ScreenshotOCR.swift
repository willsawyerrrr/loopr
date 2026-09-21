import Foundation
import RouteKit
import Vision

enum ScreenshotError: LocalizedError {
    case noWorkout

    var errorDescription: String? {
        switch self {
        case .noWorkout:
            "Couldn't find a workout in that screenshot. Use the Runna workout screen with the steps showing."
        }
    }
}

/// Text recognition for workout screenshots.
enum ScreenshotOCR {
    /// The recognised lines in reading order, and the workout read from them.
    struct Result: Sendable {
        var lines: [String]
        var workout: RecognisedWorkout
    }

    static func recognise(_ image: Data) async throws -> Result {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: image)
        let fragments = observations.compactMap { observation -> OCRFragment? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox.cgRect
            return OCRFragment(text: text, minX: box.minX, midY: 1 - box.midY, height: box.height)
        }
        let lines = OCRLayout.lines(from: fragments)
        let workout = WorkoutText.read(lines)
        guard !workout.text.isEmpty else { throw ScreenshotError.noWorkout }
        return Result(lines: lines, workout: workout)
    }
}
