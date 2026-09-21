import Foundation

public struct RouteDistanceError: LocalizedError, Equatable, Sendable {
    public var errorDescription: String? {
        let range = RouteDistance.allowedKm
        return "Choose a distance between \(Int(range.lowerBound)) and \(Int(range.upperBound)) km."
    }
}

public enum RouteDistance {
    public static let allowedKm: ClosedRange<Double> = 1...50

    /// Converts a spoken or typed length to kilometres, rounded to 10 m.
    public static func kilometres(from measurement: Measurement<UnitLength>) throws -> Double {
        let km = (measurement.converted(to: .kilometers).value * 100).rounded() / 100
        guard allowedKm.contains(km) else { throw RouteDistanceError() }
        return km
    }
}
