import Foundation
import RouteKit

/// Generates and saves the route for a calendar run.
@MainActor
enum RunPreparation {
    private static func currentPoint() async throws -> RoutePoint {
        let coordinate = try await LocationProvider().currentCoordinate()
        return RoutePoint(longitude: coordinate.longitude, latitude: coordinate.latitude)
    }

    /// The saved route for `run`, generating it first when missing or when `regenerate` is set.
    /// `background` shortens the waits so the work fits a background refresh.
    static func prepare(_ run: PlannedRun, regenerate: Bool = false, background: Bool = false) async throws -> SavedRoute {
        if !regenerate, let existing = RouteStore.route(forEventKey: run.key) { return existing }
        let start = try await StartResolver(timeout: .seconds(background ? 3 : 8)).resolve { try await currentPoint() }
        let defaults = UserDefaults.standard
        var request = try RunPlan.request(
            for: run,
            start: start.point,
            hillsPreference: defaults.double(forKey: "hillsPreference"),
            greenPreference: defaults.double(forKey: "greenPreference"),
            paces: PaceStore().paces
        )
        if regenerate { request = request.regenerated() }
        let response = try await RouteService(timeout: background ? 25 : 60).generate(request)
        let points = response.resolvedPoints()
        guard !points.isEmpty else { throw RouteDraftError.noGeometry }
        return RouteStore.save(response: response, points: points, name: run.title, eventKey: run.key)
    }
}
