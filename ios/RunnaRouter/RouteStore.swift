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

    @discardableResult
    static func save(response: RouteResponse, points: [RoutePoint]) -> SavedRoute {
        let route = SavedRoute(
            name: RouteFormat.name(distanceKm: response.route.distanceKm),
            targetDistanceKm: response.targetDistanceKm,
            summary: response.route,
            previewUrl: response.previewUrl,
            points: points
        )
        container.mainContext.insert(route)
        try? container.mainContext.save()
        let entity = RouteEntity(route)
        Task { try? await CSSearchableIndex.default().indexAppEntities([entity]) }
        RunnaRouterShortcuts.updateAppShortcutParameters()
        return route
    }

    static func delete(_ route: SavedRoute) {
        let id = route.id
        container.mainContext.delete(route)
        try? container.mainContext.save()
        Task { try? await CSSearchableIndex.default().deleteAppEntities(identifiedBy: [id], ofType: RouteEntity.self) }
        RunnaRouterShortcuts.updateAppShortcutParameters()
    }

    static func allRoutes() -> [SavedRoute] {
        let descriptor = FetchDescriptor<SavedRoute>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
}
