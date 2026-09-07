import { describe, expect, it } from "vitest";
import { lineStringToGpx } from "../src/gpx.js";

const COORDS: [number, number][] = [
  [-0.1278, 51.5074],
  [-0.12, 51.51],
  [-0.1278, 51.5074],
];

describe("lineStringToGpx", () => {
  const gpx = lineStringToGpx(COORDS, "Runna route");

  it("swaps [lon, lat] into lat/lon order", () => {
    expect(gpx).toContain('<trkpt lat="51.5074" lon="-0.1278"/>');
  });

  it("emits one trkpt per coordinate", () => {
    expect(gpx.match(/<trkpt /g)).toHaveLength(3);
  });

  it("has a single track segment", () => {
    expect(gpx.match(/<trkseg>/g)).toHaveLength(1);
    expect(gpx.match(/<trk>/g)).toHaveLength(1);
  });

  it("omits elevation and time", () => {
    expect(gpx).not.toContain("<ele>");
    expect(gpx).not.toContain("<time>");
  });

  it("declares creator runna-router and GPX 1.1", () => {
    expect(gpx).toContain('version="1.1"');
    expect(gpx).toContain('creator="runna-router"');
  });

  it("XML-escapes the name", () => {
    const escaped = lineStringToGpx(COORDS, `Tom & Jerry <"loop">`);
    expect(escaped).toContain("Tom &amp; Jerry &lt;&quot;loop&quot;&gt;");
    expect(escaped).not.toMatch(/<name>Tom & /);
  });

  it("is well-formed XML (balanced tags, single root)", () => {
    expect(gpx.startsWith('<?xml version="1.0" encoding="UTF-8"?>')).toBe(true);
    expect(gpx.trimEnd().endsWith("</gpx>")).toBe(true);
    expect(gpx.match(/<gpx /g)).toHaveLength(1);
  });
});
