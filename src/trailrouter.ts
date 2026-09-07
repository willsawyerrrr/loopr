import { DEFAULTS } from "./config.js";

const ENDPOINT = "https://trailrouter.com/ors/experimentalroutes";
const USER_AGENT = "runna-router (personal use)";

export interface TrailRouterRoute {
  distanceMeters: number;
  /** `[lon, lat]` pairs, or `[lon, lat, ele]` triples where elevation is present. */
  coordinates: [number, number, number?][];
  ascentMeters: number;
  descentMeters: number;
  /** Routing cost; lower is better within one response, not comparable across `hills_preference` values. */
  weight: number;
  greenScore: number;
  /** Metres of the route by surface type. */
  wayTypes?: Record<string, number>;
  /** Non-empty when the backend clamped a request parameter. */
  overriddenParameters?: Record<string, unknown>;
}

export interface TrailRouterQuery {
  /** `[lon, lat]`. */
  start: [number, number];
  targetDistanceMeters: number;
  hillsPreference: number;
  greenPreference: number;
}

export class TrailRouterError extends Error {
  readonly status: number | null;
  readonly detail: string;

  constructor(message: string, status: number | null, detail: string) {
    super(message);
    this.name = "TrailRouterError";
    this.status = status;
    this.detail = detail;
  }
}

function buildUrl(q: TrailRouterQuery): string {
  const params = new URLSearchParams({
    coordinates: `${q.start[0]},${q.start[1]}`,
    roundtrip: "true",
    target_distance: String(Math.round(q.targetDistanceMeters)),
    hills_preference: String(q.hillsPreference),
    green_preference: String(q.greenPreference),
    avoid_repetition: String(DEFAULTS.avoidRepetition),
    avoid_unsafe_streets: String(DEFAULTS.avoidUnsafeStreets),
    avoid_unlit_streets: String(DEFAULTS.avoidUnlitStreets),
  });
  return `${ENDPOINT}?${params.toString()}`;
}

function num(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseRoute(raw: unknown): TrailRouterRoute | null {
  if (!isObject(raw)) return null;
  const r = raw;
  const geometry = r["geometry"] as Record<string, unknown> | undefined;
  const coords = geometry?.["coordinates"];
  if (!Array.isArray(coords) || coords.length === 0) return null;

  const coordinates: [number, number, number?][] = [];
  for (const point of coords) {
    if (!Array.isArray(point) || point.length < 2) return null;
    const lon = Number(point[0]);
    const lat = Number(point[1]);
    if (!Number.isFinite(lon) || !Number.isFinite(lat)) return null;
    const ele = point.length > 2 ? Number(point[2]) : Number.NaN;
    coordinates.push(Number.isFinite(ele) ? [lon, lat, ele] : [lon, lat]);
  }
  if (coordinates.length === 0) return null;

  const overridden = r["overriddenParameters"];
  return {
    distanceMeters: num(r["distance"]),
    coordinates,
    ascentMeters: num(r["ascent"]),
    descentMeters: num(r["descent"]),
    weight: num(r["weight"]),
    greenScore: num(r["greenScore"]),
    ...(isObject(r["wayTypes"])
      ? { wayTypes: r["wayTypes"] as Record<string, number> }
      : {}),
    ...(isObject(overridden) && Object.keys(overridden).length > 0
      ? { overriddenParameters: overridden }
      : {}),
  };
}

/** Ascending by distance-to-target, then by lower `weight`. */
function byTargetFit(
  targetMeters: number,
): (a: TrailRouterRoute, b: TrailRouterRoute) => number {
  return (a, b) =>
    Math.abs(a.distanceMeters - targetMeters) -
      Math.abs(b.distanceMeters - targetMeters) || a.weight - b.weight;
}

/** Fetch and defensively parse Trail Router candidates, closest-to-target first. */
export async function fetchRoutes(
  q: TrailRouterQuery,
  fetchImpl: typeof fetch = fetch,
): Promise<TrailRouterRoute[]> {
  let response: Response;
  try {
    response = await fetchImpl(buildUrl(q), {
      headers: { "User-Agent": USER_AGENT, Accept: "application/json" },
    });
  } catch (cause) {
    throw new TrailRouterError("Trail Router request failed", null, String(cause));
  }

  const body = await response.text();
  if (!response.ok) {
    throw new TrailRouterError(
      `Trail Router returned ${response.status}`,
      response.status,
      body.slice(0, 500),
    );
  }

  let json: unknown;
  try {
    json = JSON.parse(body);
  } catch {
    throw new TrailRouterError(
      "Trail Router response was not JSON",
      response.status,
      body.slice(0, 500),
    );
  }

  const rawRoutes = (json as Record<string, unknown>)?.["routes"];
  if (!Array.isArray(rawRoutes) || rawRoutes.length === 0) {
    throw new TrailRouterError(
      "Trail Router returned no routes",
      response.status,
      body.slice(0, 500),
    );
  }

  const routes = rawRoutes
    .map(parseRoute)
    .filter((r): r is TrailRouterRoute => r !== null);
  if (routes.length === 0) {
    throw new TrailRouterError(
      "Trail Router routes had no usable geometry",
      response.status,
      body.slice(0, 500),
    );
  }

  return routes.sort(byTargetFit(q.targetDistanceMeters));
}

/** The candidate whose `distance` is closest to `targetMeters`, tie-broken by lower `weight`. */
export function pickBest(
  routes: TrailRouterRoute[],
  targetMeters: number,
): TrailRouterRoute {
  if (routes.length === 0) {
    throw new TrailRouterError("No routes to choose from", null, "");
  }
  return [...routes].sort(byTargetFit(targetMeters))[0]!;
}
