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

/// How the user wants a loop steered: up to `maxPins` points to pass through and a rough heading.
public struct RouteShape: Codable, Equatable, Sendable {
    public static let maxPins = 3
    /// The furthest a pin may sit from the start, as a fraction of the target distance (the server rejects pins beyond it).
    public static let reachFraction = 0.75

    public private(set) var pins: [RoutePoint]
    /// Degrees clockwise from north in `[0, 360)`, or `nil` for no preference.
    public var heading: Double? {
        didSet { heading = heading.flatMap(Self.normalisedHeading) }
    }

    public init(pins: [RoutePoint] = [], heading: Double? = nil) {
        self.pins = Array(pins.prefix(Self.maxPins))
        self.heading = heading.flatMap(Self.normalisedHeading)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            pins: try container.decodeIfPresent([RoutePoint].self, forKey: .pins) ?? [],
            heading: try container.decodeIfPresent(Double.self, forKey: .heading))
    }

    public var isEmpty: Bool { pins.isEmpty && heading == nil }

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

    /// The indices of pins further from `start` than the server accepts for a loop of `targetKm`.
    public func unreachablePins(from start: RoutePoint, targetKm: Double) -> Set<Int> {
        let limit = targetKm * 1000 * Self.reachFraction
        return Set(pins.indices.filter { start.distanceMeters(to: pins[$0]) > limit })
    }

    /// e.g. `2 pins · NE`; `Off` when empty.
    public var summary: String {
        var parts: [String] = []
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
