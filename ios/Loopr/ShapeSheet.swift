import MapKit
import RouteKit
import SwiftUI

/// A numbered map pin; orange when the server would reject it as out of reach.
struct PinMarker: View {
    let number: Int
    var unreachable = false

    var body: some View {
        Text("\(number)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(unreachable ? Color.orange : Color.purple, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 1)
    }
}

/// The "Shape route" row: shows the current shape and opens the sheet.
struct ShapeRow: View {
    let shape: RouteShape
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label("Shape route", systemImage: "mappin.and.ellipse")
                Spacer()
                Text(shape.summary).foregroundStyle(.secondary)
            }
        }
    }
}

/// Drop up to `RouteShape.maxPins` pins and pick a rough heading to steer the loop.
struct ShapeSheet: View {
    @Binding var shape: RouteShape
    /// The loop's target distance, when known; used to flag pins that are too far away.
    let targetKm: Double?

    @Environment(\.dismiss) private var dismiss
    @State private var start: RoutePoint?
    @State private var failure: String?
    @State private var position = MapCameraPosition.automatic

    private static let space = "shape-map"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let start {
                    map(start: start)
                    controls(start: start)
                } else if let failure {
                    ContentUnavailableView("No start location", systemImage: "location.slash", description: Text(failure))
                } else {
                    ProgressView().frame(maxHeight: .infinity)
                }
            }
            .navigationTitle("Shape route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { shape = RouteShape() }.disabled(shape.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await resolveStart() }
    }

    private func unreachable(from start: RoutePoint) -> Set<Int> {
        targetKm.map { shape.unreachablePins(from: start, targetKm: $0) } ?? []
    }

    private func map(start: RoutePoint) -> some View {
        let far = unreachable(from: start)
        return MapReader { proxy in
            Map(position: $position) {
                Annotation("Start", coordinate: start.coordinate) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, .green)
                }
                ForEach(Array(shape.pins.enumerated()), id: \.offset) { index, pin in
                    Annotation("", coordinate: pin.coordinate) {
                        PinMarker(number: index + 1, unreachable: far.contains(index))
                            .onTapGesture {}
                            .gesture(
                                DragGesture(coordinateSpace: .named(Self.space)).onChanged { drag in
                                    guard let point = proxy.convert(drag.location, from: .named(Self.space)) else { return }
                                    shape.movePin(at: index, to: RoutePoint(longitude: point.longitude, latitude: point.latitude))
                                }
                            )
                            .contextMenu {
                                Button("Remove pin", systemImage: "trash", role: .destructive) { shape.removePin(at: index) }
                            }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .coordinateSpace(.named(Self.space))
            .onTapGesture { location in
                guard let point = proxy.convert(location, from: .local) else { return }
                shape.addPin(RoutePoint(longitude: point.longitude, latitude: point.latitude))
            }
        }
    }

    private func controls(start: RoutePoint) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Heading", selection: $shape.compass) {
                Text("Any").tag(CompassPoint?.none)
                ForEach(CompassPoint.allCases, id: \.self) { Text($0.label).tag(CompassPoint?.some($0)) }
            }
            .pickerStyle(.segmented)

            ForEach(Array(shape.pins.enumerated()), id: \.offset) { index, _ in
                HStack {
                    PinMarker(number: index + 1, unreachable: unreachable(from: start).contains(index))
                    Text("Pin \(index + 1)")
                    Spacer()
                    Button("Remove pin \(index + 1)", systemImage: "minus.circle.fill") { shape.removePin(at: index) }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.red)
                }
            }

            Text(hint(start: start))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func hint(start: RoutePoint) -> String {
        if let targetKm, !unreachable(from: start).isEmpty {
            let limit = (targetKm * RouteShape.reachFraction).formatted(.number.precision(.fractionLength(0...1)))
            return "Orange pins are more than \(limit) km from the start, too far for a \(RouteFormat.distance(km: targetKm)) loop. Move them closer or raise the distance."
        }
        return shape.canAddPin
            ? "Tap the map to drop a pin, drag to move it. Up to \(RouteShape.maxPins) pins; the loop passes through them in a sensible order."
            : "Up to \(RouteShape.maxPins) pins. Remove one to add another."
    }

    private func resolveStart() async {
        do {
            let resolved = try await StartResolver(timeout: .seconds(5)).resolve { try await LocationProvider().currentPoint() }
            start = resolved.point
            let span = max((targetKm ?? 5) * 1000, 2000)
            position = .region(MKCoordinateRegion(center: resolved.point.coordinate, latitudinalMeters: span, longitudinalMeters: span))
        } catch {
            failure = error.localizedDescription
        }
    }
}
