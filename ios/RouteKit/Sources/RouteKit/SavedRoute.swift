import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

@Model
public final class SavedRoute {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date
    public var targetDistanceKm: Double
    public var distanceKm: Double
    public var ascentM: Double
    public var descentM: Double
    public var elevationGainPerKm: Double
    public var hilliness: String
    public var greenScore: Double
    public var previewUrl: String?
    /// The `PlannedRun.key` this route was generated for, when it came from a calendar run.
    public var eventKey: String?
    private var pointsData: Data
    private var warningsData: Data?

    public init(
        name: String,
        targetDistanceKm: Double,
        summary: RouteSummary,
        previewUrl: String?,
        points: [RoutePoint],
        warnings: [String] = [],
        eventKey: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.targetDistanceKm = targetDistanceKm
        self.distanceKm = summary.distanceKm
        self.ascentM = summary.ascentM
        self.descentM = summary.descentM
        self.elevationGainPerKm = summary.elevationGainPerKm
        self.hilliness = summary.hilliness
        self.greenScore = summary.greenScore
        self.previewUrl = previewUrl
        self.eventKey = eventKey
        self.pointsData = (try? JSONEncoder().encode(points)) ?? Data()
        self.warningsData = try? JSONEncoder().encode(warnings)
    }

    /// Replaces the route's geometry and metrics, keeping its identity, name and event.
    public func update(
        targetDistanceKm: Double, summary: RouteSummary, previewUrl: String?, points: [RoutePoint], warnings: [String]
    ) {
        self.targetDistanceKm = targetDistanceKm
        distanceKm = summary.distanceKm
        ascentM = summary.ascentM
        descentM = summary.descentM
        elevationGainPerKm = summary.elevationGainPerKm
        hilliness = summary.hilliness
        greenScore = summary.greenScore
        self.previewUrl = previewUrl
        pointsData = (try? JSONEncoder().encode(points)) ?? Data()
        warningsData = try? JSONEncoder().encode(warnings)
    }

    /// The server warnings from when the route was generated.
    public var warnings: [String] {
        warningsData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }

    public var points: [RoutePoint] {
        (try? JSONDecoder().decode([RoutePoint].self, from: pointsData)) ?? []
    }

    public var gpxFile: GPXFile {
        GPXFile(name: name, gpx: GPXWriter.gpx(points: points, name: name))
    }
}

extension SavedRoute {
    /// The shared on-disk store, in the app's default container.
    @MainActor
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: SavedRoute.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
    }
}

/// A GPX document that shares as a `.gpx` file.
public struct GPXFile: Transferable, Sendable {
    public static let contentType = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)

    public var name: String
    public var gpx: String

    public init(name: String, gpx: String) {
        self.name = name
        self.gpx = gpx
    }

    /// A filesystem-safe file name ending in `.gpx`.
    public var filename: String {
        let slug =
            name
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
        return (slug.isEmpty ? "route" : slug) + ".gpx"
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: contentType) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: file.filename)
            try Data(file.gpx.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
