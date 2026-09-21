import Testing
import UIKit

/// Draws a Runna-style workout screen and reads it back through Vision. Runs without the app: `ScreenshotOCR`
/// is compiled into this bundle.
@Suite struct ScreenshotOCRTests {
    private struct Row {
        var y: CGFloat
        var index: String?
        var text: String
        var label: String?
    }

    private func render(header: String, rows: [Row], bars: [(CGFloat, String)]) -> Data {
        let size = CGSize(width: 900, height: 2000)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: 0.1, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            func draw(_ text: String, at point: CGPoint, size: CGFloat, weight: UIFont.Weight = .medium) {
                (text as NSString).draw(
                    at: point,
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: UIColor.white,
                    ])
            }
            draw("Walk Run", at: CGPoint(x: 40, y: 240), size: 56, weight: .bold)
            draw(header, at: CGPoint(x: 40, y: 330), size: 40)
            draw("Description", at: CGPoint(x: 100, y: 1070), size: 44, weight: .bold)
            for (y, title) in bars { draw(title, at: CGPoint(x: 60, y: y), size: 38) }
            for row in rows {
                if let index = row.index { draw(index, at: CGPoint(x: 70, y: row.y), size: 52, weight: .bold) }
                draw(row.text, at: CGPoint(x: 170, y: row.y), size: 34)
                if let label = row.label { draw(label, at: CGPoint(x: 790, y: row.y), size: 30, weight: .bold) }
            }
            draw("Start Workout", at: CGPoint(x: 300, y: 1850), size: 44, weight: .bold)
        }
        return image.pngData()!
    }

    @Test func readsAWalkRunScreen() async throws {
        let data = render(
            header: "Walk-Run  · 2.5km",
            rows: [
                Row(y: 1260, index: "1", text: "5 mins walking warm up", label: "WALK"),
                Row(y: 1470, index: "2", text: "1.25km at a conversational pace", label: "RUN"),
                Row(y: 1530, index: nil, text: "60s walking", label: "WALK"),
                Row(y: 1720, index: "3", text: "5 mins walking cool down", label: "WALK"),
            ],
            bars: [(1190, "Warm-Up"), (1385, "Repeat x2"), (1640, "Cool Down")])

        let recognised = try await ScreenshotOCR.recognise(data)

        #expect(recognised.workout.title == "Walk-Run")
        #expect(recognised.workout.statedRunKm == 2.5)
        #expect(
            recognised.workout.text == """
                5 mins walking warm up

                2 reps of:
                • 1.25km at a conversational pace
                • 60s walking

                5 mins walking cool down
                """)
    }

    @Test func reportsAScreenshotWithNoWorkout() async {
        let data = render(header: "Settings", rows: [], bars: [])
        await #expect(throws: ScreenshotError.self) { _ = try await ScreenshotOCR.recognise(data) }
    }
}
