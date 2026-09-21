import AppIntents
import RouteKit

struct CreateRouteIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Route"
    static let description = IntentDescription(
        "Generates a loop of the given distance from where you are and shows it on a map.",
        categoryName: "Routes"
    )
    static let supportedModes: IntentModes = [.background]

    @Parameter(
        title: "Distance",
        defaultUnit: .kilometers,
        supportsNegativeNumbers: false,
        requestValueDialog: "How far do you want to run?"
    )
    var distance: Measurement<UnitLength>

    static var parameterSummary: some ParameterSummary {
        Summary("Create a \(\.$distance) route")
    }

    @MainActor
    private static func currentPoint() async throws -> RoutePoint {
        let coordinate = try await LocationProvider().currentCoordinate()
        return RoutePoint(longitude: coordinate.longitude, latitude: coordinate.latitude)
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetIntent {
        let km = try RouteDistance.kilometres(from: distance)
        let start = try await StartResolver().resolve { try await Self.currentPoint() }
        let draft = try await RouteGenerator.makeDraft(targetKm: km, start: start.point)

        let summary = RouteFormat.subtitle(distanceKm: draft.response.route.distanceKm, ascentM: draft.response.route.ascentM)
        let origin = start.source == .lastUsed ? " from your last start point" : ""
        return .result(
            value: summary,
            dialog: "Here's a \(summary) route\(origin).",
            snippetIntent: RoutePreviewSnippetIntent(draftID: draft.id)
        )
    }
}
