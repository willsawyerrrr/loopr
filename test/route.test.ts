import { afterEach, describe, expect, it, vi } from "vitest";
import { POST, GET } from "../api/route.js";
import { GET as PREVIEW } from "../api/preview.js";
import { generateRoute } from "../src/route.js";
import { decodePreview } from "../src/preview.js";
import { DEFAULT_PACES } from "../src/config.js";

const START: [number, number] = [-0.1278, 51.5074];

const ROUTER_BODY = {
  routes: [
    {
      // Far from any target used in these tests — must not be selected.
      distance: 5000,
      geometry: {
        type: "LineString",
        coordinates: [
          [-0.1278, 51.5074, 10],
          [-0.14, 51.49, 10],
          [-0.1278, 51.5074, 10],
        ],
      },
      ascent: 90,
      descent: 90,
      weight: 4000,
      greenScore: 0.1,
    },
    {
      distance: 3180,
      geometry: {
        type: "LineString",
        coordinates: [
          [-0.1278, 51.5074, 12.5],
          [-0.13, 51.5, 20],
          [-0.1278, 51.5074, 12.5],
        ],
      },
      ascent: 60,
      descent: 60,
      weight: 3200,
      greenScore: 0.4,
    },
  ],
};

function stubRouter(body: unknown, init: { status?: number } = {}) {
  const { status = 200 } = init;
  const text = typeof body === "string" ? body : JSON.stringify(body);
  const impl = vi.fn(
    (_url: string, _opts?: RequestInit): Promise<Response> =>
      Promise.resolve(new Response(text, { status })),
  );
  vi.stubGlobal("fetch", impl);
  return impl;
}

const readJson = (res: Response): Promise<any> => res.json();

function postRequest(body: unknown, query = ""): Request {
  return new Request(`https://runna-router.willsawyerrrr.dev/api/route${query}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

afterEach(() => {
  vi.unstubAllGlobals();
});

const SAMPLE_A = `Walk Run • 29m • 29m

5 mins walking warm up

4 reps of:
• 60s at a conversational pace, 30s walking
• 2 mins at a conversational pace, 60s walking

60s at a conversational pace

5 mins walking cool down`;

describe("POST /api/route — workout happy path", () => {
  it("returns gpx, filename, checksum and route metadata", async () => {
    const impl = stubRouter(ROUTER_BODY);
    const res = await POST(
      postRequest({ workout: SAMPLE_A, title: "Walk Run", date: "2026-09-13", start: START }),
    );
    expect(res.status).toBe(200);
    const json = await readJson(res);

    expect(json.gpx).toContain('<trkpt lat="51.5074" lon="-0.1278"><ele>12.5</ele></trkpt>');
    expect(json.filename).toBe("2026-09-13-walk-run-3.2km.gpx");
    expect(json.checksum.ok).toBe(true);
    // the 3180 m candidate, not the 5000 m one
    expect(json.route.distanceKm).toBe(3.18);
    expect(json.route.ascentM).toBe(60);
    expect(json.route.elevationGainPerKm).toBe(18.9);
    expect(json.route.hilliness).toBe("rolling");
    expect(json.segments.length).toBeGreaterThan(0);

    // target_distance sent to Trail Router is the parsed sum, rounded
    const sent = new URL(impl.mock.calls[0]![0]).searchParams.get("target_distance");
    expect(Number(sent)).toBeGreaterThan(3000);
    expect(Number(sent)).toBeLessThan(3400);
  });
});

describe("POST /api/route — manual override path", () => {
  it("skips parsing and uses targetDistanceKm", async () => {
    stubRouter(ROUTER_BODY);
    const res = await POST(postRequest({ targetDistanceKm: 3.2, start: START }));
    expect(res.status).toBe(200);
    const json = await readJson(res);
    expect(json.segments).toEqual([]);
    expect(json.checksum).toEqual({
      statedMinutes: null,
      statedKm: null,
      computedMinutes: 0,
      computedKm: 0,
      ok: true,
    });
    expect(json.filename).toBe("route-3.2km.gpx");
    expect(json.targetDistanceKm).toBe(3.2);
  });
});

describe("POST /api/route — error branches", () => {
  it("400 on malformed JSON", async () => {
    stubRouter(ROUTER_BODY);
    const req = new Request("https://x/api/route", { method: "POST", body: "{ not json" });
    expect((await POST(req)).status).toBe(400);
  });

  it("400 on missing start", async () => {
    stubRouter(ROUTER_BODY);
    const res = await POST(postRequest({ targetDistanceKm: 3 }));
    expect(res.status).toBe(400);
  });

  it("400 when neither workout nor targetDistanceKm", async () => {
    stubRouter(ROUTER_BODY);
    const res = await POST(postRequest({ start: START }));
    expect(res.status).toBe(400);
  });

  it("422 when the workout yields no target distance", async () => {
    stubRouter(ROUTER_BODY);
    const res = await POST(postRequest({ workout: "Rest day\n\nNothing today", start: START }));
    expect(res.status).toBe(422);
    expect((await readJson(res)).error).toMatch(/target distance/i);
  });

  it("502 when Trail Router fails", async () => {
    stubRouter("upstream down", { status: 503 });
    const res = await POST(postRequest({ targetDistanceKm: 3, start: START }));
    expect(res.status).toBe(502);
    expect((await readJson(res)).detail).toContain("upstream down");
  });
});

describe("GET /api/route — manual test endpoint", () => {
  it("maps query params to a generated route", async () => {
    stubRouter(ROUTER_BODY);
    const res = await GET(
      new Request("https://x/api/route?distanceKm=3.2&start=-0.1278,51.5074&hills=0.5"),
    );
    expect(res.status).toBe(200);
    expect((await readJson(res)).filename).toBe("route-3.2km.gpx");
  });

  it("400 without distanceKm", async () => {
    stubRouter(ROUTER_BODY);
    const res = await GET(new Request("https://x/api/route?start=-0.1278,51.5074"));
    expect(res.status).toBe(400);
  });
});

describe("generateRoute — overriddenParameters surfaced", () => {
  it("adds a warning and route.overriddenParameters", async () => {
    const impl = vi.fn(
      (_url: string, _opts?: RequestInit): Promise<Response> =>
        Promise.resolve(
          new Response(
            JSON.stringify({
              routes: [
                {
                  distance: 3000,
                  geometry: { coordinates: [[-0.1278, 51.5074], [-0.13, 51.5]] },
                  ascent: 15,
                  descent: 15,
                  weight: 2800,
                  greenScore: 0.2,
                  overriddenParameters: { target_distance: 2500 },
                },
              ],
            }),
          ),
        ),
    );
    const result = await generateRoute(
      { targetDistanceKm: 3, config: { start: START, paces: DEFAULT_PACES } },
      impl as unknown as typeof fetch,
    );
    expect(result.route.overriddenParameters).toEqual({ target_distance: 2500 });
    expect(result.warnings.some((w) => w.includes("overrode"))).toBe(true);
  });
});

describe("POST /api/route — output formats", () => {
  it("returns gpx, coordinates and previewUrl", async () => {
    stubRouter(ROUTER_BODY);
    const json = await readJson(
      await POST(postRequest({ workout: SAMPLE_A, title: "Walk Run", start: START })),
    );
    expect(json.coordinates).toEqual([
      [-0.1278, 51.5074, 12.5],
      [-0.13, 51.5, 20],
      [-0.1278, 51.5074, 12.5],
    ]);
    expect(json.gpx).toContain("<trkpt");
    // no KV store in tests → the inline-token fallback
    expect(json.previewUrl).toMatch(
      /^https:\/\/runna-router\.willsawyerrrr\.dev\/api\/preview\?r=[A-Za-z0-9_-]+$/,
    );
  });

  it("the fallback previewUrl decodes back to this exact route", async () => {
    stubRouter(ROUTER_BODY);
    const json = await readJson(
      await POST(postRequest({ workout: SAMPLE_A, title: "Walk Run", start: START })),
    );
    const token = new URL(json.previewUrl).searchParams.get("r")!;
    const data = decodePreview(token);
    expect(data.name).toBe("Walk Run");
    expect(data.route.distanceKm).toBe(json.route.distanceKm);
    // the 3180 m fixture candidate's first point, [lon,lat,ele] flipped to [lat,lon]
    expect(data.latlngs[0]).toEqual([51.5074, -0.1278]);
  });

  it("GET /api/preview renders the token map, and error pages are HTML not downloads", async () => {
    stubRouter(ROUTER_BODY);
    const json = await readJson(
      await POST(postRequest({ workout: SAMPLE_A, title: "Walk Run", start: START })),
    );
    const good = await PREVIEW(new Request(json.previewUrl));
    expect(good.status).toBe(200);
    expect(good.headers.get("Content-Type")).toBe("text/html; charset=utf-8");
    expect(await good.text()).toContain("<title>Walk Run</title>");

    const missing = await PREVIEW(new Request("https://x/api/preview"));
    expect(missing.status).toBe(400);
    expect(missing.headers.get("Content-Type")).toBe("text/html; charset=utf-8");

    const bad = await PREVIEW(new Request("https://x/api/preview?r=garbage"));
    expect(bad.status).toBe(400);
    expect(bad.headers.get("Content-Type")).toBe("text/html; charset=utf-8");

    // unknown store id → 404 HTML (store is off in tests, so any id misses)
    const gone = await PREVIEW(new Request("https://x/api/preview?id=0123456789ab"));
    expect(gone.status).toBe(404);
    expect(gone.headers.get("Content-Type")).toBe("text/html; charset=utf-8");
  });

  it("format=gpx returns the file with a download disposition", async () => {
    stubRouter(ROUTER_BODY);
    const res = await POST(
      postRequest({ targetDistanceKm: 3.2, start: START }, "?format=gpx"),
    );
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("application/gpx+xml");
    expect(res.headers.get("Content-Disposition")).toContain('filename="route-3.2km.gpx"');
    expect(await res.text()).toMatch(/^<\?xml/);
  });

  it("format=html returns a Leaflet map page with the route and summary", async () => {
    stubRouter(ROUTER_BODY);
    const res = await POST(
      postRequest(
        { workout: SAMPLE_A, title: "Walk Run", start: START },
        "?format=html",
      ),
    );
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("text/html; charset=utf-8");
    const html = await res.text();
    expect(html).toContain("<title>Walk Run</title>");
    expect(html).toContain("leaflet@1.9.4");
    expect(html).toContain("tile.openstreetmap.org");
    // [lon, lat] from the fixture, flipped to [lat, lon] for Leaflet
    expect(html).toContain("[51.5074,-0.1278");
    expect(html).toContain('"hilliness":"rolling"');
  });

  it("format also works from the POST body", async () => {
    stubRouter(ROUTER_BODY);
    const res = await POST(
      postRequest({ targetDistanceKm: 3.2, start: START, format: "gpx" }),
    );
    expect(res.headers.get("Content-Type")).toBe("application/gpx+xml");
  });

  it("GET format=html works too", async () => {
    stubRouter(ROUTER_BODY);
    const res = await GET(
      new Request("https://x/api/route?distanceKm=3.2&start=-0.1278,51.5074&format=html"),
    );
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("text/html; charset=utf-8");
  });

  it("an unknown format falls back to JSON", async () => {
    stubRouter(ROUTER_BODY);
    const res = await POST(
      postRequest({ targetDistanceKm: 3.2, start: START }, "?format=pdf"),
    );
    expect(res.headers.get("Content-Type")).toBe("application/json");
  });
});
