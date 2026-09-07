import { describe, expect, it, vi } from "vitest";
import {
  fetchRoutes,
  pickBest,
  TrailRouterError,
  type TrailRouterQuery,
  type TrailRouterRoute,
} from "../src/trailrouter.js";

const QUERY: TrailRouterQuery = {
  start: [-0.1278, 51.5074],
  targetDistanceMeters: 3187.6,
  hillsPreference: 0,
  greenPreference: 0.5,
};

const SAMPLE_RESPONSE = {
  routes: [
    {
      distance: 3050,
      geometry: {
        type: "LineString",
        coordinates: [
          [-0.1278, 51.5074, 26.8],
          [-0.12, 51.51],
        ],
      },
      ascent: 40,
      descent: 40,
      weight: 200,
      greenScore: 0.6,
      wayTypes: { footway: 100 },
    },
    {
      distance: 3210,
      geometry: {
        type: "LineString",
        coordinates: [
          [-0.1278, 51.5074, 26.8],
          [-0.13, 51.5, 30.1],
        ],
      },
      ascent: 55,
      descent: 55,
      weight: 300,
      overriddenParameters: { avoidRepetition: false },
    },
    {
      distance: 3980,
      geometry: {
        type: "LineString",
        coordinates: [
          [-0.1278, 51.5074],
          [-0.14, 51.49],
        ],
      },
      ascent: 30,
      descent: 30,
      weight: 100,
      greenScore: 0.2,
      overriddenParameters: {},
    },
  ],
};

function mockFetch(body: unknown, init: { status?: number } = {}) {
  const { status = 200 } = init;
  const text = typeof body === "string" ? body : JSON.stringify(body);
  return vi.fn(
    (_url: string, _opts?: RequestInit): Promise<Response> =>
      Promise.resolve(new Response(text, { status })),
  );
}

describe("fetchRoutes — request construction", () => {
  it("builds the documented query string and User-Agent", async () => {
    const fetchImpl = mockFetch(SAMPLE_RESPONSE);
    await fetchRoutes(QUERY, fetchImpl as unknown as typeof fetch);

    const [url, opts] = fetchImpl.mock.calls[0]!;
    const parsed = new URL(url);
    expect(parsed.origin + parsed.pathname).toBe(
      "https://trailrouter.com/ors/experimentalroutes",
    );
    expect(parsed.searchParams.get("coordinates")).toBe("-0.1278,51.5074");
    expect(parsed.searchParams.get("roundtrip")).toBe("true");
    expect(parsed.searchParams.get("target_distance")).toBe("3188");
    expect(parsed.searchParams.get("hills_preference")).toBe("0");
    expect(parsed.searchParams.get("green_preference")).toBe("0.5");
    expect(parsed.searchParams.get("avoid_repetition")).toBe("true");
    expect(parsed.searchParams.get("avoid_unsafe_streets")).toBe("true");
    expect(parsed.searchParams.get("avoid_unlit_streets")).toBe("true");
    expect(opts?.headers).toMatchObject({
      "User-Agent": "runna-router (personal use)",
    });
  });
});

describe("fetchRoutes — defensive parse", () => {
  it("parses the real schema, preserves elevation, closest-to-target first", async () => {
    const routes = await fetchRoutes(
      QUERY,
      mockFetch(SAMPLE_RESPONSE) as unknown as typeof fetch,
    );
    expect(routes).toHaveLength(3);

    // 3210 is 22.4 m from the 3187.6 m target — the closest.
    expect(routes[0]!.distanceMeters).toBe(3210);
    expect(routes[0]!.overriddenParameters).toEqual({ avoidRepetition: false });
    expect(routes[0]!.greenScore).toBe(0); // missing → default

    expect(routes[1]!.distanceMeters).toBe(3050);
    expect(routes[1]!.coordinates[0]).toEqual([-0.1278, 51.5074, 26.8]);
    expect(routes[1]!.coordinates[1]).toEqual([-0.12, 51.51]); // no elevation
    expect(routes[1]!.wayTypes).toEqual({ footway: 100 });

    // An empty overriddenParameters object is dropped.
    expect(routes[2]!.overriddenParameters).toBeUndefined();
  });

  it("throws on a non-200 response with a body snippet", async () => {
    const fetchImpl = mockFetch("upstream boom", { status: 503 });
    await expect(
      fetchRoutes(QUERY, fetchImpl as unknown as typeof fetch),
    ).rejects.toMatchObject({ status: 503, detail: "upstream boom" });
  });

  it("throws when routes is empty", async () => {
    await expect(
      fetchRoutes(QUERY, mockFetch({ routes: [] }) as unknown as typeof fetch),
    ).rejects.toBeInstanceOf(TrailRouterError);
  });

  it("throws when no route has usable geometry", async () => {
    const fetchImpl = mockFetch({
      routes: [{ distance: 3000, geometry: { coordinates: [] } }],
    });
    await expect(
      fetchRoutes(QUERY, fetchImpl as unknown as typeof fetch),
    ).rejects.toBeInstanceOf(TrailRouterError);
  });
});

describe("pickBest", () => {
  const route = (
    distanceMeters: number,
    weight: number,
  ): TrailRouterRoute => ({
    distanceMeters,
    coordinates: [[0, 0]],
    ascentMeters: 0,
    descentMeters: 0,
    weight,
    greenScore: 0,
  });

  it("takes the candidate closest to the target distance", () => {
    const routes = [route(4600, 3700), route(5300, 3200), route(4980, 5000)];
    expect(pickBest(routes, 5000).distanceMeters).toBe(4980);
  });

  it("tie-breaks equal distance gaps on lower weight", () => {
    const routes = [route(5100, 900), route(4900, 5)];
    expect(pickBest(routes, 5000).weight).toBe(5);
  });

  it("throws on an empty list", () => {
    expect(() => pickBest([], 5000)).toThrow(TrailRouterError);
  });
});
