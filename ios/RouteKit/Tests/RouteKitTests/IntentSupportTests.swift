import Foundation
import Testing

@testable import RouteKit

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "test-\(UUID().uuidString)")!
}

private func freshStore() -> LastStartStore {
    LastStartStore(defaults: freshDefaults())
}

private func resolver(
    store: LastStartStore = freshStore(), defaultStart: StartPlace? = nil, timeout: Duration = .seconds(8)
) -> StartResolver {
    let defaultStore = DefaultStartStore(defaults: freshDefaults())
    defaultStore.save(defaultStart)
    return StartResolver(store: store, defaultStore: defaultStore, timeout: timeout)
}

@Suite struct RouteDistanceTests {
    @Test func convertsKilometresAndMiles() throws {
        #expect(try RouteDistance.kilometres(from: .init(value: 10, unit: .kilometers)) == 10)
        #expect(try RouteDistance.kilometres(from: .init(value: 5, unit: .miles)) == 8.05)
        #expect(try RouteDistance.kilometres(from: .init(value: 5000, unit: .meters)) == 5)
    }

    @Test func rejectsOutOfRange() {
        #expect(throws: RouteDistanceError.self) { try RouteDistance.kilometres(from: .init(value: 0.4, unit: .kilometers)) }
        #expect(throws: RouteDistanceError.self) { try RouteDistance.kilometres(from: .init(value: 80, unit: .kilometers)) }
        #expect(throws: RouteDistanceError.self) { try RouteDistance.kilometres(from: .init(value: -5, unit: .kilometers)) }
    }
}

@Suite struct StartResolverTests {
    private let here = RoutePoint(longitude: 151.2, latitude: -33.8)
    private let before = RoutePoint(longitude: 144.9, latitude: -37.8)

    @Test func prefersFreshFixAndRemembersIt() async throws {
        let store = freshStore()
        store.save(before)
        let here = here
        let start = try await resolver(store: store).resolve { here }
        #expect(start == ResolvedStart(point: here, source: .current))
        #expect(store.value == here)
    }

    @Test func fallsBackWhenLocationFails() async throws {
        struct Denied: Error {}
        let store = freshStore()
        store.save(before)
        let start = try await resolver(store: store).resolve { throw Denied() }
        #expect(start == ResolvedStart(point: before, source: .lastUsed))
    }

    @Test func fallsBackWhenLocationIsSlow() async throws {
        let store = freshStore()
        store.save(before)
        let here = here
        let start = try await resolver(store: store, timeout: .milliseconds(50)).resolve {
            try await Task.sleep(for: .seconds(30))
            return here
        }
        #expect(start.source == .lastUsed)
        #expect(store.value == before)
    }

    @Test func failsWithoutAnyStart() async {
        await #expect(throws: StartUnavailableError.self) {
            try await resolver().resolve { throw CancellationError() }
        }
    }
}

@Suite struct ChosenStartTests {
    private let here = RoutePoint(longitude: 151.2, latitude: -33.8)
    private let before = RoutePoint(longitude: 144.9, latitude: -37.8)
    private let home = StartPlace(point: RoutePoint(longitude: 153.0, latitude: -27.5), name: "Home")
    private let park = StartPlace(point: RoutePoint(longitude: 138.6, latitude: -34.9), name: "Botanic Park")

    @Test func chosenStartSkipsLocationAndLeavesLastUsedAlone() async throws {
        let store = freshStore()
        store.save(before)
        let start = try await resolver(store: store).resolve(chosen: park) {
            Issue.record("asked for the device location")
            return RoutePoint(longitude: 0, latitude: 0)
        }
        #expect(start == ResolvedStart(point: park.point, source: .chosen, name: "Botanic Park"))
        #expect(start.label == "Botanic Park")
        #expect(store.value == before)
    }

    @Test func chosenStartBeatsTheDefault() async throws {
        let start = try await resolver(defaultStart: home).resolve(chosen: park) { throw CancellationError() }
        #expect(start.point == park.point)
        #expect(start.source == .chosen)
    }

    @Test func defaultStartStandsInForTheDeviceLocation() async throws {
        let store = freshStore()
        store.save(before)
        let start = try await resolver(store: store, defaultStart: home).resolve {
            Issue.record("asked for the device location")
            return RoutePoint(longitude: 0, latitude: 0)
        }
        #expect(start == ResolvedStart(point: home.point, source: .defaultStart, name: "Home"))
        #expect(store.value == before)
    }

    @Test func noChosenStartKeepsDeviceBehaviour() async throws {
        let store = freshStore()
        let here = here
        let start = try await resolver(store: store).resolve { here }
        #expect(start == ResolvedStart(point: here, source: .current))
        #expect(store.value == here)
        #expect(start.label == "Current location")
    }

    @Test func labelsTheLastUsedStartAndDroppedPoints() {
        #expect(ResolvedStart(point: here, source: .lastUsed).label == "Last start point")
        #expect(ResolvedStart(point: here, source: .chosen).label == "Dropped pin")
    }

    @Test func defaultStorePersistsNameAndCoordinateAndClears() {
        let store = DefaultStartStore(defaults: freshDefaults())
        #expect(store.value == nil)
        store.save(home)
        #expect(store.value == home)
        store.save(StartPlace(point: home.point, name: "  "))
        #expect(store.value?.name == nil)
        store.save(nil)
        #expect(store.value == nil)
    }
}

@Suite struct RouteFormatTests {
    @Test func formats() {
        #expect(RouteFormat.distance(km: 10) == "10 km")
        #expect(RouteFormat.distance(km: 10.024) == "10.02 km")
        #expect(RouteFormat.name(distanceKm: 5.5) == "5.5 km route")
        #expect(RouteFormat.subtitle(distanceKm: 10.02, ascentM: 139.6) == "10.02 km · 140 m climb")
    }
}
