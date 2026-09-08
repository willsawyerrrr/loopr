import { describe, expect, it } from "vitest";
import { renderMapPage } from "../src/preview.js";
import type { RouteResult } from "../src/route.js";

const RESULT: RouteResult = {
  gpx: "<gpx/>",
  coordinates: [
    [-0.1278, 51.5074, 12.5],
    [-0.13, 51.5, 20],
    [-0.1278, 51.5074, 12.5],
  ],
  filename: "route-3.2km.gpx",
  targetDistanceKm: 3.2,
  route: {
    distanceKm: 3.18,
    ascentM: 60,
    descentM: 60,
    elevationGainPerKm: 18.9,
    hilliness: "rolling",
    greenScore: 0.4,
  },
  segments: [],
  checksum: { statedMinutes: null, computedMinutes: 0, ok: true },
  warnings: ["Trail Router overrode parameters: {\"avoidRepetition\":false}"],
};

describe("renderMapPage", () => {
  const html = renderMapPage(RESULT, "Walk Run");

  it("is a full HTML document titled with the route name", () => {
    expect(html.startsWith("<!doctype html>")).toBe(true);
    expect(html).toContain("<title>Walk Run</title>");
  });

  it("embeds the polyline as [lat, lon] pairs, elevation dropped", () => {
    expect(html).toContain("[51.5074,-0.1278],[51.5,-0.13],[51.5074,-0.1278]");
  });

  it("carries the route summary and warnings", () => {
    expect(html).toContain('"hilliness":"rolling"');
    expect(html).toContain('"target":3.2');
    expect(html).toContain("avoidRepetition");
  });

  it("loads Leaflet and OSM tiles", () => {
    expect(html).toContain("unpkg.com/leaflet@1.9.4/dist/leaflet.js");
    expect(html).toContain("tile.openstreetmap.org/{z}/{x}/{y}.png");
    expect(html).toContain("OpenStreetMap contributors");
  });

  it("escapes the name and neutralises embedded </script", () => {
    const evil = renderMapPage(RESULT, "</script><img src=x onerror=alert(1)>");
    expect(evil).not.toContain("<img src=x");
    expect(evil).toContain("&lt;/script&gt;");
  });

  it("escapes < inside the embedded JSON payload", () => {
    const withTag: RouteResult = { ...RESULT, warnings: ["<b>bad</b>"] };
    const out = renderMapPage(withTag, "x");
    expect(out).not.toContain("<b>bad</b>");
    expect(out).toContain("\\u003cb>bad\\u003c/b>");
  });
});
