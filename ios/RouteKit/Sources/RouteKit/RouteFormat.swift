import Foundation

public enum RouteFormat {
    /// e.g. `10 km`, `10.02 km`.
    public static func distance(km: Double) -> String {
        "\(km.formatted(.number.precision(.fractionLength(0...2)))) km"
    }

    /// e.g. `5.5 km route`.
    public static func name(distanceKm: Double) -> String {
        "\(distanceKm.formatted(.number.precision(.fractionLength(0...1)))) km route"
    }

    /// e.g. `10.02 km · 140 m climb`.
    public static func subtitle(distanceKm: Double, ascentM: Double) -> String {
        "\(distance(km: distanceKm)) · \(Int(ascentM.rounded())) m climb"
    }
}
