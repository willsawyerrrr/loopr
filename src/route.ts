import { DEFAULTS, type RouteConfig } from "./config.js";
import { fetchRoutes, type TrailRouterRoute } from "./trailrouter.js";
import { generateGuided, GuidanceError, validateGuidance, type LonLat } from "./guided.js";
import { chooseCandidate, nudgeStart } from "./variation.js";
import { lineStringToGpx } from "./gpx.js";
import { parseWorkout, type ParsedWorkout, type Segment } from "./workout.js";

/** Terrain band, from elevation gain per km (research §1): `<10` flat, `10–25` rolling, `>25` hilly. */
export type Hilliness = "flat" | "rolling" | "hilly";

function hilliness(gainPerKm: number): Hilliness {
  if (gainPerKm < 10) return "flat";
  if (gainPerKm <= 25) return "rolling";
  return "hilly";
}

export interface RouteResult {
  gpx: string;
  /** The chosen route's `[lon, lat, ele?]` points. Not part of the JSON response. */
  coordinates: [number, number, number?][];
  /** e.g. `2026-09-13-walk-run-3.2km.gpx`. */
  filename: string;
  targetDistanceKm: number;
  route: {
    distanceKm: number;
    ascentM: number;
    descentM: number;
    elevationGainPerKm: number;
    hilliness: Hilliness;
    greenScore: number;
    overriddenParameters?: Record<string, unknown>;
  };
  segments: Segment[];
  checksum: ParsedWorkout["checksum"];
  warnings: string[];
  /** The applied `variant`; `0` is the closest-to-target route. */
  variant: number;
  /** Present when `waypoints` or `heading` steered the route. */
  guided?: {
    waypoints: LonLat[];
    /** Degrees in `[0, 360)`, or `null` when only pins were given. */
    heading: number | null;
    /** Trail Router requests issued to reach the target distance. */
    requests: number;
    distanceMeters: number;
  };
}

export interface GenerateRouteInput {
  /** Raw Runna Notes text. Mutually exclusive with `targetDistanceKm`. */
  workout?: string;
  /** Manual distance override / bare-event fallback. Mutually exclusive with `workout`. */
  targetDistanceKm?: number;
  /** Used for the filename and the GPX track name. */
  title?: string;
  /** ISO date for the filename. */
  date?: string;
  /** Non-negative integer. `0` or absent picks the closest-to-target route; `> 0` picks a seeded, different one. */
  variant?: number;
  /** Up to `DEFAULTS.guided.maxWaypoints` `[lon, lat]` pins the route passes through. */
  waypoints?: LonLat[];
  /** Degrees, `0` = north, clockwise, in `[0, 360]`: the direction the loop should head toward. */
  heading?: number;
  config: RouteConfig;
}

/** Neither or both of `workout` / `targetDistanceKm` were supplied. */
export class RouteInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RouteInputError";
  }
}

/** A workout description was supplied but yielded no usable target distance. */
export class RouteParseError extends Error {
  readonly detail: string;
  constructor(message: string, detail: string) {
    super(message);
    this.name = "RouteParseError";
    this.detail = detail;
  }
}

const round1 = (n: number): number => Math.round(n * 10) / 10;
const round2 = (n: number): number => Math.round(n * 100) / 100;

function slug(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

const EMPTY_CHECKSUM: ParsedWorkout["checksum"] = {
  statedMinutes: null,
  statedKm: null,
  computedMinutes: 0,
  computedKm: 0,
  ok: true,
};

export async function generateRoute(
  input: GenerateRouteInput,
  fetchImpl?: typeof fetch,
): Promise<RouteResult> {
  const { workout, targetDistanceKm, title, date, config, variant = 0 } = input;
  const { waypoints, heading } = input;
  const hasWorkout = typeof workout === "string" && workout.trim().length > 0;
  const hasManual = typeof targetDistanceKm === "number" && Number.isFinite(targetDistanceKm);

  if (hasWorkout === hasManual) {
    throw new RouteInputError(
      "Provide exactly one of `workout` or `targetDistanceKm`",
    );
  }

  let segments: Segment[] = [];
  let checksum = EMPTY_CHECKSUM;
  const warnings: string[] = [];
  let targetMeters: number;

  if (hasWorkout) {
    const parsed = parseWorkout(workout, config.paces, {
      fallbackRunPaceMinPerKm: DEFAULTS.fallbackRunPaceMinPerKm,
    });
    if (parsed.targetDistanceMeters <= 0) {
      throw new RouteParseError(
        "Could not derive a target distance from the workout text",
        parsed.warnings.join("; "),
      );
    }
    segments = parsed.segments;
    checksum = parsed.checksum;
    warnings.push(...parsed.warnings);
    targetMeters = parsed.targetDistanceMeters;
  } else {
    if (targetDistanceKm! <= 0) {
      throw new RouteInputError("`targetDistanceKm` must be greater than 0");
    }
    targetMeters = targetDistanceKm! * 1000;
  }

  const hillsPreference = config.hillsPreference ?? DEFAULTS.hillsPreference;
  const greenPreference = config.greenPreference ?? DEFAULTS.greenPreference;
  let best: TrailRouterRoute;
  let guided: RouteResult["guided"];

  if ((waypoints && waypoints.length > 0) || (heading !== undefined && heading !== null)) {
    let guidance;
    try {
      guidance = validateGuidance(config.start, targetMeters, waypoints, heading);
    } catch (err) {
      if (err instanceof GuidanceError) throw new RouteInputError(err.message);
      throw err;
    }
    const result = await generateGuided(
      {
        start: config.start,
        targetMeters,
        guidance,
        hillsPreference,
        greenPreference,
        variant,
      },
      fetchImpl,
    );
    best = result.route;
    warnings.push(...result.warnings);
    guided = {
      waypoints: guidance.waypoints,
      heading: guidance.heading,
      requests: result.requests,
      distanceMeters: Math.round(best.distanceMeters),
    };
  } else {
    const routes = await fetchRoutes(
      {
        start: variant > 0 ? nudgeStart(config.start, variant) : config.start,
        targetDistanceMeters: targetMeters,
        hillsPreference,
        greenPreference,
      },
      fetchImpl,
    );
    best = chooseCandidate(routes, targetMeters, variant);
  }

  if (best.overriddenParameters && Object.keys(best.overriddenParameters).length > 0) {
    warnings.push(
      `Trail Router overrode parameters: ${JSON.stringify(best.overriddenParameters)}`,
    );
  }

  const name = title?.trim() || "Runna route";
  const km = round1(targetMeters / 1000);
  const isoDate = date?.slice(0, 10);
  const filename =
    isoDate && title?.trim()
      ? `${isoDate}-${slug(title)}-${km}km.gpx`
      : `route-${km}km.gpx`;

  const gainPerKm =
    best.distanceMeters > 0
      ? best.ascentMeters / (best.distanceMeters / 1000)
      : 0;

  return {
    gpx: lineStringToGpx(best.coordinates, name),
    coordinates: best.coordinates,
    filename,
    targetDistanceKm: round2(targetMeters / 1000),
    route: {
      distanceKm: round2(best.distanceMeters / 1000),
      ascentM: round1(best.ascentMeters),
      descentM: round1(best.descentMeters),
      elevationGainPerKm: round1(gainPerKm),
      hilliness: hilliness(gainPerKm),
      greenScore: round2(best.greenScore),
      ...(best.overriddenParameters
        ? { overriddenParameters: best.overriddenParameters }
        : {}),
    },
    segments,
    checksum,
    warnings,
    variant,
    ...(guided ? { guided } : {}),
  };
}
