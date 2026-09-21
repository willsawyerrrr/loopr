import Foundation

/// A chosen route start: a point and, when known, what to call it.
public struct StartPlace: Codable, Equatable, Sendable {
    public var point: RoutePoint
    /// A place or address name; `nil` for a dropped point.
    public var name: String?

    public init(point: RoutePoint, name: String? = nil) {
        self.point = point
        self.name = Self.cleaned(name)
    }

    /// `name`, else `Dropped pin`.
    public var displayName: String { name ?? "Dropped pin" }

    /// `name` trimmed, or `nil` when blank.
    static func cleaned(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

/// The start used for any route that has none of its own, kept in `UserDefaults`.
public struct DefaultStartStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "defaultStart"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var value: StartPlace? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(StartPlace.self, from: $0) }
    }

    /// Saves `place`, or removes the default when `nil`.
    public func save(_ place: StartPlace?) {
        if let place, let data = try? JSONEncoder().encode(place) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
