import { DEFAULTS } from "./config.js";
import { pickBest, type TrailRouterRoute } from "./trailrouter.js";

const METERS_PER_DEGREE = 111_320;

/** Deterministic PRNG returning floats in `[0, 1)` (mulberry32). */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Independent streams per purpose so the offset and the pick don't correlate. */
const NUDGE_SALT = 0x51ed270b;
const CHOICE_SALT = 0x9e3779b9;

/** `start` moved by a seeded offset (random bearing, radius within `DEFAULTS.variantNudgeMeters`), as `[lon, lat]`. */
export function nudgeStart(
  start: [number, number],
  variant: number,
): [number, number] {
  const rand = mulberry32(variant ^ NUDGE_SALT);
  const { min, max } = DEFAULTS.variantNudgeMeters;
  const bearing = rand() * 2 * Math.PI;
  const radius = min + rand() * (max - min);
  const dLat = (radius * Math.cos(bearing)) / METERS_PER_DEGREE;
  const dLon =
    (radius * Math.sin(bearing)) /
    (METERS_PER_DEGREE * Math.cos((start[1] * Math.PI) / 180));
  return [start[0] + dLon, start[1] + dLat];
}

/**
 * The closest-to-target candidate when `variant` is `0`. Otherwise a seeded pick among the
 * candidates within `DEFAULTS.variantTolerance` of the target, falling back to the closest when none qualify.
 */
export function chooseCandidate(
  routes: TrailRouterRoute[],
  targetMeters: number,
  variant: number,
): TrailRouterRoute {
  if (variant <= 0) return pickBest(routes, targetMeters);
  const eligible = routes
    .filter(
      (r) =>
        Math.abs(r.distanceMeters - targetMeters) <=
        targetMeters * DEFAULTS.variantTolerance,
    )
    .sort((a, b) => a.distanceMeters - b.distanceMeters || a.weight - b.weight);
  if (eligible.length === 0) return pickBest(routes, targetMeters);
  const rand = mulberry32(variant ^ CHOICE_SALT);
  return eligible[Math.floor(rand() * eligible.length)]!;
}
