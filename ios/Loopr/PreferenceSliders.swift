import SwiftUI

/// The hills and green preferences shared by the *Generate* tab, calendar runs and background generation.
struct PreferenceSliders: View {
    @AppStorage("hillsPreference") private var hills = 0.0
    @AppStorage("greenPreference") private var green = 0.0

    var body: some View {
        VStack(alignment: .leading) {
            Text("Hills").font(.subheadline)
            Slider(value: $hills, in: -1...1, step: 0.25) {
                Text("Hills")
            } minimumValueLabel: {
                Text("Flat").font(.caption)
            } maximumValueLabel: {
                Text("Hilly").font(.caption)
            }
        }
        VStack(alignment: .leading) {
            Text("Green").font(.subheadline)
            Slider(value: $green, in: 0...1, step: 0.25) {
                Text("Green")
            } minimumValueLabel: {
                Text("Any").font(.caption)
            } maximumValueLabel: {
                Text("Green").font(.caption)
            }
        }
    }
}
