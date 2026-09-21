import AppIntents
import CoreSpotlight
import RouteKit

struct RouteEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Route"
    static let defaultQuery = RouteEntityQuery()

    let id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Distance (km)")
    var distanceKm: Double

    @Property(title: "Saved")
    var createdAt: Date

    private let subtitle: String

    init(_ route: SavedRoute) {
        id = route.id
        subtitle = RouteFormat.subtitle(distanceKm: route.distanceKm, ascentM: route.ascentM)
        name = route.name
        distanceKm = route.distanceKm
        createdAt = route.createdAt
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)",
            image: .init(systemName: "point.topleft.down.to.point.bottomright.curvepath")
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.displayName = name
        attributes.contentDescription = subtitle
        attributes.keywords = ["route", "run", "loop", "gpx"]
        return attributes
    }
}

struct RouteEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [RouteEntity] {
        RouteStore.allRoutes().filter { identifiers.contains($0.id) }.map(RouteEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [RouteEntity] {
        RouteStore.allRoutes()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(RouteEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [RouteEntity] {
        RouteStore.allRoutes().prefix(10).map(RouteEntity.init)
    }
}
