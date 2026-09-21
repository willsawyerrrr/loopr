import Foundation
import RouteKit

/// A generated route that hasn't been saved yet, held for the snippet's Save / Regenerate buttons.
struct RouteDraft: Sendable {
    let id: UUID
    var targetKm: Double
    var start: RoutePoint
    var response: RouteResponse
    var points: [RoutePoint]
    var snapshotPNG: Data?
    var savedID: UUID?
}

enum RouteDraftError: LocalizedError {
    case expired
    case noGeometry

    var errorDescription: String? {
        switch self {
        case .expired: "That route is no longer available. Ask for a new one."
        case .noGeometry: "The route had no geometry."
        }
    }
}

actor DraftStore {
    static let shared = DraftStore()

    private var drafts: [UUID: RouteDraft] = [:]

    func put(_ draft: RouteDraft) {
        if drafts.count >= 8, let oldest = drafts.keys.first { drafts[oldest] = nil }
        drafts[draft.id] = draft
    }

    func draft(_ id: UUID) throws -> RouteDraft {
        guard let draft = drafts[id] else { throw RouteDraftError.expired }
        return draft
    }
}

enum RouteGenerator {
    /// Generates a loop with the app's hills/green preferences and stores it as a draft; `regenerate` asks for a different loop than a plain request returns. Must finish within the ~30 s intent budget.
    static func makeDraft(targetKm: Double, start: RoutePoint, regenerate: Bool = false) async throws -> RouteDraft {
        let defaults = UserDefaults.standard
        var request = RouteRequest(
            targetDistanceKm: targetKm,
            startLongitude: start.longitude,
            startLatitude: start.latitude,
            hillsPreference: defaults.double(forKey: "hillsPreference"),
            greenPreference: defaults.double(forKey: "greenPreference")
        )
        if regenerate { request = request.regenerated() }
        let response = try await RouteService(timeout: 25).generate(request)
        return try await draft(from: response, targetKm: targetKm, start: start)
    }

    /// Stores an already generated `response` as a draft, so Regenerate reuses `targetKm` and `start`.
    static func draft(from response: RouteResponse, targetKm: Double, start: RoutePoint) async throws -> RouteDraft {
        let points = response.resolvedPoints()
        guard !points.isEmpty else { throw RouteDraftError.noGeometry }
        var draft = RouteDraft(
            id: UUID(), targetKm: targetKm, start: start, response: response, points: points)
        draft.snapshotPNG = await RouteSnapshot.png(points: points)
        await DraftStore.shared.put(draft)
        return draft
    }
}
