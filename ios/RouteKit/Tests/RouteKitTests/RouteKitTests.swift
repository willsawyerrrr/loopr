import Foundation
import SwiftData
import Testing

@testable import RouteKit

private let gpxFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="loopr" xmlns="http://www.topografix.com/GPX/1/1">
      <trk><name>Loop</name><trkseg>
        <trkpt lat="-33.8688" lon="151.2093"><ele>12.5</ele></trkpt>
        <trkpt lat="-33.8690" lon="151.2100"/>
      </trkseg></trk>
    </gpx>
    """

private func responseJSON(coordinates: String?) -> Data {
    let gpx =
        gpxFixture
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    let coords = coordinates.map { ",\"coordinates\":\($0)" } ?? ""
    return Data(
        """
        {"gpx":"\(gpx)","filename":"route-3km.gpx","targetDistanceKm":3,
         "route":{"distanceKm":3.02,"ascentM":140,"descentM":138,"elevationGainPerKm":46.4,
                  "hilliness":"hilly","greenScore":0.1,"overriddenParameters":{"avoidRepetition":false}},
         "segments":[],"checksum":{"ok":true},"warnings":["careful"],
         "previewUrl":"https://example.com/api/preview?id=abc"\(coords)}
        """.utf8)
}

@Suite struct DecodingTests {
    @Test func decodesCoordinatesWhenPresent() throws {
        let data = responseJSON(coordinates: "[[151.2,-33.8,10],[151.3,-33.9]]")
        let response = try JSONDecoder().decode(RouteResponse.self, from: data)
        #expect(response.route.distanceKm == 3.02)
        #expect(response.route.hilliness == "hilly")
        #expect(response.warnings == ["careful"])
        #expect(response.previewUrl == "https://example.com/api/preview?id=abc")
        let points = response.resolvedPoints()
        #expect(
            points == [
                RoutePoint(longitude: 151.2, latitude: -33.8, elevation: 10),
                RoutePoint(longitude: 151.3, latitude: -33.9),
            ])
    }

    @Test func fallsBackToGPXWithoutCoordinates() throws {
        let response = try JSONDecoder().decode(RouteResponse.self, from: responseJSON(coordinates: nil))
        #expect(response.coordinates == nil)
        #expect(
            response.resolvedPoints() == [
                RoutePoint(longitude: 151.2093, latitude: -33.8688, elevation: 12.5),
                RoutePoint(longitude: 151.2100, latitude: -33.8690),
            ])
    }
}

@Suite struct GPXTests {
    @Test func writesAndReparses() {
        let points = [
            RoutePoint(longitude: 151.2093, latitude: -33.8688, elevation: 12.5),
            RoutePoint(longitude: 151.21, latitude: -33.869),
        ]
        let gpx = GPXWriter.gpx(points: points, name: "A & B <run>")
        #expect(gpx.contains("<name>A &amp; B &lt;run&gt;</name>"))
        #expect(gpx.contains("<trkpt lat=\"-33.8688\" lon=\"151.2093\"><ele>12.5</ele></trkpt>"))
        #expect(gpx.contains("<trkpt lat=\"-33.869\" lon=\"151.21\"/>"))
        #expect(GPXParser.points(in: gpx) == points)
    }

    @Test func filenameIsSlugged() {
        #expect(GPXFile(name: "Long Run — 10 km!", gpx: "").filename == "long-run-10-km.gpx")
        #expect(GPXFile(name: "!!!", gpx: "").filename == "route.gpx")
    }
}

@Suite struct ServiceTests {
    private func service(status: Int, body: Data, capture: @escaping @Sendable (URLRequest) -> Void = { _ in }) -> RouteService {
        RouteService(baseURL: URL(string: "https://example.com")!) { request in
            capture(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }
    }

    @Test func postsRequestBody() async throws {
        final class Box: @unchecked Sendable { var request: URLRequest? }
        let box = Box()
        let service = service(status: 200, body: responseJSON(coordinates: nil)) { box.request = $0 }
        _ = try await service.generate(
            RouteRequest(
                targetDistanceKm: 5, startLongitude: 151.2, startLatitude: -33.8, hillsPreference: -0.5, greenPreference: 0.25
            ))
        let request = try #require(box.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/route")
        let json = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(json["targetDistanceKm"] as? Double == 5)
        #expect(json["start"] as? [Double] == [151.2, -33.8])
        #expect(json["hillsPreference"] as? Double == -0.5)
        #expect(json["greenPreference"] as? Double == 0.25)
    }

    @Test func omitsVariantUntilRegenerated() throws {
        let request = RouteRequest(targetDistanceKm: 5, startLongitude: 0, startLatitude: 0)
        func json(_ request: RouteRequest) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        }
        #expect(try json(request)["variant"] == nil)

        var next = 0
        let first = request.regenerated { next += 1; return next }
        let second = request.regenerated { next += 1; return next }
        #expect(try json(first)["variant"] as? Int == 1)
        #expect(try json(second)["variant"] as? Int == 2)
        #expect(request.variant == nil)
    }

    @Test func regeneratedVariantsStayInRange() throws {
        let request = RouteRequest(targetDistanceKm: 5, startLongitude: 0, startLatitude: 0)
        for _ in 0..<100 {
            #expect(RouteRequest.variantRange.contains(try #require(request.regenerated().variant)))
        }
    }

    @Test func surfacesServerErrors() async {
        let body = Data(#"{"error":"Trail Router failed","detail":"timeout"}"#.utf8)
        let service = service(status: 502, body: body)
        await #expect(throws: RouteServiceError.self) {
            _ = try await service.generate(RouteRequest(targetDistanceKm: 5, startLongitude: 0, startLatitude: 0))
        }
        do {
            _ = try await service.generate(RouteRequest(targetDistanceKm: 5, startLongitude: 0, startLatitude: 0))
        } catch {
            #expect(error.localizedDescription == "Trail Router failed: timeout")
        }
    }
}

@Suite @MainActor struct StoreTests {
    @Test func savesAndReloadsRoute() throws {
        let container = try SavedRoute.makeContainer(inMemory: true)
        let points = [RoutePoint(longitude: 1, latitude: 2, elevation: 3), RoutePoint(longitude: 4, latitude: 5)]
        let summary = RouteSummary(distanceKm: 3, ascentM: 10, descentM: 9, elevationGainPerKm: 3.3, hilliness: "flat", greenScore: 0)
        container.mainContext.insert(SavedRoute(name: "Loop", targetDistanceKm: 3, summary: summary, previewUrl: nil, points: points))
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(FetchDescriptor<SavedRoute>())
        #expect(fetched.count == 1)
        #expect(fetched[0].points == points)
        #expect(fetched[0].gpxFile.gpx.contains("<name>Loop</name>"))
    }
}
