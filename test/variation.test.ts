import { describe, expect, it } from "vitest";
import { DEFAULTS } from "../src/config.js";
import type { TrailRouterRoute } from "../src/trailrouter.js";
import { chooseCandidate, mulberry32, nudgeStart } from "../src/variation.js";

const START: [number, number] = [151.2093, -33.8688];

function metersBetween(a: [number, number], b: [number, number]): number {
  const dLat = (b[1] - a[1]) * 111_320;
  const dLon = (b[0] - a[0]) * 111_320 * Math.cos((a[1] * Math.PI) / 180);
  return Math.hypot(dLat, dLon);
}

function route(distanceMeters: number, weight = 0): TrailRouterRoute {
  return {
    distanceMeters,
    coordinates: [[0, 0]],
    ascentMeters: 0,
    descentMeters: 0,
    weight,
    greenScore: 0,
  };
}

describe("mulberry32", () => {
  it("repeats for a seed and yields floats in [0, 1)", () => {
    const a = mulberry32(7);
    const b = mulberry32(7);
    for (let i = 0; i < 20; i++) {
      const x = a();
      expect(x).toBe(b());
      expect(x).toBeGreaterThanOrEqual(0);
      expect(x).toBeLessThan(1);
    }
  });
});

describe("nudgeStart", () => {
  it("is deterministic per variant", () => {
    expect(nudgeStart(START, 3)).toEqual(nudgeStart(START, 3));
  });

  it("gives different offsets for different variants", () => {
    const offsets = new Set(
      Array.from({ length: 10 }, (_, i) => nudgeStart(START, i + 1).join(",")),
    );
    expect(offsets.size).toBe(10);
  });

  it("stays within the configured radius", () => {
    const { min, max } = DEFAULTS.variantNudgeMeters;
    for (let v = 1; v <= 200; v++) {
      const d = metersBetween(START, nudgeStart(START, v));
      expect(d).toBeGreaterThanOrEqual(min - 0.5);
      expect(d).toBeLessThanOrEqual(max + 0.5);
    }
  });
});

describe("chooseCandidate", () => {
  const target = 5000;
  const routes = [
    route(3600),
    route(4800),
    route(5040),
    route(5200),
    route(6500),
  ];

  it("variant 0 is the closest to target", () => {
    expect(chooseCandidate(routes, target, 0).distanceMeters).toBe(5040);
  });

  it("only picks candidates within tolerance and is deterministic per variant", () => {
    const seen = new Set<number>();
    for (let v = 1; v <= 50; v++) {
      const picked = chooseCandidate(routes, target, v);
      expect(picked).toBe(chooseCandidate([...routes].reverse(), target, v));
      expect(
        Math.abs(picked.distanceMeters - target) / target,
      ).toBeLessThanOrEqual(DEFAULTS.variantTolerance);
      seen.add(picked.distanceMeters);
    }
    expect([...seen].sort()).toEqual([4800, 5040, 5200]);
  });

  it("falls back to the closest when none are within tolerance", () => {
    const far = [route(3000), route(4400), route(7000)];
    expect(chooseCandidate(far, target, 9).distanceMeters).toBe(4400);
  });
});
