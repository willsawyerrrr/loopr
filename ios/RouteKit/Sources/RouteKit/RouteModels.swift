import Foundation

/// Body of `POST /api/route` for a manual target distance.
public struct RouteRequest: Encodable, Sendable {
    public var targetDistanceKm: Double
    /// `[lon, lat]`.
    public var start: [Double]
    public var hillsPreference: Double
    public var greenPreference: Double
    public var title: String?

    public init(
        targetDistanceKm: Double,
        startLongitude: Double,
        startLatitude: Double,
        hillsPreference: Double = 0,
        greenPreference: Double = 0,
        title: String? = nil
    ) {
        self.targetDistanceKm = targetDistanceKm
        self.start = [startLongitude, startLatitude]
        self.hillsPreference = hillsPreference
        self.greenPreference = greenPreference
        self.title = title
    }
}

public struct RouteSummary: Codable, Hashable, Sendable {
    public var distanceKm: Double
    public var ascentM: Double
    public var descentM: Double
    public var elevationGainPerKm: Double
    public var hilliness: String
    public var greenScore: Double
}

/// The JSON returned by `POST /api/route`.
public struct RouteResponse: Decodable, Sendable {
    public var gpx: String
    public var filename: String
    public var targetDistanceKm: Double
    public var route: RouteSummary
    public var warnings: [String]
    public var previewUrl: String?
    /// Present once the API returns geometry directly; otherwise read from `gpx`.
    public var coordinates: [RoutePoint]?

    /// The route geometry, taken from `coordinates` or, when absent, parsed from `gpx`.
    public func resolvedPoints() -> [RoutePoint] {
        if let coordinates, !coordinates.isEmpty { return coordinates }
        return GPXParser.points(in: gpx)
    }
}

/// A `4xx`/`5xx` body: `{ "error": …, "detail": … }`.
struct APIErrorBody: Decodable {
    var error: String
    var detail: String?
}
