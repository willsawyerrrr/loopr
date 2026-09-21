import AppIntents
import CoreSpotlight
import Foundation
import RouteKit
import SwiftData

/// The single route store shared by the UI and App Intents, which run in the app's process.
@MainActor
enum RouteStore {
    static let container: ModelContainer = {
        do {
            return try SavedRoute.makeContainer()
        } catch {
            fatalError("Could not open the route store: \(error)")
        }
    }()

    /// Saves a route. With an `eventKey`, the route for that calendar run is updated in place if one exists.
    @discardableResult
    static func save(
        response: RouteResponse, points: [RoutePoint], name: String? = nil, eventKey: String? = nil
    ) -> SavedRoute {
        let route: SavedRoute
        if let eventKey, let existing = self.route(forEventKey: eventKey) {
            existing.update(
                targetDistanceKm: response.targetDistanceKm, summary: response.route, previewUrl: response.previewUrl,
                points: points, warnings: response.warnings)
            route = existing
        } else {
            route = SavedRoute(
                name: name ?? RouteFormat.name(distanceKm: response.route.distanceKm),
                targetDistanceKm: response.targetDistanceKm,
                summary: response.route,
                previewUrl: response.previewUrl,
                points: points,
                warnings: response.warnings,
                eventKey: eventKey
            )
            container.mainContext.insert(route)
        }
        try? container.mainContext.save()
        let entity = RouteEntity(route)
        Task { try? await CSSearchableIndex.default().indexAppEntities([entity]) }
        LooprShortcuts.updateAppShortcutParameters()
        return route
    }

    static func route(forEventKey key: String) -> SavedRoute? {
        var descriptor = FetchDescriptor<SavedRoute>(predicate: #Predicate { $0.eventKey == key })
        descriptor.fetchLimit = 1
        return (try? container.mainContext.fetch(descriptor))?.first
    }

    static func delete(_ route: SavedRoute) {
        let id = route.id
        container.mainContext.delete(route)
        try? container.mainContext.save()
        Task { try? await CSSearchableIndex.default().deleteAppEntities(identifiedBy: [id], ofType: RouteEntity.self) }
        LooprShortcuts.updateAppShortcutParameters()
    }

    static func allRoutes() -> [SavedRoute] {
        let descriptor = FetchDescriptor<SavedRoute>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
}
