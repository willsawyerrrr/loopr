import { DEFAULTS } from "./config.js";

const ENDPOINT = "https://trailrouter.com/ors/experimentalroutes";
const USER_AGENT = "runna-router (personal use)";

export interface TrailRouterRoute {
  distanceMeters: number;
  /** `[lon, lat]` pairs. */
  coordinates: [number, number][];
  score: number;
  hillsScore: number;
  greenScore: number;
  distanceScore: number;
  repetitionScore: number;
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

function parseRoute(raw: unknown): TrailRouterRoute | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  const geometry = r["geometry"] as Record<string, unknown> | undefined;
  const coords = geometry?.["coordinates"];
  if (!Array.isArray(coords) || coords.length === 0) return null;

  const coordinates: [number, number][] = [];
  for (const point of coords) {
    if (!Array.isArray(point) || point.length < 2) return null;
    const lon = Number(point[0]);
    const lat = Number(point[1]);
    if (!Number.isFinite(lon) || !Number.isFinite(lat)) return null;
    coordinates.push([lon, lat]);
  }

  return {
    distanceMeters: num(r["distance"]),
    coordinates,
    score: num(r["score"]),
    hillsScore: num(r["hillsScore"]),
    greenScore: num(r["greenScore"]),
    distanceScore: num(r["distanceScore"]),
    repetitionScore: num(r["repetitionScore"]),
    ...(r["overriddenParameters"] && typeof r["overriddenParameters"] === "object"
      ? { overriddenParameters: r["overriddenParameters"] as Record<string, unknown> }
      : {}),
  };
}

/** Fetch and defensively parse Trail Router candidates, sorted best-first. */
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

  return routes.sort(
    (a, b) => b.score - a.score || b.distanceScore - a.distanceScore,
  );
}

/** Highest `score`, tie-broken by higher `distanceScore`. */
export function pickBest(routes: TrailRouterRoute[]): TrailRouterRoute {
  if (routes.length === 0) {
    throw new TrailRouterError("No routes to choose from", null, "");
  }
  return [...routes].sort(
    (a, b) => b.score - a.score || b.distanceScore - a.distanceScore,
  )[0]!;
}
