import AppIntents
import RouteKit

/// Makes a route from a screenshot of a Runna workout. Not an App Shortcut phrase, since Siri can't supply
/// the image: chain it after Shortcuts' *Take Screenshot*, then bind that shortcut to Back Tap or the Action Button.
struct CreateRouteFromScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Route from Screenshot"
    static let description = IntentDescription(
        "Reads a screenshot of a Runna workout, works out its distance and shows a loop of that length on a map.",
        categoryName: "Routes"
    )
    static let supportedModes: IntentModes = [.background]

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var screenshot: IntentFile

    @Parameter(
        title: "Distance",
        description: "Used instead of the workout in the screenshot. Asked for when the workout can't be read.",
        defaultUnit: .kilometers,
        supportsNegativeNumbers: false
    )
    var distance: Measurement<UnitLength>?

    static var parameterSummary: some ParameterSummary {
        Summary("Create a route from \(\.$screenshot)") {
            \.$distance
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetIntent {
        // The whole run must fit the ~30 s background limit: recognition and the location fix overlap,
        // and the requests get what's left of the budget.
        async let start = StartResolver().resolve { try await RouteCreation.currentPoint() }

        if let distance {
            let resolved = try await start
            let draft = try await RouteGenerator.makeDraft(
                targetKm: RouteDistance.kilometres(from: distance), start: resolved.point)
            return RouteCreation.present(draft, start: resolved.source)
        }

        let recognised = try await ScreenshotOCR.recognise(screenshot.data)
        let resolved = try await start
        let pipeline = ScreenshotRouting.pipeline(rewriting: recognised.lines, budget: .seconds(20), timeout: 20)
        switch try await pipeline.route(for: recognised.workout, start: resolved.point, date: ScreenshotRouting.today) {
        case .needsManualDistance(let request):
            let problems = request.problems.joined(separator: " ")
            throw $distance.needsValueError("\(problems) How far should the route be?")
        case .route(let route):
            let draft = try await RouteGenerator.draft(
                from: route.response, targetKm: route.response.targetDistanceKm, start: resolved.point)
            return RouteCreation.present(
                draft, start: resolved.source, detail: " from your workout", notes: route.notes + route.response.warnings)
        }
    }
}
