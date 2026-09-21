import RouteKit
import SwiftUI

/// A generated route's map, stats and warnings, with Save and Share GPX.
struct RouteResultSections: View {
    let response: RouteResponse
    let points: [RoutePoint]
    /// Shaping pins to number on the map.
    var pins: [RoutePoint] = []
    /// Saved with the route.
    var shape: RouteShape?
    /// Names the saved route and the shared file; defaults to the distance.
    var name: String?
    @Binding var savedID: UUID?

    private var displayName: String { name ?? RouteFormat.name(distanceKm: response.route.distanceKm) }

    var body: some View {
        Section {
            RouteMapView(points: points, pins: pins, interactive: false)
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
            ForEach(response.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.circle").font(.footnote)
            }
        }
        Section {
            Button(savedID == nil ? "Save route" : "Saved", systemImage: savedID == nil ? "bookmark" : "bookmark.fill") {
                savedID = RouteStore.save(response: response, points: points, name: name, shape: shape).id
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
