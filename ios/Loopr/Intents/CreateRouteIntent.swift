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

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetIntent {
        try await RouteCreation.create(km: RouteDistance.kilometres(from: distance))
    }
}

/// A whole-kilometre distance that Siri can match inside an App Shortcut phrase.
struct DistanceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Distance"
    static let defaultQuery = DistanceEntityQuery()

    let id: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(id) km",
            synonyms: ["\(id) kilometres", "\(id) kilometers", "\(id)k", "\(id) K"]
        )
    }

    static let all = (Int(RouteDistance.allowedKm.lowerBound)...Int(RouteDistance.allowedKm.upperBound)).map(DistanceEntity.init)
}

struct DistanceEntityQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [DistanceEntity] {
        DistanceEntity.all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DistanceEntity] {
        DistanceEntity.all
    }
}

/// Backs phrases that say the distance aloud ("Create a 10 km route in Loopr").
struct CreateRouteOfDistanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Route of Distance"
    static let supportedModes: IntentModes = [.background]

    @Parameter(title: "Distance")
    var distance: DistanceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Create a \(\.$distance) route")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetIntent {
        try await RouteCreation.create(km: Double(distance.id))
    }
}

enum RouteCreation {
    @MainActor
    static func currentPoint() async throws -> RoutePoint {
        let coordinate = try await LocationProvider().currentCoordinate()
        return RoutePoint(longitude: coordinate.longitude, latitude: coordinate.latitude)
    }

    static func create(km: Double) async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetIntent {
        let start = try await StartResolver().resolve { try await currentPoint() }
        let draft = try await RouteGenerator.makeDraft(targetKm: km, start: start)
        return present(draft)
    }

    /// The map snippet result for `draft`; `detail` follows "route" in the spoken line and `notes` end it.
    /// The line names the start unless it was the current location.
    static func present(
        _ draft: RouteDraft, detail: String = "", notes: [String] = []
    ) -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetIntent {
        let summary = RouteFormat.subtitle(distanceKm: draft.response.route.distanceKm, ascentM: draft.response.route.ascentM)
        let origin =
            switch draft.start.source {
            case .current: ""
            case .lastUsed: " from your last start point"
            case .chosen, .defaultStart: " from \(draft.start.label)"
            }
        let spoken = "Here's a \(summary) route\(detail)\(origin)." + notes.map { " \($0)" }.joined()
        return .result(
            value: summary,
            dialog: "\(spoken)",
            snippetIntent: RoutePreviewSnippetIntent(draftID: draft.id)
        )
    }
}
