import { DEFAULTS, type RouteConfig } from "./config.js";
import { fetchRoutes, pickBest } from "./trailrouter.js";
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
  computedMinutes: 0,
  ok: true,
};

export async function generateRoute(
  input: GenerateRouteInput,
  fetchImpl?: typeof fetch,
): Promise<RouteResult> {
  const { workout, targetDistanceKm, title, date, config } = input;
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

  const routes = await fetchRoutes(
    {
      start: config.start,
      targetDistanceMeters: targetMeters,
      hillsPreference: config.hillsPreference ?? DEFAULTS.hillsPreference,
      greenPreference: config.greenPreference ?? DEFAULTS.greenPreference,
    },
    fetchImpl,
  );
  const best = pickBest(routes, targetMeters);

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
  };
}
