import Foundation

/// Body of `POST /api/route`: either a manual target distance or a Runna workout description.
public struct RouteRequest: Encodable, Sendable {
    public var targetDistanceKm: Double?
    /// The raw Runna workout text; the server works out the distance from it.
    public var workout: String?
    /// `[lon, lat]`.
    public var start: [Double]
    public var hillsPreference: Double
    public var greenPreference: Double
    public var title: String?
    /// The run's date as `yyyy-MM-dd`.
    public var date: String?
    /// Pace phrase (lowercased) to minutes per km.
    public var paces: [String: Double]?
    /// Asks the server for a different loop than the one a request without it returns; omitted when `nil`.
    public var variant: Int?
    /// Points the loop should pass through, in `[lon, lat]` order; omitted when `nil`.
    public var waypoints: [RoutePoint]?
    /// Degrees clockwise from north the loop should head toward; omitted when `nil`.
    public var heading: Double?

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

    public init(
        workout: String,
        title: String,
        date: String,
        start: RoutePoint,
        hillsPreference: Double = 0,
        greenPreference: Double = 0,
        paces: [String: Double]
    ) {
        self.workout = workout
        self.title = title
        self.date = date
        self.start = [start.longitude, start.latitude]
        self.hillsPreference = hillsPreference
        self.greenPreference = greenPreference
        self.paces = paces
    }

    /// The range `regenerated(variant:)` draws from by default.
    public static let variantRange = 1...1_000_000

    /// This request with a fresh `variant`, so the server returns a different loop than the last one.
    public func regenerated(variant: () -> Int = { Int.random(in: RouteRequest.variantRange) }) -> RouteRequest {
        var copy = self
        copy.variant = variant()
        return copy
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
    /// Present for workout requests; a manual distance carries an always-passing one.
    public var checksum: WorkoutChecksum?
    /// The parsed workout steps; empty for a manual distance.
    public var segments: [WorkoutSegment]?

    /// The distance of the running steps alone, or `nil` when the response carries no steps.
    public var runKm: Double? {
        guard let segments, !segments.isEmpty else { return nil }
        return segments.filter { $0.activity == "run" }.reduce(0) { $0 + $1.distanceMeters } / 1000
    }

    /// The route geometry, taken from `coordinates` or, when absent, parsed from `gpx`.
    public func resolvedPoints() -> [RoutePoint] {
        if let coordinates, !coordinates.isEmpty { return coordinates }
        return GPXParser.points(in: gpx)
    }
}

/// One parsed workout step.
public struct WorkoutSegment: Decodable, Hashable, Sendable {
    /// `run` or `walk`.
    public var activity: String
    public var distanceMeters: Double
}

/// The server's cross-check of a workout's parsed total against the figures in its header.
public struct WorkoutChecksum: Decodable, Hashable, Sendable {
    public var ok: Bool
    public var statedMinutes: Double?
    public var statedKm: Double?
    public var computedMinutes: Double?
    public var computedKm: Double?

    /// Whether the header carried a total to check against; without one, `ok` is vacuously true.
    public var hasStatedFigure: Bool { statedMinutes != nil || statedKm != nil }

    /// Which figure disagrees, or `nil` when the checksum passed.
    public var problem: String? {
        guard !ok else { return nil }
        if let stated = statedKm, let computed = computedKm, abs(stated - computed) > max(1, 0.15 * stated) {
            return "The workout says \(Self.number(stated)) km but its steps add up to \(Self.number(computed)) km."
        }
        if let stated = statedMinutes, let computed = computedMinutes, abs(stated - computed) > 3 {
            return "The workout says \(Self.number(stated)) min but its steps add up to \(Self.number(computed)) min."
        }
        return "The workout's steps don't add up to its stated total."
    }

    /// A distance to offer for manual entry: the header's, else the parsed total.
    public var suggestedKm: Double? {
        if let statedKm, statedKm > 0 { return statedKm }
        if let computedKm, computedKm > 0 { return computedKm }
        return nil
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// A `4xx`/`5xx` body: `{ "error": …, "detail": … }`.
struct APIErrorBody: Decodable {
    var error: String
    var detail: String?
}
