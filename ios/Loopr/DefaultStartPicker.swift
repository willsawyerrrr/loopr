import MapKit
import RouteKit
import SwiftUI

/// Search for a place or tap the map to choose where routes without a start of their own begin and end.
struct DefaultStartPicker: View {
    @Binding var place: StartPlace?

    @Environment(\.dismiss) private var dismiss
    @State private var position = MapCameraPosition.automatic

    private static let space = "default-start-map"

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    if let place {
                        Annotation(place.displayName, coordinate: place.point.coordinate) {
                            StartMarker().draggableStart(
                                proxy: proxy, space: Self.space,
                                onMove: { self.place = StartPlace(point: $0) },
                                onEnd: { if let point = self.place?.point { Task { await StartNaming.name($place, at: point) } } })
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .coordinateSpace(.named(Self.space))
                .onTapGesture { location in
                    guard let point = proxy.convert(location, from: .local) else { return }
                    StartNaming.drop(at: RoutePoint(longitude: point.longitude, latitude: point.latitude), into: $place)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(place.map { "Routes start and finish at \($0.displayName)." } ?? "Search or tap the map to choose a start.")
                    .font(.footnote)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
            .navigationTitle("Default start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { place = nil }.disabled(place == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .startSearchable { picked in
                place = picked
                recentre()
            }
        }
        .task { recentre() }
    }

    private func recentre() {
        guard let place else { return }
        position = .region(MKCoordinateRegion(center: place.point.coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000))
    }
}
