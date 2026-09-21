import CoreLocation

/// A route point in GeoJSON order, with optional elevation in metres.
public struct RoutePoint: Codable, Hashable, Sendable {
    public var longitude: Double
    public var latitude: Double
    public var elevation: Double?

    public init(longitude: Double, latitude: Double, elevation: Double? = nil) {
        self.longitude = longitude
        self.latitude = latitude
        self.elevation = elevation
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Decodes the API's `[lon, lat]` / `[lon, lat, ele]` array form.
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        longitude = try container.decode(Double.self)
        latitude = try container.decode(Double.self)
        elevation = container.isAtEnd ? nil : try container.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(longitude)
        try container.encode(latitude)
        if let elevation { try container.encode(elevation) }
    }
}
