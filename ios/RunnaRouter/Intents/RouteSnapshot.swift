import MapKit
import RouteKit
import UIKit

/// Renders a route onto a static map image. Snippets are snapshots, so a live `Map` would render blank.
enum RouteSnapshot {
    static let size = CGSize(width: 360, height: 200)

    static func png(points: [RoutePoint]) async -> Data? {
        let coordinates = points.map(\.coordinate)
        guard coordinates.count > 1 else { return nil }

        let rect = coordinates.reduce(MKMapRect.null) {
            $0.union(MKMapRect(origin: MKMapPoint($1), size: MKMapSize(width: 0, height: 0)))
        }
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect.insetBy(dx: -rect.width * 0.25, dy: -rect.height * 0.25)
        options.size = size
        options.pointOfInterestFilter = .excludingAll

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let image = UIGraphicsImageRenderer(size: size).image { context in
            snapshot.image.draw(at: .zero)
            let path = UIBezierPath()
            for (index, coordinate) in coordinates.enumerated() {
                let point = snapshot.point(for: coordinate)
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.lineWidth = 4
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            UIColor.systemBlue.setStroke()
            path.stroke()

            let start = snapshot.point(for: coordinates[0])
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: start.x - 7, y: start.y - 7, width: 14, height: 14)).fill()
            UIColor.systemGreen.setFill()
            UIBezierPath(ovalIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)).fill()
        }
        return image.pngData()
    }
}
