import Foundation
import SwiftData
import Testing

@testable import RouteKit

private let start = RoutePoint(longitude: 151.2093, latitude: -33.8688)

private func json(_ request: RouteRequest) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
}

@Suite struct RouteShapeTests {
    @Test func capsPinsAtThree() {
        var shape = RouteShape(pins: (0..<5).map { RoutePoint(longitude: Double($0), latitude: 0) })
        #expect(shape.pins.count == 3)
        #expect(!shape.canAddPin)
        let addedAtCap = shape.addPin(start)
        #expect(!addedAtCap)
        shape.removePin(at: 0)
        let addedAfterRemoval = shape.addPin(start)
        #expect(addedAfterRemoval)
        #expect(shape.pins.last == start)
    }

    @Test func normalisesHeading() {
        #expect(RouteShape(heading: 450).heading == 90)
        #expect(RouteShape(heading: -90).heading == 270)
        #expect(RouteShape(heading: 360).heading == 0)
        #expect(RouteShape(heading: .nan).heading == nil)
        var shape = RouteShape()
        shape.heading = -45
        #expect(shape.heading == 315)
    }

    @Test func mapsCompassPointsToDegrees() {
        #expect(CompassPoint.allCases.map(\.label) == ["N", "NE", "E", "SE", "S", "SW", "W", "NW"])
        #expect(CompassPoint.allCases.map(\.degrees) == [0, 45, 90, 135, 180, 225, 270, 315])
        #expect(CompassPoint(nearest: 100) == .east)
        #expect(CompassPoint(nearest: 350) == .north)
        #expect(CompassPoint(nearest: 22.6) == .northEast)
        var shape = RouteShape()
        shape.compass = .southWest
        #expect(shape.heading == 225)
        shape.compass = nil
        #expect(shape.heading == nil)
    }

    @Test func emptyAndSummary() {
        #expect(RouteShape().isEmpty)
        #expect(RouteShape().summary == "Off")
        #expect(RouteShape(pins: [start]).summary == "1 pin")
        #expect(RouteShape(pins: [start, start], heading: 40).summary == "2 pins · NE")
        #expect(!RouteShape(heading: 0).isEmpty)
    }

    @Test func codableRoundTrip() throws {
        let shape = RouteShape(pins: [start, RoutePoint(longitude: 151.22, latitude: -33.85)], heading: 90)
        let decoded = try JSONDecoder().decode(RouteShape.self, from: JSONEncoder().encode(shape))
        #expect(decoded == shape)
        let lenient = try JSONDecoder().decode(RouteShape.self, from: Data(#"{"heading":-10}"#.utf8))
        #expect(lenient == RouteShape(heading: 350))
    }

    @Test func requestOmitsEmptyShape() throws {
        let request = RouteRequest(targetDistanceKm: 5, startLongitude: 0, startLatitude: 0)
        let plain = try json(RouteShape().applied(to: request))
        #expect(plain["waypoints"] == nil)
        #expect(plain["heading"] == nil)
    }

    @Test func requestCarriesPinsAndHeading() throws {
        let request = RouteRequest(targetDistanceKm: 5, startLongitude: 0, startLatitude: 0)
        let shaped = try json(RouteShape(pins: [start], heading: 90).applied(to: request))
        #expect(shaped["waypoints"] as? [[Double]] == [[151.2093, -33.8688]])
        #expect(shaped["heading"] as? Double == 90)
        let headingOnly = try json(RouteShape(heading: 0).applied(to: request))
        #expect(headingOnly["waypoints"] == nil)
        #expect(headingOnly["heading"] as? Double == 0)
    }

    @Test func flagsPinsBeyondReach() {
        let near = RoutePoint(longitude: 151.2093, latitude: -33.8598)  // ~1 km north
        let far = RoutePoint(longitude: 151.2093, latitude: -33.7788)  // ~10 km north
        let shape = RouteShape(pins: [near, far])
        #expect(shape.unreachablePins(from: start, targetKm: 5) == [1])
        #expect(shape.unreachablePins(from: start, targetKm: 20).isEmpty)
    }

    @Test func measuresDistance() {
        let north = RoutePoint(longitude: 151.2093, latitude: -33.8598)
        #expect(abs(start.distanceMeters(to: north) - 1000) < 20)
    }
}

@Suite @MainActor struct SavedShapeTests {
    private let summary = RouteSummary(
        distanceKm: 3, ascentM: 1, descentM: 1, elevationGainPerKm: 1, hilliness: "flat", greenScore: 0)

    @Test func persistsAndClearsShape() throws {
        let container = try SavedRoute.makeContainer(inMemory: true)
        let shape = RouteShape(pins: [start], heading: 135)
        let route = SavedRoute(
            name: "Loop", targetDistanceKm: 3, summary: summary, previewUrl: nil, points: [start], shape: shape)
        container.mainContext.insert(route)
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(FetchDescriptor<SavedRoute>()).first?.shape == shape)

        route.update(targetDistanceKm: 3, summary: summary, previewUrl: nil, points: [start], warnings: [], shape: RouteShape())
        #expect(route.shape == nil)
    }

    @Test func routesWithoutShapeHaveNone() {
        let route = SavedRoute(name: "Loop", targetDistanceKm: 3, summary: summary, previewUrl: nil, points: [])
        #expect(route.shape == nil)
    }
}
