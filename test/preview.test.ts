import { describe, expect, it } from "vitest";
import {
  decodePreview,
  encodePreview,
  previewData,
  renderMapPage,
  type PreviewData,
} from "../src/preview.js";
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
  warnings: ['Trail Router overrode parameters: {"avoidRepetition":false}'],
};

const DATA: PreviewData = previewData(RESULT, "Walk Run");

describe("previewData", () => {
  it("flips [lon, lat, ele] to [lat, lon] and drops elevation", () => {
    expect(DATA.latlngs).toEqual([
      [51.5074, -0.1278],
      [51.5, -0.13],
      [51.5074, -0.1278],
    ]);
  });

  it("carries the name, target, route metadata and warnings", () => {
    expect(DATA.name).toBe("Walk Run");
    expect(DATA.target).toBe(3.2);
    expect(DATA.route.hilliness).toBe("rolling");
    expect(DATA.warnings).toHaveLength(1);
  });
});

describe("encodePreview / decodePreview", () => {
  it("round-trips a PreviewData through a URL-safe token", () => {
    const token = encodePreview(DATA);
    expect(token).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(decodePreview(token)).toEqual(DATA);
  });

  it("keeps a ~120-point route token well under a URL length limit", () => {
    const many: PreviewData = {
      ...DATA,
      latlngs: Array.from({ length: 120 }, (_, i) => [
        51.5 + i * 0.0003,
        -0.12 - i * 0.0004,
      ]),
    };
    expect(encodePreview(many).length).toBeLessThan(3000);
  });

  it("throws on a malformed token", () => {
    expect(() => decodePreview("not-base64-gzip!!")).toThrow();
  });
});

describe("renderMapPage", () => {
  const html = renderMapPage(DATA);

  it("is a full HTML document titled with the route name", () => {
    expect(html.startsWith("<!doctype html>")).toBe(true);
    expect(html).toContain("<title>Walk Run</title>");
  });

  it("embeds the polyline as [lat, lon] pairs", () => {
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
    const evil = renderMapPage({
      ...DATA,
      name: "</script><img src=x onerror=alert(1)>",
    });
    expect(evil).not.toContain("<img src=x");
    expect(evil).toContain("&lt;/script&gt;");
  });

  it("escapes < inside the embedded JSON payload", () => {
    const out = renderMapPage({ ...DATA, warnings: ["<b>bad</b>"] });
    expect(out).not.toContain("<b>bad</b>");
    expect(out).toContain("\\u003cb>bad\\u003c/b>");
  });
});
