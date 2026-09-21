import RouteKit
import SwiftData
import SwiftUI

struct GenerateView: View {
    @AppStorage("distanceKm") private var distanceKm = 5.0
    @AppStorage("hillsPreference") private var hills = 0.0
    @AppStorage("greenPreference") private var green = 0.0

    @State private var phase = Phase.idle
    @State private var savedID: UUID?
    @State private var shape = RouteShape()
    @State private var usedShape = RouteShape()
    @State private var usedStart: ResolvedStart?
    @State private var showShape = false

    private let service = RouteService()

    private enum Phase {
        case idle
        case loading
        case done(RouteResponse, [RoutePoint])
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section("Route") {
                        Stepper(value: $distanceKm, in: 1...50, step: 0.5) {
                            LabeledContent("Distance", value: "\(distanceKm.formatted(.number.precision(.fractionLength(0...1)))) km")
                        }
                        PreferenceSliders()
                        ShapeRow(shape: shape) { showShape = true }
                        Button(action: generate) {
                            HStack {
                                Text("Generate route")
                                if case .loading = phase {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isLoading)
                    }

                    switch phase {
                    case .idle, .loading:
                        EmptyView()
                    case .failed(let message):
                        Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                    case .done(let response, let points):
                        RouteResultSections(
                            response: response, points: points, pins: usedShape.pins, shape: usedShape,
            startLabel: usedStart?.label, savedID: $savedID)
                    }
                }
                .onChange(of: resultID) {
                    guard resultID != nil else { return }
                    withAnimation { proxy.scrollTo("result", anchor: .top) }
                }
            }
            .navigationTitle("Loopr")
            .sheet(isPresented: $showShape) { ShapeSheet(shape: $shape, targetKm: distanceKm) }
        }
    }

    private var resultID: String? {
        if case .done(let response, _) = phase { response.filename + String(response.route.distanceKm) } else { nil }
    }

    private var isLoading: Bool {
        if case .loading = phase { true } else { false }
    }

    private func generate() {
        let regenerate = if case .done = phase { true } else { false }
        phase = .loading
        savedID = nil
        usedShape = shape
        Task {
            do {
                let start = try await StartResolver().resolve(chosen: usedShape.startPlace) {
                    try await LocationProvider().currentPoint()
                }
                usedStart = start
                var request = RouteRequest(
                    targetDistanceKm: distanceKm,
                    startLongitude: start.point.longitude,
                    startLatitude: start.point.latitude,
                    hillsPreference: hills,
                    greenPreference: green
                )
                request = usedShape.applied(to: request)
                if regenerate { request = request.regenerated() }
                let response = try await service.generate(request)
                let points = response.resolvedPoints()
                phase = points.isEmpty ? .failed("The route had no geometry.") : .done(response, points)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
