import RouteKit
import SwiftData
import SwiftUI

struct SavedRoutesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var routes: [SavedRoute]

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty {
                    ContentUnavailableView(
                        "No saved routes", systemImage: "bookmark", description: Text("Generate a route and save it to see it here."))
                } else {
                    List {
                        ForEach(routes) { route in
                            NavigationLink(value: route.id) {
                                VStack(alignment: .leading) {
                                    Text(route.name).font(.headline)
                                    Text(
                                        "\(route.distanceKm.formatted(.number.precision(.fractionLength(0...2)))) km · \(Int(route.ascentM.rounded())) m climb · \(route.createdAt.formatted(date: .abbreviated, time: .omitted))"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { routes[$0] }.forEach(modelContext.delete)
                            try? modelContext.save()
                        }
                    }
                }
            }
            .navigationTitle("Saved")
            .navigationDestination(for: UUID.self) { id in
                if let route = routes.first(where: { $0.id == id }) {
                    RouteDetailView(route: route)
                }
            }
        }
    }
}

struct RouteDetailView: View {
    let route: SavedRoute

    var body: some View {
        VStack(spacing: 0) {
            RouteMapView(points: route.points)
            RouteStatsView(
                distanceKm: route.distanceKm,
                ascentM: route.ascentM,
                descentM: route.descentM,
                hilliness: route.hilliness,
                elevationGainPerKm: route.elevationGainPerKm
            )
            .padding()
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: route.gpxFile, preview: SharePreview(route.name)) {
                Label("Share GPX", systemImage: "square.and.arrow.up")
            }
        }
    }
}
