import { DEFAULTS } from "./config.js";
import { fetchRoutes, type TrailRouterRoute } from "./trailrouter.js";
import { mulberry32 } from "./variation.js";

/** `[lon, lat]`. */
export type LonLat = [number, number];

const EARTH_RADIUS_M = 6_371_008.8;
const rad = (deg: number): number => (deg * Math.PI) / 180;
const deg = (radians: number): number => (radians * 180) / Math.PI;

/** Degrees wrapped into `[0, 360)`. */
export function normalizeHeading(degrees: number): number {
  return ((degrees % 360) + 360) % 360;
}

/** Smallest absolute difference between two bearings, in degrees (`0`–`180`). */
export function angleDifference(a: number, b: number): number {
  const d = Math.abs(normalizeHeading(a) - normalizeHeading(b));
  return d > 180 ? 360 - d : d;
}

/** Great-circle distance in metres. */
export function haversine(a: LonLat, b: LonLat): number {
  const dLat = rad(b[1] - a[1]);
  const dLon = rad(b[0] - a[0]);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a[1])) * Math.cos(rad(b[1])) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Initial bearing from `a` to `b` in degrees, `0` = north, clockwise. */
export function bearing(a: LonLat, b: LonLat): number {
  const dLon = rad(b[0] - a[0]);
  const y = Math.sin(dLon) * Math.cos(rad(b[1]));
  const x =
    Math.cos(rad(a[1])) * Math.sin(rad(b[1])) -
    Math.sin(rad(a[1])) * Math.cos(rad(b[1])) * Math.cos(dLon);
  return normalizeHeading(deg(Math.atan2(y, x)));
}

/** The point `distanceM` from `from` along `bearingDeg`. */
export function destination(
  from: LonLat,
  bearingDeg: number,
  distanceM: number,
): LonLat {
  const angular = distanceM / EARTH_RADIUS_M;
  const theta = rad(bearingDeg);
  const lat1 = rad(from[1]);
  const lon1 = rad(from[0]);
  const lat2 = Math.asin(
    Math.sin(lat1) * Math.cos(angular) +
      Math.cos(lat1) * Math.sin(angular) * Math.cos(theta),
  );
  const lon2 =
    lon1 +
    Math.atan2(
      Math.sin(theta) * Math.sin(angular) * Math.cos(lat1),
      Math.cos(angular) - Math.sin(lat1) * Math.sin(lat2),
    );
  return [((deg(lon2) + 540) % 360) - 180, deg(lat2)];
}

/** Length in metres of the polyline through `points`. */
export function pathLength(points: LonLat[]): number {
  let total = 0;
  for (let i = 1; i < points.length; i++) {
    total += haversine(points[i - 1]!, points[i]!);
  }
  return total;
}

/** Shortest distance in metres from `pin` to the polyline `line`. */
export function closestApproach(
  line: readonly { 0: number; 1: number }[],
  pin: LonLat,
): number {
  const cosLat = Math.cos(rad(pin[1]));
  const metresPerDegree = rad(1) * EARTH_RADIUS_M;
  const local = (p: { 0: number; 1: number }): [number, number] => [
    (p[0] - pin[0]) * metresPerDegree * cosLat,
    (p[1] - pin[1]) * metresPerDegree,
  ];
  let best = Infinity;
  for (let i = 0; i < line.length; i++) {
    const [ax, ay] = local(line[i]!);
    if (i === 0) {
      best = Math.min(best, Math.hypot(ax, ay));
      continue;
    }
    const [bx, by] = local(line[i - 1]!);
    const dx = ax - bx;
    const dy = ay - by;
    const len2 = dx * dx + dy * dy;
    const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, -(bx * dx + by * dy) / len2));
    best = Math.min(best, Math.hypot(bx + t * dx, by + t * dy));
  }
  return best;
}

/** The request's `waypoints` / `heading` were unusable. */
export class GuidanceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GuidanceError";
  }
}

export interface Guidance {
  waypoints: LonLat[];
  /** Normalised to `[0, 360)`; `null` when absent. */
  heading: number | null;
}

/** Checks the pins and heading against the limits and returns them in canonical form. */
export function validateGuidance(
  start: LonLat,
  targetMeters: number,
  waypoints: unknown,
  heading: unknown,
): Guidance {
  const cfg = DEFAULTS.guided;
  const pins: LonLat[] = [];
  if (waypoints !== undefined) {
    if (!Array.isArray(waypoints)) {
      throw new GuidanceError("`waypoints` must be an array of `[lon, lat]`");
    }
    if (waypoints.length > cfg.maxWaypoints) {
      throw new GuidanceError(`\`waypoints\` accepts at most ${cfg.maxWaypoints} points`);
    }
    for (const point of waypoints) {
      const ok =
        Array.isArray(point) &&
        point.length === 2 &&
        point.every((n) => typeof n === "number" && Number.isFinite(n)) &&
        Math.abs(point[0]) <= 180 &&
        Math.abs(point[1]) <= 90;
      if (!ok) {
        throw new GuidanceError(
          "Each waypoint must be a finite `[lon, lat]` (lon -180 to 180, lat -90 to 90)",
        );
      }
      pins.push([point[0], point[1]]);
    }
  }

  const maxRadius = targetMeters * cfg.pinRadiusFactor;
  for (const pin of pins) {
    const distance = haversine(start, pin);
    if (distance > maxRadius) {
      throw new GuidanceError(
        `A waypoint is ${(distance / 1000).toFixed(1)} km from the start; ` +
          `at most ${(maxRadius / 1000).toFixed(1)} km for a ${(targetMeters / 1000).toFixed(1)} km route`,
      );
    }
  }

  let normalized: number | null = null;
  if (heading !== undefined && heading !== null) {
    if (typeof heading !== "number" || !Number.isFinite(heading) || heading < 0 || heading > 360) {
      throw new GuidanceError("`heading` must be a number of degrees from 0 to 360");
    }
    normalized = normalizeHeading(heading);
  }
  return { waypoints: pins, heading: normalized };
}

/** Keeps a seeded stream separate from the ones in `variation.ts`. */
const GUIDED_SALT = 0x2c1b3c6d;

/**
 * A family of anchor layouts for one request, indexed by a single scalar `size` in metres: the bulge
 * offset for pins, the anchor radius for a heading. A larger size never gives a shorter perimeter.
 */
export interface Shape {
  kind: "pins" | "heading";
  /** Ordered points between the start and the finish for `size`. */
  anchors(size: number): LonLat[];
  minSize: number;
  maxSize: number;
  /** The first size worth requesting. */
  probeSize: number;
}

const closedLength = (start: LonLat, anchors: LonLat[]): number =>
  pathLength([start, ...anchors, start]);

/** The size whose straight-line perimeter is `perimeter`, clamped to the shape's range. */
export function sizeForPerimeter(
  shape: Shape,
  start: LonLat,
  perimeter: number,
): number {
  let lo = shape.minSize;
  let hi = shape.maxSize;
  if (closedLength(start, shape.anchors(lo)) >= perimeter) return lo;
  if (closedLength(start, shape.anchors(hi)) <= perimeter) return hi;
  for (let i = 0; i < 40; i++) {
    const mid = (lo + hi) / 2;
    if (closedLength(start, shape.anchors(mid)) < perimeter) lo = mid;
    else hi = mid;
  }
  return (lo + hi) / 2;
}

function permutations<T>(items: T[]): T[][] {
  if (items.length <= 1) return [items];
  return items.flatMap((item, i) =>
    permutations([...items.slice(0, i), ...items.slice(i + 1)]).map((rest) => [item, ...rest]),
  );
}

/**
 * The pins in a visiting order: the shortest tour from `start`, except that among tours within 5%
 * of the shortest one a `heading` prefers the tour whose first pin lies closest to it.
 */
export function orderPins(
  start: LonLat,
  pins: LonLat[],
  heading: number | null,
): LonLat[] {
  if (pins.length < 2) return pins;
  const tours = permutations(pins).map((tour) => ({
    tour,
    length: closedLength(start, tour),
  }));
  const shortest = Math.min(...tours.map((t) => t.length));
  const candidates = tours.filter((t) => t.length <= shortest * 1.05);
  const score = (t: { tour: LonLat[]; length: number }): number =>
    heading === null ? t.length : angleDifference(bearing(start, t.tour[0]!), heading);
  return candidates.sort((a, b) => score(a) - score(b) || a.length - b.length)[0]!.tour;
}

/** The tour `start`, `pins`, `start`, with a lateral "bulge" anchor on its longest leg that `size` moves outward. */
function pinShape(
  start: LonLat,
  pins: LonLat[],
  heading: number | null,
  targetMeters: number,
  variant: number,
): Shape {
  const ordered = orderPins(start, pins, heading);
  const path = [start, ...ordered, start];

  let leg = 0;
  for (let i = 1; i < path.length - 1; i++) {
    if (haversine(path[i]!, path[i + 1]!) > haversine(path[leg]!, path[leg + 1]!)) leg = i;
  }
  const from = path[leg]!;
  const to = path[leg + 1]!;
  const legLength = haversine(from, to);
  const legBearing = bearing(from, to);

  const rand = mulberry32(variant ^ GUIDED_SALT);
  const along = variant > 0 ? 0.35 + rand() * 0.3 : 0.5;
  const base = destination(from, legBearing, legLength * along);
  const sides = [legBearing + 90, legBearing - 90];
  const probe = 0.3 * legLength;
  const reach = (side: number): LonLat => destination(base, side, probe);

  let side: number;
  if (heading !== null) {
    side = sides.sort(
      (a, b) =>
        angleDifference(bearing(start, reach(a)), heading) -
        angleDifference(bearing(start, reach(b)), heading),
    )[0]!;
  } else {
    const centre: LonLat = [
      [start, ...ordered].reduce((sum, p) => sum + p[0], 0) / (ordered.length + 1),
      [start, ...ordered].reduce((sum, p) => sum + p[1], 0) / (ordered.length + 1),
    ];
    const [first, second] = sides as [number, number];
    const gap = haversine(reach(first), centre) - haversine(reach(second), centre);
    // A single pin has no interior, so either side makes a loop; the seed picks.
    side = Math.abs(gap) > 1 ? (gap > 0 ? first : second) : rand() < 0.5 || variant === 0 ? first : second;
  }

  const minSize = ordered.length < 2 ? 0.15 * legLength : 0;
  return {
    kind: "pins",
    anchors: (size) => {
      if (size < 1) return ordered;
      const bulge = destination(base, side, size);
      return [...ordered.slice(0, leg), bulge, ...ordered.slice(leg)];
    },
    minSize,
    maxSize: Math.max(targetMeters / 2, minSize),
    probeSize: 0,
  };
}

/** A triangle loop whose two anchors sit at `heading` ± a spread from `start`, radius `size`. */
function headingShape(
  start: LonLat,
  heading: number,
  targetMeters: number,
  variant: number,
): Shape {
  const rand = mulberry32(variant ^ GUIDED_SALT);
  const spread = DEFAULTS.guided.headingSpreadDegrees + (variant > 0 ? (rand() - 0.5) * 10 : 0);
  const centre = heading + (variant > 0 ? (rand() - 0.5) * 20 : 0);
  const shape: Shape = {
    kind: "heading",
    anchors: (size) => [
      destination(start, centre - spread, size),
      destination(start, centre + spread, size),
    ],
    minSize: 50,
    maxSize: targetMeters,
    probeSize: 0,
  };
  shape.probeSize = sizeForPerimeter(
    shape,
    start,
    targetMeters / DEFAULTS.guided.assumedRouteFactor,
  );
  return shape;
}

/**
 * The anchor layout for `guidance`. Pins are always visited; a `heading` decides the side of the
 * bulge and the visiting order, or, alone, the direction of a triangle loop. A single pin still gets a
 * bulge so the route is a loop, not an out-and-back.
 */
export function planShape(
  start: LonLat,
  targetMeters: number,
  guidance: Guidance,
  variant = 0,
): Shape {
  if (guidance.waypoints.length > 0) {
    const shape = pinShape(start, guidance.waypoints, guidance.heading, targetMeters, variant);
    if (shape.minSize > 0) {
      shape.probeSize = sizeForPerimeter(
        shape,
        start,
        targetMeters / DEFAULTS.guided.assumedRouteFactor,
      );
    }
    return shape;
  }
  return headingShape(start, guidance.heading ?? 0, targetMeters, variant);
}

export interface GuidedInput {
  start: LonLat;
  targetMeters: number;
  guidance: Guidance;
  hillsPreference: number;
  greenPreference: number;
  variant?: number;
}

export interface GuidedResult {
  route: TrailRouterRoute;
  /** Trail Router requests issued. */
  requests: number;
  warnings: string[];
}

interface Attempt {
  size: number;
  route: TrailRouterRoute;
}

/** Size multipliers around the estimate for each round after the probe. */
const ROUND_SCALES = [
  [0.85, 1, 1.15],
  [0.92, 1, 1.08],
] as const;

/**
 * Routes through the pins (or toward the heading) and tunes the anchor size until the length is
 * near the target: one probe request, then up to two rounds of up to three parallel requests, at
 * most `DEFAULTS.guided.maxRequests` in all, inside `timeBudgetMs`.
 */
export async function generateGuided(
  input: GuidedInput,
  fetchImpl?: typeof fetch,
): Promise<GuidedResult> {
  const cfg = DEFAULTS.guided;
  const { start, targetMeters, guidance } = input;
  const shape = planShape(start, targetMeters, guidance, input.variant ?? 0);
  const startedAt = Date.now();
  const attempts: Attempt[] = [];
  let requests = 0;
  let firstError: unknown;

  const relativeError = (a: Attempt): number =>
    Math.abs(a.route.distanceMeters - targetMeters) / targetMeters;
  const best = (): Attempt =>
    attempts.reduce((a, b) => (relativeError(b) < relativeError(a) ? b : a));

  const evaluate = async (sizes: number[]): Promise<void> => {
    const fresh = sizes
      .map((s) => Math.min(shape.maxSize, Math.max(shape.minSize, s)))
      .filter((s, i, all) => all.indexOf(s) === i)
      .filter((s) => attempts.every((a) => Math.abs(a.size - s) > Math.max(1, 0.005 * s)))
      .slice(0, cfg.maxRequests - requests);
    requests += fresh.length;
    const remaining = Math.max(1, cfg.timeBudgetMs - (Date.now() - startedAt));
    const settled = await Promise.allSettled(
      fresh.map(async (size) => {
        const routes = await fetchRoutes(
          {
            start,
            targetDistanceMeters: targetMeters,
            hillsPreference: input.hillsPreference,
            greenPreference: input.greenPreference,
            through: shape.anchors(size),
            signal: AbortSignal.timeout(remaining),
          },
          fetchImpl,
        );
        return { size, route: routes[0]! };
      }),
    );
    for (const result of settled) {
      if (result.status === "fulfilled") attempts.push(result.value);
      else firstError ??= result.reason;
    }
  };

  /**
   * The size that should hit the target: interpolated between the attempts either side of it, else
   * scaled from the measured route-to-anchor length ratio of the closest attempt.
   */
  const nextSize = (): number => {
    const below = attempts
      .filter((a) => a.route.distanceMeters < targetMeters)
      .sort((a, b) => b.route.distanceMeters - a.route.distanceMeters)[0];
    const above = attempts
      .filter((a) => a.route.distanceMeters > targetMeters)
      .sort((a, b) => a.route.distanceMeters - b.route.distanceMeters)[0];
    if (below && above) {
      const t =
        (targetMeters - below.route.distanceMeters) /
        (above.route.distanceMeters - below.route.distanceMeters);
      return below.size + t * (above.size - below.size);
    }
    const ref = best();
    const factor = ref.route.distanceMeters / closedLength(start, shape.anchors(ref.size));
    const size = sizeForPerimeter(shape, start, targetMeters / factor);
    return ref.size < 1 ? size : Math.min(1.4 * ref.size, Math.max(0.7 * ref.size, size));
  };

  await evaluate([shape.probeSize]);
  for (const scales of ROUND_SCALES) {
    if (attempts.length === 0) break;
    if (relativeError(best()) <= cfg.goodEnough) break;
    if (requests >= cfg.maxRequests || Date.now() - startedAt > cfg.timeBudgetMs / 2) break;
    const size = nextSize();
    const before = attempts.length;
    await evaluate(scales.map((s) => size * s));
    if (attempts.length === before) break;
  }
  if (attempts.length === 0) throw firstError;

  const chosen = best();
  const warnings: string[] = [];
  const km = (m: number): string => (m / 1000).toFixed(1);
  if (relativeError(chosen) > cfg.tolerance) {
    warnings.push(
      guidance.waypoints.length > 0
        ? `Your pins make this route ${km(chosen.route.distanceMeters)} km against a ${km(targetMeters)} km target`
        : `Could not reach the ${km(targetMeters)} km target; this route is ${km(chosen.route.distanceMeters)} km`,
    );
  }
  const missed = guidance.waypoints.filter(
    (pin) => closestApproach(chosen.route.coordinates, pin) > cfg.pinMissMeters,
  ).length;
  if (missed > 0) {
    warnings.push(
      `Trail Router's route passes more than ${cfg.pinMissMeters} m from ${missed} of your pins`,
    );
  }
  return { route: chosen.route, requests, warnings };
}
