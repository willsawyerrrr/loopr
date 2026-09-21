import MapKit
import Observation
import RouteKit
import SwiftUI

/// Completes a typed place or address and looks up the chosen suggestion.
@MainActor
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    var query = "" {
        didSet { completer.queryFragment = query }
    }

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { suggestions = self.completer.results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }

    /// The place `suggestion` stands for.
    func place(for suggestion: MKLocalSearchCompletion) async -> StartPlace? {
        await place(for: MKLocalSearch.Request(completion: suggestion))
    }

    /// The best match for the typed `query`.
    func firstPlace() async -> StartPlace? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        return await place(for: request)
    }

    private func place(for request: MKLocalSearch.Request) async -> StartPlace? {
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        return StartPlace(point: RoutePoint(longitude: coordinate.longitude, latitude: coordinate.latitude), name: item.name)
    }
}

/// Names a dropped start after what is there, when it can be told.
enum StartNaming {
    /// Sets `place` to a nameless start at `point`, then fills in its name once looked up.
    @MainActor
    static func drop(at point: RoutePoint, into place: Binding<StartPlace?>) {
        place.wrappedValue = StartPlace(point: point)
        Task { await name(place, at: point) }
    }

    /// Names the start at `point` unless it has since moved.
    @MainActor
    static func name(_ place: Binding<StartPlace?>, at point: RoutePoint) async {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: point.latitude, longitude: point.longitude)),
            let name = try? await request.mapItems.first?.name,
            place.wrappedValue == StartPlace(point: point)
        else { return }
        place.wrappedValue = StartPlace(point: point, name: name)
    }
}

extension View {
    /// Adds a search field with place suggestions; `onPick` receives the chosen place.
    func startSearchable(onPick: @escaping (StartPlace) -> Void) -> some View {
        modifier(StartSearch(onPick: onPick))
    }
}

private struct StartSearch: ViewModifier {
    let onPick: (StartPlace) -> Void

    @State private var search = PlaceSearch()
    @State private var searching = false

    func body(content: Content) -> some View {
        content
            .searchable(text: $search.query, isPresented: $searching, prompt: "Search for a place or address")
            .searchSuggestions {
                ForEach(search.suggestions, id: \.self) { suggestion in
                    Button {
                        Task { finish(await search.place(for: suggestion)) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(suggestion.title)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onSubmit(of: .search) { Task { finish(await search.firstPlace()) } }
    }

    private func finish(_ place: StartPlace?) {
        guard let place else { return }
        onPick(place)
        searching = false
        search.query = ""
    }
}

/// Makes a start marker draggable; `onMove` gets the point under the finger and `onEnd` fires on release.
private struct DraggableStart: ViewModifier {
    let proxy: MapProxy
    let space: String
    let onMove: (RoutePoint) -> Void
    let onEnd: () -> Void

    func body(content: Content) -> some View {
        content
            .onTapGesture {}
            .gesture(
                DragGesture(coordinateSpace: .named(space))
                    .onChanged { drag in
                        guard let point = proxy.convert(drag.location, from: .named(space)) else { return }
                        onMove(RoutePoint(longitude: point.longitude, latitude: point.latitude))
                    }
                    .onEnded { _ in onEnd() }
            )
    }
}

extension View {
    func draggableStart(proxy: MapProxy, space: String, onMove: @escaping (RoutePoint) -> Void, onEnd: @escaping () -> Void)
        -> some View
    {
        modifier(DraggableStart(proxy: proxy, space: space, onMove: onMove, onEnd: onEnd))
    }
}
