function escapeXml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

/**
 * Render a GeoJSON LineString as a GPX 1.1 track.
 *
 * `coordinates` are `[lon, lat]` pairs or `[lon, lat, ele]` triples (GeoJSON
 * order); each becomes one `<trkpt lat lon>` with the order swapped. A nested
 * `<ele>` is emitted only for a tuple carrying a finite 3rd value. No `<time>`
 * is emitted.
 */
export function lineStringToGpx(
  coordinates: [number, number, number?][],
  name: string,
): string {
  const safeName = escapeXml(name);
  const points = coordinates
    .map(([lon, lat, ele]) =>
      typeof ele === "number" && Number.isFinite(ele)
        ? `      <trkpt lat="${lat}" lon="${lon}"><ele>${ele}</ele></trkpt>`
        : `      <trkpt lat="${lat}" lon="${lon}"/>`,
    )
    .join("\n");

  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="runna-router"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
     xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
  <metadata><name>${safeName}</name></metadata>
  <trk>
    <name>${safeName}</name>
    <trkseg>
${points}
    </trkseg>
  </trk>
</gpx>
`;
}
