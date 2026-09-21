import RouteKit
import SwiftData
import SwiftUI

struct GenerateView: View {
    @AppStorage("distanceKm") private var distanceKm = 5.0
    @AppStorage("hillsPreference") private var hills = 0.0
    @AppStorage("greenPreference") private var green = 0.0

    @State private var phase = Phase.idle
    @State private var savedID: UUID?

    private let service = RouteService()
    private let location = LocationProvider()

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
                        Button(action: generate) {
                            HStack {
                                Text("Generate route from here")
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
                        result(response, points)
                    }
                }
                .onChange(of: resultID) {
                    guard resultID != nil else { return }
                    withAnimation { proxy.scrollTo("result", anchor: .top) }
                }
            }
            .navigationTitle("Loopr")
        }
    }

    private var resultID: String? {
        if case .done(let response, _) = phase { response.filename + String(response.route.distanceKm) } else { nil }
    }

    private var isLoading: Bool {
        if case .loading = phase { true } else { false }
    }

    @ViewBuilder
    private func result(_ response: RouteResponse, _ points: [RoutePoint]) -> some View {
        Section {
            RouteMapView(points: points, interactive: false)
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
                save(response, points)
            }
            .disabled(savedID != nil)
            ShareLink(
                item: GPXFile(name: name(for: response), gpx: GPXWriter.gpx(points: points, name: name(for: response))),
                preview: SharePreview(name(for: response))
            ) {
                Label("Share GPX", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func name(for response: RouteResponse) -> String {
        RouteFormat.name(distanceKm: response.route.distanceKm)
    }

    private func generate() {
        let regenerate = if case .done = phase { true } else { false }
        phase = .loading
        savedID = nil
        Task {
            do {
                let coordinate = try await location.currentCoordinate()
                LastStartStore().save(RoutePoint(longitude: coordinate.longitude, latitude: coordinate.latitude))
                var request = RouteRequest(
                    targetDistanceKm: distanceKm,
                    startLongitude: coordinate.longitude,
                    startLatitude: coordinate.latitude,
                    hillsPreference: hills,
                    greenPreference: green
                )
                if regenerate { request = request.regenerated() }
                let response = try await service.generate(request)
                let points = response.resolvedPoints()
                phase = points.isEmpty ? .failed("The route had no geometry.") : .done(response, points)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func save(_ response: RouteResponse, _ points: [RoutePoint]) {
        savedID = RouteStore.save(response: response, points: points).id
    }
}
