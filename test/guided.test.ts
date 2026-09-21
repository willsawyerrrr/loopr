import { describe, expect, it, vi } from "vitest";
import {
  angleDifference,
  bearing,
  closestApproach,
  destination,
  generateGuided,
  haversine,
  normalizeHeading,
  orderPins,
  pathLength,
  planShape,
  validateGuidance,
  GuidanceError,
  type LonLat,
} from "../src/guided.js";

const START: LonLat = [151.2093, -33.8688];

/** A router whose route length is the anchor polyline's length times `factor`. */
function fakeRouter(factor = 1.25) {
  const calls: { points: LonLat[]; roundtrip: string | null }[] = [];
  const impl = vi.fn(async (url: string | URL | Request): Promise<Response> => {
    const params = new URL(String(url)).searchParams;
    const points = params
      .get("coordinates")!
      .split("|")
      .map((pair) => pair.split(",").map(Number) as LonLat);
    calls.push({ points, roundtrip: params.get("roundtrip") });
    const distance = pathLength(points) * factor;
    return new Response(
      JSON.stringify({
        routes: [
          {
            distance,
            geometry: { coordinates: points },
            ascent: 10,
            descent: 10,
            weight: distance,
            greenScore: 0.2,
          },
        ],
      }),
    );
  });
  return { impl: impl as unknown as typeof fetch, calls, mock: impl };
}

const input = (
  targetMeters: number,
  waypoints: LonLat[],
  heading: number | null,
  variant = 0,
) => ({
  start: START,
  targetMeters,
  guidance: { waypoints, heading },
  hillsPreference: 0,
  greenPreference: 0,
  variant,
});

describe("geometry", () => {
  it("haversine matches a known distance", () => {
    expect(haversine([0, 0], [0, 1])).toBeCloseTo(111_195, -2);
    expect(haversine(START, START)).toBe(0);
  });

  it("destination and bearing invert each other", () => {
    for (const b of [0, 45, 90, 180, 270, 359]) {
      const p = destination(START, b, 2000);
      expect(haversine(START, p)).toBeCloseTo(2000, 0);
      expect(angleDifference(bearing(START, p), b)).toBeLessThan(0.05);
    }
  });

  it("bearing uses 0 = north, clockwise", () => {
    expect(bearing([0, 0], [0, 1])).toBeCloseTo(0);
    expect(bearing([0, 0], [1, 0])).toBeCloseTo(90);
    expect(bearing([0, 0], [0, -1])).toBeCloseTo(180);
    expect(bearing([0, 0], [-1, 0])).toBeCloseTo(270);
  });

  it("normalizes headings and angle differences", () => {
    expect(normalizeHeading(360)).toBe(0);
    expect(normalizeHeading(-90)).toBe(270);
    expect(angleDifference(350, 10)).toBe(20);
  });

  it("closestApproach measures to segments, not just vertices", () => {
    const line: LonLat[] = [
      [0, 0],
      [0.01, 0],
    ];
    const pin: LonLat = [0.005, 0.0009];
    expect(closestApproach(line, pin)).toBeCloseTo(100, -1);
  });
});

describe("validateGuidance", () => {
  const ok = (w: unknown, h?: unknown) => validateGuidance(START, 5000, w, h);

  it("accepts pins and a heading, normalising 360 to 0", () => {
    const pin = destination(START, 45, 1000);
    expect(ok([pin], 360)).toEqual({ waypoints: [pin], heading: 0 });
    expect(ok(undefined, undefined)).toEqual({ waypoints: [], heading: null });
  });

  it("rejects more than 3 waypoints", () => {
    const pin = destination(START, 45, 500);
    expect(() => ok([pin, pin, pin, pin])).toThrow(GuidanceError);
  });

  it("rejects malformed and out-of-range waypoints", () => {
    for (const bad of [
      "x",
      [[1]],
      [[1, 2, 3]],
      [[NaN, 1]],
      [[Infinity, 1]],
      [["1", "2"]],
      [[181, 0]],
      [[0, 91]],
    ]) {
      expect(() => ok(bad)).toThrow(GuidanceError);
    }
  });

  it("rejects a pin further than 0.75 x the target from the start", () => {
    expect(() => ok([destination(START, 0, 3700)])).not.toThrow();
    expect(() => ok([destination(START, 0, 3800)])).toThrow(/at most 3\.8 km/);
  });

  it("rejects an invalid heading", () => {
    for (const bad of [-1, 361, NaN, "90", Infinity]) {
      expect(() => ok(undefined, bad)).toThrow(/heading/);
    }
  });
});

describe("planning", () => {
  it("orders pins by the shortest tour, not crossing the square", () => {
    const north = destination(START, 0, 1000);
    const east = destination(START, 90, 1000);
    const corner: LonLat = [east[0], north[1]];
    const tour = orderPins(START, [east, north, corner], null);
    expect(tour[1]).toEqual(corner);
  });

  it("a heading picks the direction of near-equal tours", () => {
    const a = destination(START, 0, 1000);
    const b = destination(START, 90, 1000);
    expect(orderPins(START, [a, b], 0)[0]).toEqual(a);
    expect(orderPins(START, [a, b], 90)[0]).toEqual(b);
  });

  it("a single pin always gets a bulge, so the tour is a loop", () => {
    const pin = destination(START, 45, 1000);
    const shape = planShape(START, 5000, { waypoints: [pin], heading: null });
    const anchors = shape.anchors(shape.minSize);
    expect(anchors).toHaveLength(2);
    expect(anchors).toContainEqual(pin);
    const bulge = anchors.find((p) => p !== pin)!;
    expect(closestApproach([START, pin], bulge)).toBeGreaterThan(100);
  });

  it("bulges toward the heading's side", () => {
    const pin = destination(START, 0, 1500);
    for (const heading of [90, 270]) {
      const shape = planShape(START, 8000, { waypoints: [pin], heading });
      const bulge = shape.anchors(1000).find((p) => p !== pin)!;
      expect(angleDifference(bearing(START, bulge), heading)).toBeLessThan(90);
    }
  });

  it("pins alone need no bulge when their tour is long enough", () => {
    const pins = [destination(START, 45, 1200), destination(START, 135, 1200)];
    const shape = planShape(START, 4000, { waypoints: pins, heading: null });
    expect(shape.anchors(shape.probeSize)).toHaveLength(2);
    expect(shape.anchors(800)).toHaveLength(3);
  });

  it("a heading alone is a triangle spanning the heading from the start", () => {
    const shape = planShape(START, 5000, { waypoints: [], heading: 90 });
    const [a, b] = shape.anchors(1000);
    expect(haversine(START, a!)).toBeCloseTo(1000, 0);
    expect(bearing(START, a!)).toBeCloseTo(55, 0);
    expect(bearing(START, b!)).toBeCloseTo(125, 0);
  });

  it("a variant moves the anchors; the same variant repeats", () => {
    const g = { waypoints: [], heading: 90 };
    const plan = (v: number) => planShape(START, 5000, g, v).anchors(1000);
    expect(plan(3)).toEqual(plan(3));
    expect(plan(3)).not.toEqual(plan(0));
    expect(plan(3)).not.toEqual(plan(4));
  });
});

describe("generateGuided", () => {
  const within = (distance: number, target: number) => Math.abs(distance - target) / target;

  it("heading only converges within tolerance and the request cap", async () => {
    for (const factor of [1.1, 1.25, 1.6]) {
      const { impl } = fakeRouter(factor);
      const r = await generateGuided(input(5000, [], 90), impl);
      expect(within(r.route.distanceMeters, 5000)).toBeLessThanOrEqual(0.07);
      expect(r.requests).toBeLessThanOrEqual(8);
      expect(r.warnings).toEqual([]);
    }
  });

  it("uses point-to-point requests that start and end at the start", async () => {
    const { impl, calls } = fakeRouter();
    await generateGuided(input(5000, [], 90), impl);
    for (const c of calls) {
      expect(c.roundtrip).toBe("false");
      expect(c.points[0]).toEqual(START);
      expect(c.points.at(-1)).toEqual(START);
    }
  });

  it("a single pin converges and the route passes through it", async () => {
    const pin = destination(START, 45, 1000);
    const { impl, calls } = fakeRouter();
    const r = await generateGuided(input(5000, [pin], null), impl);
    expect(within(r.route.distanceMeters, 5000)).toBeLessThanOrEqual(0.07);
    expect(closestApproach(r.route.coordinates, pin)).toBeLessThan(1);
    expect(calls[0]!.points.length).toBeGreaterThanOrEqual(4);
  });

  it("two pins that need padding converge", async () => {
    const pins = [destination(START, 30, 900), destination(START, 150, 900)];
    const { impl } = fakeRouter();
    const r = await generateGuided(input(9000, pins, null), impl);
    expect(within(r.route.distanceMeters, 9000)).toBeLessThanOrEqual(0.07);
    expect(r.requests).toBeLessThanOrEqual(8);
    for (const pin of pins) expect(closestApproach(r.route.coordinates, pin)).toBeLessThan(1);
  });

  it("pins and a heading converge, with pins still on the route", async () => {
    const pins = [destination(START, 20, 1200), destination(START, 80, 1400)];
    const { impl } = fakeRouter();
    const r = await generateGuided(input(7000, pins, 45), impl);
    expect(within(r.route.distanceMeters, 7000)).toBeLessThanOrEqual(0.07);
    for (const pin of pins) expect(closestApproach(r.route.coordinates, pin)).toBeLessThan(1);
  });

  it("stops after one request when the pins already fit", async () => {
    const pins = [destination(START, 45, 1000), destination(START, 135, 1000)];
    const tour = pathLength([START, ...pins, START]) * 1.25;
    const { impl } = fakeRouter();
    const r = await generateGuided(input(tour, pins, null), impl);
    expect(r.requests).toBe(1);
  });

  it("returns the pins' route with a warning when they force a length off target", async () => {
    const pins = [destination(START, 45, 2500), destination(START, 135, 2500)];
    const { impl } = fakeRouter();
    const r = await generateGuided(input(6000, pins, null), impl);
    expect(r.route.distanceMeters).toBeGreaterThan(6000 * 1.07);
    expect(r.warnings).toHaveLength(1);
    expect(r.warnings[0]).toMatch(/Your pins make this route \d+\.\d km against a 6\.0 km target/);
    expect(r.requests).toBeLessThanOrEqual(8);
  });

  it("warns when the router's route misses a pin", async () => {
    const pin = destination(START, 45, 1000);
    const impl = vi.fn(async () =>
      new Response(
        JSON.stringify({
          routes: [
            {
              distance: 5000,
              geometry: { coordinates: [START, destination(START, 200, 1500), START] },
              ascent: 0,
              descent: 0,
              weight: 1,
            },
          ],
        }),
      ),
    ) as unknown as typeof fetch;
    const r = await generateGuided(input(5000, [pin], null), impl);
    expect(r.warnings.join()).toMatch(/passes more than 100 m from 1 of your pins/);
  });

  it("tolerates failures in a parallel batch and throws if every request fails", async () => {
    let n = 0;
    const { impl: ok } = fakeRouter();
    const flaky = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      n++;
      if (n === 3) return new Response("boom", { status: 500 });
      return (ok as typeof fetch)(url, init);
    }) as unknown as typeof fetch;
    const r = await generateGuided(input(5000, [], 90), flaky);
    expect(r.route.distanceMeters).toBeGreaterThan(0);

    const dead = vi.fn(async () => new Response("no", { status: 500 })) as unknown as typeof fetch;
    await expect(generateGuided(input(5000, [], 90), dead)).rejects.toThrow(/Trail Router/);
  });

  it("never exceeds the request cap even when the router is erratic", async () => {
    const calls = { n: 0 };
    const erratic = vi.fn(async (url: string | URL | Request) => {
      calls.n++;
      const points = new URL(String(url)).searchParams.get("coordinates")!.split("|");
      return new Response(
        JSON.stringify({
          routes: [
            {
              distance: 1000 + ((calls.n * 7919) % 9000),
              geometry: { coordinates: points.map((p) => p.split(",").map(Number)) },
              ascent: 0,
              descent: 0,
              weight: 1,
            },
          ],
        }),
      );
    }) as unknown as typeof fetch;
    const r = await generateGuided(input(5000, [], 0), erratic);
    expect(calls.n).toBeLessThanOrEqual(8);
    expect(r.requests).toBe(calls.n);
  });

  it("the same variant repeats and a different one gives a different loop", async () => {
    const run = async (v: number) =>
      (await generateGuided(input(5000, [], 90, v), fakeRouter().impl)).route.coordinates;
    expect(await run(5)).toEqual(await run(5));
    expect(await run(5)).not.toEqual(await run(6));
  });
});
