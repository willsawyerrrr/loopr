import Foundation
import Testing

@testable import RouteKit

private func freshStore() -> LastStartStore {
    let suite = "test-\(UUID().uuidString)"
    return LastStartStore(defaults: UserDefaults(suiteName: suite)!)
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
        let start = try await StartResolver(store: store).resolve { here }
        #expect(start == ResolvedStart(point: here, source: .current))
        #expect(store.value == here)
    }

    @Test func fallsBackWhenLocationFails() async throws {
        struct Denied: Error {}
        let store = freshStore()
        store.save(before)
        let start = try await StartResolver(store: store).resolve { throw Denied() }
        #expect(start == ResolvedStart(point: before, source: .lastUsed))
    }

    @Test func fallsBackWhenLocationIsSlow() async throws {
        let store = freshStore()
        store.save(before)
        let here = here
        let start = try await StartResolver(store: store, timeout: .milliseconds(50)).resolve {
            try await Task.sleep(for: .seconds(30))
            return here
        }
        #expect(start.source == .lastUsed)
        #expect(store.value == before)
    }

    @Test func failsWithoutAnyStart() async {
        await #expect(throws: StartUnavailableError.self) {
            try await StartResolver(store: freshStore()).resolve { throw CancellationError() }
        }
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
