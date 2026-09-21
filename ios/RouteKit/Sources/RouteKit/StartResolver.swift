import Foundation

/// The last route start point, kept so background runs work when a location fix isn't available.
public struct LastStartStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "lastStartPoint"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var value: RoutePoint? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(RoutePoint.self, from: $0) }
    }

    public func save(_ point: RoutePoint) {
        defaults.set(try? JSONEncoder().encode(point), forKey: key)
    }
}

public struct ResolvedStart: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case current
        case lastUsed
    }

    public var point: RoutePoint
    public var source: Source
}

public struct StartUnavailableError: LocalizedError, Equatable, Sendable {
    public var errorDescription: String? {
        "No start location yet. Open Runna Router once and allow location access, then try again."
    }
}

/// Picks a route start: a fresh location fix if one arrives in time, otherwise the last one used.
public struct StartResolver: Sendable {
    private let store: LastStartStore
    private let timeout: Duration

    public init(store: LastStartStore = LastStartStore(), timeout: Duration = .seconds(8)) {
        self.store = store
        self.timeout = timeout
    }

    public func resolve(current: @escaping @Sendable () async throws -> RoutePoint) async throws -> ResolvedStart {
        let timeout = timeout
        let fix = await withTaskGroup(of: RoutePoint?.self) { group in
            group.addTask { try? await current() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let fix {
            store.save(fix)
            return ResolvedStart(point: fix, source: .current)
        }
        if let last = store.value {
            return ResolvedStart(point: last, source: .lastUsed)
        }
        throw StartUnavailableError()
    }
}
