import Foundation
import Testing

@testable import RouteKit

/// The Notes-style text each screen must produce. `test/screenshot-workout.test.ts` feeds the same
/// strings to the server's parser.
private enum Expected {
    static let continuousRun = """
        5 mins walking warm up

        2km at a conversational pace

        5 mins walking cool down
        """
    static let walkRun = """
        5 mins walking warm up

        2 reps of:
        • 1.25km at a conversational pace
        • 60s walking

        5 mins walking cool down
        """
    static let timedWalkRun = """
        5 mins walking warm up

        4 reps of:
        • 60s at a conversational pace
        • 30s walking
        • 2 mins at a conversational pace
        • 60s walking

        60s at a conversational pace

        5 mins walking cool down
        """
}

/// Vision's output for a Runna workout screen, top to bottom: `(top y, x, text)`.
private let continuousRunScreen: [(Double, Double, String)] = [
    (0.027, 0.1, "3:22 -"), (0.033, 0.8, "12"), (0.087, 0.2, "Week 5"), (0.142, 0.05, "22 SEP 2026"),
    (0.142, 0.4, "* SCHEDULE"), (0.176, 0.05, "Continuous Run"), (0.219, 0.05, "Continuous Run • 2km"),
    (0.304, 0.05, "It will be warmer for much of the day;"), (0.328, 0.05, "consider choosing shadier routes and..."),
    (0.458, 0.1, "WARM-UP"), (0.475, 0.1, "STRETCHES"), (0.456, 0.3, "ADD"), (0.475, 0.3, "ROUTE"),
    (0.456, 0.5, "LINK"), (0.475, 0.5, "ACTIVITY"), (0.427, 0.8, "000"), (0.456, 0.7, "SKIP"), (0.475, 0.7, "WORKOUT"),
    (0.535, 0.1, "Description"), (0.585, 0.07, "Warm-Up"), (0.625, 0.08, "1"),
    (0.624, 0.2, "5 mins walking warm up"), (0.628, 0.8, "& WALK"), (0.681, 0.07, "Session"), (0.721, 0.08, "2"),
    (0.724, 0.2, "2km at a conversational pace O"), (0.725, 0.8, "& RUN"), (0.780, 0.07, "Cool Down"),
    (0.820, 0.08, "3"), (0.823, 0.2, "5 mins walking cool down"), (0.823, 0.8, "& WALK"),
    (0.929, 0.3, "Start Workout"), (0.971, 0.15, "Head Coach, British Olympian"),
]

private let walkRunScreen: [(Double, Double, String)] = [
    (0.029, 0.1, "3:22 A"), (0.032, 0.8, "• 12"), (0.087, 0.05, "SEP Week 5SCHED Walk Run"), (0.122, 0.05, "walk Run"),
    (0.166, 0.05, "Walk-Run • 2.5km"), (0.251, 0.2, "Personalised Workout Briefing"), (0.278, 0.2, "Available in 2 days"),
    (0.324, 0.15, "• How consistent was your pacing last time?"),
    (0.464, 0.1, "WARM-UP"), (0.483, 0.1, "STRETCHES"), (0.462, 0.3, "ADD"), (0.481, 0.3, "ROUTE"),
    (0.462, 0.5, "LINK"), (0.481, 0.5, "ACTIVITY"), (0.433, 0.8, "000"), (0.462, 0.7, "SKIP"), (0.481, 0.7, "WORKOUT"),
    (0.541, 0.1, "Description"), (0.591, 0.07, "Warm-Up"), (0.631, 0.2, "5 mins walking warm up"),
    (0.632, 0.8, "* WALK"), (0.689, 0.12, "• Repeat ×2"), (0.741, 0.08, "2"),
    (0.730, 0.2, "1.25km at a conversational pace"), (0.758, 0.2, "60s walking"), (0.731, 0.8, "& RUN"),
    (0.760, 0.8, "& WALK"), (0.814, 0.07, "Cool Down"), (0.853, 0.08, "3"), (0.856, 0.2, "5 mins walking cool down"),
    (0.856, 0.8, "& WALK"), (0.929, 0.3, "Start Workout"), (0.981, 0.15, "Steph Kessell"),
]

private let timedWalkRunLines = [
    "3:22", "Walk Run", "Walk Run", "8 Sep 2026 • 17:33", "Distance", "3.70 km", "Time", "32:40", "Avg pace", "8:49 /km",
    "WARM-UP", "STRETCHES", "ADD", "ROUTE", "Description", "Warm-Up", "1", "5 mins walking warm up", "& WALK",
    "Repeat x4", "2", "60s at a conversational pace", "& RUN", "30s walking", "& WALK",
    "2 mins at a conversational pace", "& RUN", "60s walking", "& WALK", "Session", "3",
    "60s at a conversational pace", "& RUN", "Cool Down", "4", "5 mins walking cool down", "& WALK",
    "Start Workout", "Steph Kessell",
]

private func fragments(_ screen: [(Double, Double, String)]) -> [OCRFragment] {
    screen.map { OCRFragment(text: $0.2, minX: $0.1, midY: $0.0 + 0.007, height: 0.014) }
}

@Suite struct ScreenReadingTests {
    @Test func continuousRun() {
        let workout = WorkoutText.read(OCRLayout.lines(from: fragments(continuousRunScreen)))
        #expect(workout.text == Expected.continuousRun)
        #expect(workout.title == "Continuous Run")
        #expect(workout.statedRunKm == 2)
    }

    @Test func walkRunWithRepeat() {
        let workout = WorkoutText.read(OCRLayout.lines(from: fragments(walkRunScreen)))
        #expect(workout.text == Expected.walkRun)
        #expect(workout.title == "Walk-Run")
        #expect(workout.statedRunKm == 2.5)
    }

    @Test func timedWalkRunIgnoresTheCompletedActivityCard() {
        let workout = WorkoutText.read(timedWalkRunLines)
        #expect(workout.text == Expected.timedWalkRun)
        #expect(workout.title == nil)
        #expect(workout.statedRunKm == nil)
    }

    @Test func plainLinesGiveTheSameText() {
        let lines = fragments(walkRunScreen).sorted { $0.midY < $1.midY }.map(\.text)
        #expect(WorkoutText.normalise(lines) == Expected.walkRun)
    }

    @Test func layoutJoinsARowAndDropsGutterAndLabels() {
        let lines = OCRLayout.lines(from: fragments(walkRunScreen))
        #expect(lines.contains("5 mins walking warm up"))
        #expect(!lines.contains { $0.contains("WALK") && $0.contains("5 mins") })
        #expect(lines.contains("1.25km at a conversational pace"))
        #expect(!lines.contains("2"))
    }

    @Test func layoutOrdersRowsAndSideBySideFragments() {
        let lines = OCRLayout.lines(from: [
            OCRFragment(text: "second", minX: 0.1, midY: 0.5, height: 0.02),
            OCRFragment(text: "right", minX: 0.6, midY: 0.301, height: 0.02),
            OCRFragment(text: "left", minX: 0.1, midY: 0.3, height: 0.02),
        ])
        #expect(lines == ["left right", "second"])
    }
}

@Suite struct NormaliserTests {
    @Test func notesTextPassesThrough() {
        let notes = """
            Walk Run • 29m • 29m

            5 mins walking warm up

            4 reps of:
            • 60s at a conversational pace, 30s walking
            • 2 mins at a conversational pace, 60s walking

            60s at a conversational pace

            5 mins walking cool down
            """
        #expect(WorkoutText.normalise(notes.components(separatedBy: "\n")) == notes)
    }

    @Test func fixesDigitAndUnitConfusions() {
        let lines = ["1O mins walking warm up", "l.5 KM at 5:2O /km", "6O S walking", "2,5km at a conversational pace", "3O secs walking"]
        #expect(
            WorkoutText.normalise(lines) == """
                10 mins walking warm up
                1.5km at 5:20/km
                60s walking
                2.5km at a conversational pace
                30s walking
                """)
    }

    @Test func leavesWordsAlone() {
        #expect(WorkoutText.normalise(["Hill repeats on the loop"]) == "Hill repeats on the loop")
    }

    @Test func joinsWrappedLines() {
        let lines = ["2 mins at a", "conversational pace,", "60s walking", "5 mins walking warm", "up"]
        #expect(
            WorkoutText.normalise(lines) == """
                2 mins at a conversational pace, 60s walking
                5 mins walking warm up
                """)
    }

    @Test func readsRepeatVariants() {
        for marker in ["Repeat x4", "Repeat ×4", "• Repeat x4", "Repeat 4x", "4 reps of", "4 reps of:"] {
            #expect(WorkoutText.normalise([marker, "60s walking"]) == "4 reps of:\n• 60s walking", "\(marker)")
        }
    }

    @Test func repeatBlockEndsAtASectionHeaderOrBlankLine() {
        let text = WorkoutText.normalise(["Repeat x2", "1km at 4:30/km", "Cool Down", "5 mins walking cool down"])
        #expect(text == "2 reps of:\n• 1km at 4:30/km\n\n5 mins walking cool down")
        let blank = WorkoutText.normalise(["4 reps of:", "• 60s walking", "", "60s at a conversational pace"])
        #expect(blank == "4 reps of:\n• 60s walking\n\n60s at a conversational pace")
    }

    @Test func dropsChromeAndStatusBar() {
        let lines = ["9:41", "100%", "Add Route", "5 mins walking warm up", "Start Workout", "Steph Kessell"]
        #expect(WorkoutText.normalise(lines) == "5 mins walking warm up")
    }

    @Test func emptyInput() {
        #expect(WorkoutText.normalise([]) == "")
        #expect(WorkoutText.read(["Description", "Start Workout"]).text == "")
    }
}

@Suite struct WorkoutOutlineTests {
    @Test func rendersNotesText() {
        let outline = WorkoutOutline(
            title: "Walk Run",
            blocks: [
                .init(repeats: 1, steps: ["5 mins walking warm up"]),
                .init(repeats: 2, steps: ["- 1.25km at a conversational pace", "• 60s walking"]),
                .init(repeats: 1, steps: ["  "]),
            ])
        #expect(
            outline.notesText == """
                Walk Run

                5 mins walking warm up

                2 reps of:
                • 1.25km at a conversational pace
                • 60s walking
                """)
    }
}

// MARK: Pipeline

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []
    var workouts: [String] {
        lock.withLock { texts }
    }
    func record(_ workout: String) {
        lock.withLock { texts.append(workout) }
    }
}

private func responseBody(
    runKm: Double, walkKm: Double = 0.2, statedKm: Double? = nil, ok: Bool = true, computedKm: Double? = nil,
    statedMinutes: Double? = nil, computedMinutes: Double = 30
) -> Data {
    let stated = statedKm.map { "\($0)" } ?? "null"
    let minutes = statedMinutes.map { "\($0)" } ?? "null"
    return Data(
        """
        {"gpx":"<gpx/>","filename":"route.gpx","targetDistanceKm":\(runKm + walkKm),
         "route":{"distanceKm":\(runKm + walkKm),"ascentM":10,"descentM":10,"elevationGainPerKm":3,
                  "hilliness":"flat","greenScore":0},
         "segments":[{"activity":"walk","distanceMeters":\(walkKm * 1000)},{"activity":"run","distanceMeters":\(runKm * 1000)}],
         "checksum":{"ok":\(ok),"statedMinutes":\(minutes),"statedKm":\(stated),
                     "computedMinutes":\(computedMinutes),"computedKm":\(computedKm ?? runKm + walkKm)},
         "warnings":["a warning"],"coordinates":[[151.2,-33.8],[151.3,-33.9]]}
        """.utf8)
}

private func pipeline(
    calls: Calls, rewrite: ScreenshotRoutePipeline.Rewriter? = nil, budget: Duration? = nil,
    respond: @escaping @Sendable (String) -> (Int, Data)
) -> ScreenshotRoutePipeline {
    let service = RouteService(baseURL: URL(string: "https://example.com")!) { request in
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let workout = body?["workout"] as? String ?? ""
        calls.record(workout)
        let (status, data) = respond(workout)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    return ScreenshotRoutePipeline(service: service, rewrite: rewrite, budget: budget)
}

private let start = RoutePoint(longitude: 151.2, latitude: -33.8)

@Suite struct PipelineTests {
    @Test func sendsTheTextAsAWorkout() async throws {
        let calls = Calls()
        let workout = WorkoutText.read(OCRLayout.lines(from: fragments(walkRunScreen)))
        let outcome = try await pipeline(calls: calls) { _ in (200, responseBody(runKm: 2.5, walkKm: 1.1)) }
            .route(for: workout, start: start, date: "2026-09-22")
        #expect(calls.workouts == [Expected.walkRun])
        guard case .route(let route) = outcome else { Issue.record("expected a route"); return }
        #expect(route.crossChecked)
        #expect(!route.rewritten)
    }

    @Test func acceptsAWorkoutWithNoStatedTotalButDoesNotClaimItWasChecked() async throws {
        let workout = WorkoutText.read(timedWalkRunLines)
        let outcome = try await pipeline(calls: Calls()) { _ in (200, responseBody(runKm: 0.4, walkKm: 2.8)) }
            .route(for: workout, start: start, date: "2026-09-22")
        guard case .route(let route) = outcome else { Issue.record("expected a route"); return }
        #expect(!route.crossChecked)
    }

    @Test func rewritesOnceWhenTheRunningDistanceDisagrees() async throws {
        let calls = Calls()
        let workout = RecognisedWorkout(text: "garbled", title: nil, statedRunKm: 2.5)
        let outcome = try await pipeline(calls: calls, rewrite: { _ in "2 reps of:\n• 1.25km at a conversational pace" }) {
            $0 == "garbled" ? (200, responseBody(runKm: 0.5)) : (200, responseBody(runKm: 2.5))
        }.route(for: workout, start: start, date: "2026-09-22")
        #expect(calls.workouts == ["garbled", "2 reps of:\n• 1.25km at a conversational pace"])
        guard case .route(let route) = outcome else { Issue.record("expected a route"); return }
        #expect(route.rewritten)
        #expect(route.text.hasPrefix("2 reps of:"))
    }

    @Test func asksForADistanceWhenThereIsNoRewriter() async throws {
        let workout = RecognisedWorkout(text: "garbled", title: nil, statedRunKm: 2.5)
        let outcome = try await pipeline(calls: Calls()) { _ in (200, responseBody(runKm: 0.5, walkKm: 0.5)) }
            .route(for: workout, start: start, date: "2026-09-22")
        guard case .needsManualDistance(let request) = outcome else { Issue.record("expected a prompt"); return }
        #expect(request.problems == ["The screen shows 2.5 km of running but the steps add up to 0.5 km.", "a warning"])
        #expect(request.suggestedKm == 1)
        #expect(request.text == "garbled")
    }

    @Test func asksForADistanceWhenTheRewriteDoesNotHelpEither() async throws {
        let calls = Calls()
        let workout = RecognisedWorkout(text: "garbled", title: nil, statedRunKm: 2.5)
        let outcome = try await pipeline(calls: calls, rewrite: { _ in "still wrong" }) { _ in (200, responseBody(runKm: 0.5)) }
            .route(for: workout, start: start, date: "2026-09-22")
        #expect(calls.workouts.count == 2)
        guard case .needsManualDistance = outcome else { Issue.record("expected a prompt"); return }
    }

    @Test func doesNotRetryWhenTheRewriterHasNothingNew() async throws {
        let calls = Calls()
        let workout = RecognisedWorkout(text: "garbled", title: nil, statedRunKm: 2.5)
        _ = try await pipeline(calls: calls, rewrite: { _ in nil }) { _ in (200, responseBody(runKm: 0.5)) }
            .route(for: workout, start: start, date: "2026-09-22")
        #expect(calls.workouts.count == 1)
    }

    @Test func skipsTheRewriteWhenTheBudgetIsSpent() async throws {
        let calls = Calls()
        let workout = RecognisedWorkout(text: "garbled", title: nil, statedRunKm: 2.5)
        let outcome = try await pipeline(calls: calls, rewrite: { _ in "fixed" }, budget: .seconds(2)) { _ in
            (200, responseBody(runKm: 0.5))
        }.route(for: workout, start: start, date: "2026-09-22")
        #expect(calls.workouts.count == 1)
        guard case .needsManualDistance = outcome else { Issue.record("expected a prompt"); return }
    }

    @Test func rejectsAFailedServerChecksum() async throws {
        let workout = RecognisedWorkout(text: "Walk Run • 6km\n2km walking", title: nil, statedRunKm: nil)
        let outcome = try await pipeline(calls: Calls()) { _ in
            (200, responseBody(runKm: 0, walkKm: 2, statedKm: 6, ok: false, computedKm: 2))
        }.route(for: workout, start: start, date: "2026-09-22")
        guard case .needsManualDistance(let request) = outcome else { Issue.record("expected a prompt"); return }
        #expect(request.problems.first == "The workout says 6 km but its steps add up to 2 km.")
        #expect(request.suggestedKm == 6)
    }

    @Test func reportsMinutesMismatches() {
        let checksum = WorkoutChecksum(
            ok: false, statedMinutes: 29, statedKm: nil, computedMinutes: 14.5, computedKm: 1.9)
        #expect(checksum.problem == "The workout says 29 min but its steps add up to 14.5 min.")
        #expect(checksum.suggestedKm == 1.9)
    }

    @Test func passesServerUnparseableErrorsOnVerbatim() async throws {
        let body = Data(#"{"error":"Could not derive a target distance from the workout text","detail":"No segments parsed from workout text"}"#.utf8)
        let outcome = try await pipeline(calls: Calls()) { _ in (422, body) }
            .route(for: RecognisedWorkout(text: "x", title: nil, statedRunKm: nil), start: start, date: "2026-09-22")
        guard case .needsManualDistance(let request) = outcome else { Issue.record("expected a prompt"); return }
        #expect(
            request.problems == [
                "Could not derive a target distance from the workout text", "No segments parsed from workout text",
            ])
        #expect(request.suggestedKm == nil)
    }

    @Test func otherServerErrorsPropagate() async {
        let body = Data(#"{"error":"Trail Router failed"}"#.utf8)
        await #expect(throws: RouteServiceError.self) {
            _ = try await pipeline(calls: Calls()) { _ in (502, body) }
                .route(for: RecognisedWorkout(text: "x", title: nil, statedRunKm: nil), start: start, date: "2026-09-22")
        }
    }

    @Test func explainsHowTheDistanceWasReached() throws {
        let response = try JSONDecoder().decode(RouteResponse.self, from: responseBody(runKm: 2.5))
        let plain = ScreenshotRoute(response: response, text: "", rewritten: false, crossChecked: true)
        #expect(plain.notes.isEmpty)
        let unchecked = ScreenshotRoute(response: response, text: "", rewritten: true, crossChecked: false)
        #expect(unchecked.notes.count == 2)
    }

    @Test func decodesSegmentsAndRunKm() throws {
        let response = try JSONDecoder().decode(RouteResponse.self, from: responseBody(runKm: 2.5, walkKm: 1))
        #expect(response.runKm == 2.5)
        #expect(response.checksum?.ok == true)
    }
}
