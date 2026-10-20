import CoreLocation
import Foundation

/// One of the eight compass points a loop's heading can be nudged toward.
public enum CompassPoint: Int, CaseIterable, Codable, Sendable {
    case north, northEast, east, southEast, south, southWest, west, northWest

    /// The bearing in degrees clockwise from north.
    public var degrees: Double { Double(rawValue) * 45 }

    /// `N`, `NE`, `E`, …
    public var label: String {
        ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][rawValue]
    }

    /// The compass point nearest to `degrees`.
    public init(nearest degrees: Double) {
        self = CompassPoint(rawValue: Int((RouteShape.normalised(degrees) / 45).rounded()) % 8) ?? .north
    }
}

/// How the user wants a loop steered: a start and finish other than the device location, up to `maxPins`
/// points to pass through and a rough heading.
public struct RouteShape: Codable, Equatable, Sendable {
    public static let maxPins = 3
    /// The longest straight-line round trip from the start through every pin, as a multiple of the target distance (the server rejects pins beyond it).
    public static let tourFactor = 1.5

    public private(set) var pins: [RoutePoint]
    /// Degrees clockwise from north in `[0, 360)`, or `nil` for no preference.
    public var heading: Double? {
        didSet { heading = heading.flatMap(Self.normalisedHeading) }
    }

    /// Where the loop starts and finishes, or `nil` to use the default start or the device location.
    public private(set) var start: RoutePoint?
    /// What to call `start`; `nil` for a dropped point.
    public private(set) var startName: String?

    public init(pins: [RoutePoint] = [], heading: Double? = nil, start: StartPlace? = nil) {
        self.pins = Array(pins.prefix(Self.maxPins))
        self.heading = heading.flatMap(Self.normalisedHeading)
        self.start = start?.point
        self.startName = start?.name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decodeIfPresent(RoutePoint.self, forKey: .start)
        self.init(
            pins: try container.decodeIfPresent([RoutePoint].self, forKey: .pins) ?? [],
            heading: try container.decodeIfPresent(Double.self, forKey: .heading),
            start: start.map {
                StartPlace(point: $0, name: try? container.decodeIfPresent(String.self, forKey: .startName))
            })
    }

    public var isEmpty: Bool { pins.isEmpty && heading == nil && start == nil }

    /// The chosen start with its name.
    public var startPlace: StartPlace? {
        get { start.map { StartPlace(point: $0, name: startName) } }
        set {
            start = newValue?.point
            startName = newValue?.name
        }
    }

    public var canAddPin: Bool { pins.count < Self.maxPins }

    /// The compass point nearest to `heading`.
    public var compass: CompassPoint? {
        get { heading.map(CompassPoint.init(nearest:)) }
        set { heading = newValue?.degrees }
    }

    /// Appends `pin` unless `maxPins` is reached; returns whether it was added.
    @discardableResult
    public mutating func addPin(_ pin: RoutePoint) -> Bool {
        guard canAddPin else { return false }
        pins.append(pin)
        return true
    }

    public mutating func movePin(at index: Int, to point: RoutePoint) {
        guard pins.indices.contains(index) else { return }
        pins[index] = point
    }

    public mutating func removePin(at index: Int) {
        guard pins.indices.contains(index) else { return }
        pins.remove(at: index)
    }

    /// The indices of all pins when the shortest round trip from `start` through them is longer than the server accepts for a loop of `targetKm`; empty otherwise.
    public func unreachablePins(from start: RoutePoint, targetKm: Double) -> Set<Int> {
        guard !pins.isEmpty else { return [] }
        return shortestTourMeters(from: start) > targetKm * 1000 * Self.tourFactor ? Set(pins.indices) : []
    }

    /// The length of the shortest straight-line round trip from `start` through every pin.
    public func shortestTourMeters(from start: RoutePoint) -> Double {
        func length(_ order: [RoutePoint]) -> Double {
            let path = [start] + order + [start]
            return zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distanceMeters(to: $1.1) }
        }
        func orders(_ items: [RoutePoint]) -> [[RoutePoint]] {
            guard items.count > 1 else { return [items] }
            return items.indices.flatMap { i in
                var rest = items
                let first = rest.remove(at: i)
                return orders(rest).map { [first] + $0 }
            }
        }
        return orders(pins).map(length).min() ?? 0
    }

    /// e.g. `Custom start · 2 pins · NE`; `Off` when empty.
    public var summary: String {
        var parts: [String] = []
        if start != nil { parts.append("Custom start") }
        if !pins.isEmpty { parts.append(pins.count == 1 ? "1 pin" : "\(pins.count) pins") }
        if let compass { parts.append(compass.label) }
        return parts.isEmpty ? "Off" : parts.joined(separator: " · ")
    }

    /// `request` with this shape's pins and heading; an empty shape leaves it unchanged.
    public func applied(to request: RouteRequest) -> RouteRequest {
        var copy = request
        copy.waypoints = pins.isEmpty ? nil : pins
        copy.heading = heading
        return copy
    }

    /// `degrees` wrapped into `[0, 360)`.
    static func normalised(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private static func normalisedHeading(_ degrees: Double) -> Double? {
        degrees.isFinite ? normalised(degrees) : nil
    }
}

extension RoutePoint {
    /// Great-circle distance to `other` in metres.
    public func distanceMeters(to other: RoutePoint) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
