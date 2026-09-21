import Foundation

/// GPX 1.1 track rendering, matching the server's `lineStringToGpx`.
public enum GPXWriter {
    public static func gpx(points: [RoutePoint], name: String) -> String {
        let safeName = escape(name)
        let body = points.map { point -> String in
            if let ele = point.elevation, ele.isFinite {
                return "      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><ele>\(ele)</ele></trkpt>"
            }
            return "      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"/>"
        }.joined(separator: "\n")

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="loopr"
                 xmlns="http://www.topografix.com/GPX/1/1"
                 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                 xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
              <metadata><name>\(safeName)</name></metadata>
              <trk>
                <name>\(safeName)</name>
                <trkseg>
            \(body)
                </trkseg>
              </trk>
            </gpx>

            """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// Reads `<trkpt>` points out of a GPX document.
public enum GPXParser {
    public static func points(in gpx: String) -> [RoutePoint] {
        guard let data = gpx.data(using: .utf8) else { return [] }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.points
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var points: [RoutePoint] = []
        private var current: RoutePoint?
        private var inElevation = false
        private var text = ""

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
            qualifiedName: String?, attributes: [String: String] = [:]
        ) {
            switch name {
            case "trkpt":
                if let lat = attributes["lat"].flatMap(Double.init),
                    let lon = attributes["lon"].flatMap(Double.init)
                {
                    current = RoutePoint(longitude: lon, latitude: lat)
                }
            case "ele":
                inElevation = current != nil
                text = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inElevation { text += string }
        }

        func parser(
            _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
            qualifiedName: String?
        ) {
            switch name {
            case "ele":
                current?.elevation = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
                inElevation = false
            case "trkpt":
                if let current { points.append(current) }
                current = nil
            default:
                break
            }
        }
    }
}
