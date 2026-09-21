import RouteKit
import SwiftUI

struct RouteStatsView: View {
    let distanceKm: Double
    let ascentM: Double
    let descentM: Double
    let hilliness: String
    let elevationGainPerKm: Double

    var body: some View {
        HStack {
            stat("Distance", distanceKm.formatted(.number.precision(.fractionLength(0...2))) + " km")
            Divider()
            stat("Climb", "\(Int(ascentM.rounded())) m")
            Divider()
            stat(hilliness.capitalized, elevationGainPerKm.formatted(.number.precision(.fractionLength(0))) + " m/km")
        }
        .frame(height: 44)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
