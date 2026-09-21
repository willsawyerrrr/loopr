import CoreLocation
import RouteKit

enum LocationError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: "Location access is off. Enable it in Settings to start routes from where you are, or choose a start instead."
        case .unavailable: "Couldn't get your location. Try again."
        }
    }
}

/// One-shot current-location fix with When-In-Use authorisation.
@MainActor
struct LocationProvider {
    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location { return location.coordinate }
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw LocationError.denied
            }
        }
        throw LocationError.unavailable
    }

    func currentPoint() async throws -> RoutePoint {
        let coordinate = try await currentCoordinate()
        return RoutePoint(longitude: coordinate.longitude, latitude: coordinate.latitude)
    }
}
