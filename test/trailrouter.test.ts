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
      geometry: { type: "LineString", coordinates: [[-0.1278, 51.5074], [-0.12, 51.51]] },
      score: 0.71,
      greenScore: 0.6,
      hillsScore: 0.5,
      distanceScore: 0.9,
      repetitionScore: 0.95,
    },
    {
      distance: 3210,
      geometry: { type: "LineString", coordinates: [[-0.1278, 51.5074], [-0.13, 51.5]] },
      score: 0.88,
      hillsScore: 0.8,
      distanceScore: 0.99,
      overriddenParameters: { target_distance: 3200 },
    },
  ],
};

function mockFetch(body: unknown, init: { ok?: boolean; status?: number } = {}) {
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
  it("parses routes, defaults missing scores, sorts best-first", async () => {
    const routes = await fetchRoutes(
      QUERY,
      mockFetch(SAMPLE_RESPONSE) as unknown as typeof fetch,
    );
    expect(routes).toHaveLength(2);
    expect(routes[0]!.score).toBe(0.88);
    expect(routes[0]!.greenScore).toBe(0); // missing → default
    expect(routes[0]!.overriddenParameters).toEqual({ target_distance: 3200 });
    expect(routes[0]!.coordinates[0]).toEqual([-0.1278, 51.5074]);
  });

  it("throws on a non-200 response with a body snippet", async () => {
    const fetchImpl = mockFetch("upstream boom", { ok: false, status: 503 });
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
    const fetchImpl = mockFetch({ routes: [{ score: 0.9, geometry: { coordinates: [] } }] });
    await expect(
      fetchRoutes(QUERY, fetchImpl as unknown as typeof fetch),
    ).rejects.toBeInstanceOf(TrailRouterError);
  });
});

describe("pickBest", () => {
  const routes: TrailRouterRoute[] = [
    { distanceMeters: 1, coordinates: [[0, 0]], score: 0.8, hillsScore: 0, greenScore: 0, distanceScore: 0.5, repetitionScore: 0 },
    { distanceMeters: 1, coordinates: [[0, 0]], score: 0.8, hillsScore: 0, greenScore: 0, distanceScore: 0.9, repetitionScore: 0 },
    { distanceMeters: 1, coordinates: [[0, 0]], score: 0.6, hillsScore: 0, greenScore: 0, distanceScore: 1, repetitionScore: 0 },
  ];

  it("takes the max score, tie-broken by distanceScore", () => {
    expect(pickBest(routes).distanceScore).toBe(0.9);
  });

  it("throws on an empty list", () => {
    expect(() => pickBest([])).toThrow(TrailRouterError);
  });
});
