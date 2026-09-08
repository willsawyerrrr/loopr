import { gunzipSync, gzipSync } from "node:zlib";
import type { RouteResult } from "./route.js";

const LEAFLET_VERSION = "1.9.4";

export interface PreviewData {
  name: string;
  /** `[lat, lon]` pairs (Leaflet order). */
  latlngs: [number, number][];
  target: number;
  route: RouteResult["route"];
  warnings: string[];
}

/** Everything the map page needs, from a generated route. */
export function previewData(result: RouteResult, name: string): PreviewData {
  return {
    name,
    latlngs: result.coordinates.map(([lon, lat]) => [lat, lon]),
    target: result.targetDistanceKm,
    route: result.route,
    warnings: result.warnings,
  };
}

/** Pack a PreviewData into a URL-safe token (gzipped JSON, base64url). */
export function encodePreview(d: PreviewData): string {
  return gzipSync(Buffer.from(JSON.stringify(d), "utf8")).toString("base64url");
}

/** Inverse of `encodePreview`. Throws on a malformed token. */
export function decodePreview(token: string): PreviewData {
  return JSON.parse(
    gunzipSync(Buffer.from(token, "base64url")).toString("utf8"),
  ) as PreviewData;
}

/**
 * A standalone HTML page that draws the route on an OpenStreetMap base layer
 * with a summary panel — served for `format=html` and for the `previewUrl`
 * token so a route can be eyeballed in a browser before importing it.
 */
export function renderMapPage(d: PreviewData): string {
  const json = JSON.stringify(d).replace(/</g, "\\u003c");

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(d.name)}</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@${LEAFLET_VERSION}/dist/leaflet.css">
<style>
  html, body { margin: 0; height: 100%; font: 14px/1.4 -apple-system, system-ui, sans-serif; }
  #map { position: absolute; inset: 0; }
  #panel {
    position: absolute; z-index: 1000; top: 12px; left: 12px; right: 12px;
    max-width: 320px; background: rgba(255,255,255,0.94); border-radius: 10px;
    padding: 12px 14px; box-shadow: 0 2px 12px rgba(0,0,0,0.18);
  }
  #panel h1 { margin: 0 0 6px; font-size: 15px; }
  #panel dl { margin: 0; display: grid; grid-template-columns: auto 1fr; gap: 2px 10px; }
  #panel dt { color: #666; }
  #panel dd { margin: 0; font-variant-numeric: tabular-nums; }
  #warn { margin: 8px 0 0; color: #9a3b00; font-size: 13px; }
  @media (prefers-color-scheme: dark) {
    #panel { background: rgba(30,30,32,0.94); color: #eee; }
    #panel dt { color: #aaa; }
    #warn { color: #ffb27a; }
  }
</style>
</head>
<body>
<div id="map"></div>
<div id="panel"><h1></h1><dl></dl><p id="warn" hidden></p></div>
<script id="d" type="application/json">${json}</script>
<script src="https://unpkg.com/leaflet@${LEAFLET_VERSION}/dist/leaflet.js"></script>
<script>
  var d = JSON.parse(document.getElementById("d").textContent);
  document.querySelector("#panel h1").textContent = d.name;
  var rows = [
    ["Target", d.target + " km"],
    ["Route", d.route.distanceKm + " km"],
    ["Hilliness", d.route.hilliness + " (" + d.route.elevationGainPerKm + " m/km)"],
    ["Climb", d.route.ascentM + " m"],
    ["Green", Math.round(d.route.greenScore * 100) + "%"],
  ];
  var dl = document.querySelector("#panel dl");
  rows.forEach(function (r) {
    var dt = document.createElement("dt"); dt.textContent = r[0];
    var dd = document.createElement("dd"); dd.textContent = r[1];
    dl.append(dt, dd);
  });
  if (d.warnings && d.warnings.length) {
    var w = document.getElementById("warn");
    w.hidden = false; w.textContent = d.warnings.join("\\n");
  }
  var map = L.map("map");
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap contributors',
  }).addTo(map);
  var line = L.polyline(d.latlngs, { color: "#e6007e", weight: 4 }).addTo(map);
  L.circleMarker(d.latlngs[0], { radius: 6, color: "#111", fillColor: "#fff", fillOpacity: 1 })
    .addTo(map).bindPopup("Start / finish");
  map.fitBounds(line.getBounds(), { padding: [30, 30] });
</script>
</body>
</html>
`;
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!,
  );
}
