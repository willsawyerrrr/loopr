import MapKit
import RouteKit
import SwiftUI

/// Where a route starts and finishes; distinct from the numbered pins.
struct StartMarker: View {
    var body: some View {
        Image(systemName: "figure.run.circle.fill")
            .font(.title)
            .foregroundStyle(.white, .green)
    }
}

struct RouteMapView: View {
    let points: [RoutePoint]
    /// The chosen start to mark; the route's first point when `nil`.
    var start: RoutePoint?
    /// Shaping pins to number on the route.
    var pins: [RoutePoint] = []
    var interactive = true

    var body: some View {
        let coordinates = points.map(\.coordinate)
        Map(initialPosition: .rect(Self.rect(for: coordinates)), interactionModes: interactive ? .all : []) {
            MapPolyline(coordinates: coordinates)
                .stroke(.blue, lineWidth: 5)
            if let marked = start?.coordinate ?? coordinates.first {
                Annotation("Start", coordinate: marked) { StartMarker() }
            }
            ForEach(Array(pins.enumerated()), id: \.offset) { index, pin in
                Annotation("", coordinate: pin.coordinate) { PinMarker(number: index + 1) }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .id(points.count)
    }

    private static func rect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        let rect = coordinates.reduce(MKMapRect.null) { rect, coordinate in
            rect.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
        return rect.isNull ? .world : rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2)
    }
}
