import CoreTransferable
import Foundation
import Observation
import RouteKit
import UniformTypeIdentifiers

/// Drives the *From screenshot* screen: recognise, generate, and fall back to a manual distance.
@MainActor
@Observable
final class ScreenshotRouteModel {
    enum Phase {
        case idle
        case recognising
        case generating
        case route(RouteResponse, [RoutePoint], notes: [String])
        /// The distance couldn't be confirmed; `problems` are shown as the checks and server reported them.
        case needsDistance(problems: [String])
        case failed(String)
    }

    private(set) var phase = Phase.idle
    /// The recognised workout text, editable so the user can correct it and regenerate.
    var text = ""
    var manualKm = 5.0
    var savedID: UUID?
    private(set) var title: String?
    /// Where the current route started from.
    private(set) var startLabel: String?
    private var statedRunKm: Double?
    private var lines: [String] = []

    var isBusy: Bool {
        switch phase {
        case .recognising, .generating: true
        default: false
        }
    }

    func load(_ image: Data) async {
        phase = .recognising
        savedID = nil
        do {
            let recognised = try await ScreenshotOCR.recognise(image)
            lines = recognised.lines
            text = recognised.workout.text
            title = recognised.workout.title
            statedRunKm = recognised.workout.statedRunKm
            await generate(rewriting: lines)
        } catch {
            text = ""
            phase = .failed(error.localizedDescription)
        }
    }

    /// Regenerates from the text as edited, which is taken as written rather than rewritten.
    func regenerate() async {
        await generate(rewriting: nil)
    }

    /// Generates a loop of `manualKm` when the workout's distance couldn't be confirmed.
    func generateManual() async {
        phase = .generating
        savedID = nil
        do {
            let start = try await currentStart().point
            let defaults = UserDefaults.standard
            let response = try await RouteService().generate(
                RouteRequest(
                    targetDistanceKm: manualKm, startLongitude: start.longitude, startLatitude: start.latitude,
                    hillsPreference: defaults.double(forKey: "hillsPreference"),
                    greenPreference: defaults.double(forKey: "greenPreference")))
            show(response, notes: [])
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    var saveName: String? { title }

    private func generate(rewriting lines: [String]?) async {
        phase = .generating
        savedID = nil
        do {
            let start = try await currentStart()
            let workout = RecognisedWorkout(text: text, title: title, statedRunKm: statedRunKm)
            let outcome = try await ScreenshotRouting.pipeline(rewriting: lines)
                .route(for: workout, start: start.point, date: ScreenshotRouting.today)
            switch outcome {
            case .route(let route):
                if route.rewritten { text = route.text }
                show(route.response, notes: route.notes)
            case .needsManualDistance(let request):
                manualKm = min(max(request.suggestedKm ?? manualKm, RouteDistance.allowedKm.lowerBound), RouteDistance.allowedKm.upperBound)
                phase = .needsDistance(problems: request.problems)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func show(_ response: RouteResponse, notes: [String]) {
        let points = response.resolvedPoints()
        phase = points.isEmpty ? .failed("The route had no geometry.") : .route(response, points, notes: notes)
    }

    /// The default start, else the current location or the last one used.
    private func currentStart() async throws -> ResolvedStart {
        let start = try await StartResolver().resolve { try await LocationProvider().currentPoint() }
        startLabel = start.label
        return start
    }
}
