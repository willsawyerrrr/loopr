import RouteKit
import SwiftUI

/// A generated route's map, stats and warnings, with Save and Share GPX.
struct RouteResultSections: View {
    let response: RouteResponse
    let points: [RoutePoint]
    /// Shaping pins to number on the map.
    var pins: [RoutePoint] = []
    /// Saved with the route; its start, if any, is marked on the map.
    var shape: RouteShape?
    /// Where the route started from, e.g. `Current location`.
    var startLabel: String?
    /// Names the saved route and the shared file; defaults to the distance.
    var name: String?
    @Binding var savedID: UUID?

    private var displayName: String { name ?? RouteFormat.name(distanceKm: response.route.distanceKm) }

    var body: some View {
        Section {
            RouteMapView(points: points, start: shape?.start, pins: pins, interactive: false)
                .frame(height: 300)
                .listRowInsets(EdgeInsets())
                .id("result")
            RouteStatsView(
                distanceKm: response.route.distanceKm,
                ascentM: response.route.ascentM,
                descentM: response.route.descentM,
                hilliness: response.route.hilliness,
                elevationGainPerKm: response.route.elevationGainPerKm
            )
            if let startLabel { StartedFromLabel(label: startLabel) }
            ForEach(response.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.circle").font(.footnote)
            }
        }
        Section {
            Button(savedID == nil ? "Save route" : "Saved", systemImage: savedID == nil ? "bookmark" : "bookmark.fill") {
                savedID = RouteStore.save(response: response, points: points, name: name, shape: shape, startLabel: startLabel).id
            }
            .disabled(savedID != nil)
            ShareLink(
                item: GPXFile(name: displayName, gpx: GPXWriter.gpx(points: points, name: displayName)),
                preview: SharePreview(displayName)
            ) {
                Label("Share GPX", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// `Started from <label>`.
struct StartedFromLabel: View {
    let label: String

    var body: some View {
        Label("Started from \(label)", systemImage: "location").font(.footnote).foregroundStyle(.secondary)
    }
}
