import Foundation

/// The last device location a route started from, kept so background runs work when a location fix isn't available.
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
        /// A fresh device location fix.
        case current
        /// The last device location, when no fix arrived in time.
        case lastUsed
        /// The route's own chosen start.
        case chosen
        /// The default start from Settings.
        case defaultStart
    }

    public var point: RoutePoint
    public var source: Source
    /// The chosen place's name, for `chosen` and `defaultStart`.
    public var name: String?

    public init(point: RoutePoint, source: Source, name: String? = nil) {
        self.point = point
        self.source = source
        self.name = name
    }

    /// `Current location`, `Last start point` or the chosen place's name.
    public var label: String {
        switch source {
        case .current: "Current location"
        case .lastUsed: "Last start point"
        case .chosen, .defaultStart: name ?? "Dropped pin"
        }
    }
}

public struct StartUnavailableError: LocalizedError, Equatable, Sendable {
    public var errorDescription: String? {
        "No start location yet. Open Loopr once and allow location access, or set a default start in Settings, then try again."
    }
}

/// Picks a route start: the route's own chosen place, else the default start, else a fresh location fix
/// if one arrives in time, else the last device location.
public struct StartResolver: Sendable {
    private let store: LastStartStore
    private let defaultStore: DefaultStartStore
    private let timeout: Duration

    public init(
        store: LastStartStore = LastStartStore(), defaultStore: DefaultStartStore = DefaultStartStore(),
        timeout: Duration = .seconds(8)
    ) {
        self.store = store
        self.defaultStore = defaultStore
        self.timeout = timeout
    }

    /// Resolves `chosen` or the default start without asking for the device location; otherwise waits
    /// for `current`. Only a real fix updates the last-used store.
    public func resolve(
        chosen: StartPlace? = nil, current: @escaping @Sendable () async throws -> RoutePoint
    ) async throws -> ResolvedStart {
        if let chosen { return ResolvedStart(point: chosen.point, source: .chosen, name: chosen.name) }
        if let place = defaultStore.value { return ResolvedStart(point: place.point, source: .defaultStart, name: place.name) }
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
