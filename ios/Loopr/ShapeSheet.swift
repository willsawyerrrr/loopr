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

/// Choose where the loop starts and finishes, drop up to `RouteShape.maxPins` pins and pick a rough heading to steer it.
struct ShapeSheet: View {
    @Binding var shape: RouteShape
    /// The loop's target distance, when known; used to flag pins that are too far away.
    let targetKm: Double?

    @Environment(\.dismiss) private var dismiss
    /// Where the loop starts when the shape has no start of its own: the default start, else the device location.
    @State private var fallback: ResolvedStart?
    @State private var failure: String?
    @State private var settingStart = false
    @State private var position = MapCameraPosition.automatic

    private static let space = "shape-map"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                ScrollView { controls.padding() }
                    .frame(maxHeight: 300)
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
            .startSearchable { place in
                shape.startPlace = place
                recentre()
            }
        }
        .task {
            if shape.start == nil { await resolveFallback() }
            recentre()
        }
        .onChange(of: shape.start == nil) { _, reset in
            guard reset else { return }
            Task {
                await resolveFallback()
                recentre()
            }
        }
    }

    /// The chosen start, else where the loop would otherwise begin.
    private var start: RoutePoint? { shape.start ?? fallback?.point }

    private var unreachable: Set<Int> {
        guard let start, let targetKm else { return [] }
        return shape.unreachablePins(from: start, targetKm: targetKm)
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let start {
                    Annotation("Start", coordinate: start.coordinate) {
                        if shape.start != nil {
                            StartMarker().draggableStart(
                                proxy: proxy, space: Self.space,
                                onMove: { shape.startPlace = StartPlace(point: $0) },
                                onEnd: { if let point = shape.start { Task { await StartNaming.name($shape.startPlace, at: point) } } })
                        } else {
                            StartMarker()
                        }
                    }
                }
                ForEach(Array(shape.pins.enumerated()), id: \.offset) { index, pin in
                    Annotation("", coordinate: pin.coordinate) {
                        PinMarker(number: index + 1, unreachable: unreachable.contains(index))
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
                guard let coordinate = proxy.convert(location, from: .local) else { return }
                let point = RoutePoint(longitude: coordinate.longitude, latitude: coordinate.latitude)
                if settingStart {
                    StartNaming.drop(at: point, into: $shape.startPlace)
                } else {
                    shape.addPin(point)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            startRow

            Picker("Heading", selection: $shape.compass) {
                Text("Any").tag(CompassPoint?.none)
                ForEach(CompassPoint.allCases, id: \.self) { Text($0.label).tag(CompassPoint?.some($0)) }
            }
            .pickerStyle(.segmented)

            ForEach(Array(shape.pins.enumerated()), id: \.offset) { index, _ in
                HStack {
                    PinMarker(number: index + 1, unreachable: unreachable.contains(index))
                    Text("Pin \(index + 1)")
                    Spacer()
                    Button("Remove pin \(index + 1)", systemImage: "minus.circle.fill") { shape.removePin(at: index) }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.red)
                }
            }

            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var startRow: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Start and finish").font(.caption).foregroundStyle(.secondary)
                Text(startName)
            }
            Spacer()
            if shape.start != nil {
                Button("Reset", systemImage: "location") { shape.startPlace = nil }
                    .labelStyle(.iconOnly)
            }
            Button(settingStart ? "Done" : "Set start", systemImage: "mappin.circle") { settingStart.toggle() }
                .buttonStyle(.bordered)
                .tint(settingStart ? .green : .accentColor)
        }
    }

    private var startName: String {
        if let place = shape.startPlace { return place.displayName }
        if let fallback { return fallback.label }
        return failure == nil ? "Locating…" : "Not set"
    }

    private var hint: String {
        if settingStart { return "Tap the map to place the start; drag its marker to move it. The loop ends where it starts." }
        if let targetKm, !unreachable.isEmpty {
            let limit = (targetKm * RouteShape.reachFraction).formatted(.number.precision(.fractionLength(0...1)))
            return "Orange pins are more than \(limit) km from the start, too far for a \(RouteFormat.distance(km: targetKm)) loop. Move them closer or raise the distance."
        }
        if start == nil, let failure { return "\(failure) Search for a place or tap Set start to choose one." }
        return shape.canAddPin
            ? "Tap the map to drop a pin, drag to move it. Up to \(RouteShape.maxPins) pins; the loop passes through them in a sensible order."
            : "Up to \(RouteShape.maxPins) pins. Remove one to add another."
    }

    /// Finds where the loop begins without a chosen start; a chosen start never needs the device location.
    private func resolveFallback() async {
        guard shape.start == nil, fallback == nil else { return }
        do {
            fallback = try await StartResolver(timeout: .seconds(5)).resolve { try await LocationProvider().currentPoint() }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func recentre() {
        guard let start else { return }
        let span = max((targetKm ?? 5) * 1000, 2000)
        position = .region(MKCoordinateRegion(center: start.coordinate, latitudinalMeters: span, longitudinalMeters: span))
    }
}
