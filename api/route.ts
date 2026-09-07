import { DEFAULT_PACES, DEFAULTS, type RouteConfig } from "../src/config.js";
import {
  generateRoute,
  RouteInputError,
  RouteParseError,
  type GenerateRouteInput,
} from "../src/route.js";
import { TrailRouterError } from "../src/trailrouter.js";

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function parseStart(value: unknown): [number, number] | null {
  const pair = Array.isArray(value)
    ? value
    : typeof value === "string"
      ? value.split(",").map((n) => Number(n.trim()))
      : null;
  if (!pair || pair.length !== 2) return null;
  const lon = Number(pair[0]);
  const lat = Number(pair[1]);
  if (!Number.isFinite(lon) || !Number.isFinite(lat)) return null;
  return [lon, lat];
}

function mergePaces(overrides: unknown): Record<string, number> {
  const merged: Record<string, number> = { ...DEFAULT_PACES };
  if (overrides && typeof overrides === "object") {
    for (const [phrase, pace] of Object.entries(overrides as Record<string, unknown>)) {
      if (typeof pace === "number" && Number.isFinite(pace)) {
        merged[phrase.toLowerCase()] = pace;
      }
    }
  }
  return merged;
}

function buildConfig(
  start: [number, number],
  hillsPreference: unknown,
  greenPreference: unknown,
  paces: unknown,
): RouteConfig {
  return {
    start,
    hillsPreference:
      typeof hillsPreference === "number" ? hillsPreference : DEFAULTS.hillsPreference,
    greenPreference:
      typeof greenPreference === "number" ? greenPreference : DEFAULTS.greenPreference,
    paces: mergePaces(paces),
  };
}

async function run(input: GenerateRouteInput): Promise<Response> {
  try {
    return json(await generateRoute(input), 200);
  } catch (err) {
    if (err instanceof RouteInputError) return json({ error: err.message }, 400);
    if (err instanceof RouteParseError) {
      return json({ error: err.message, detail: err.detail }, 422);
    }
    if (err instanceof TrailRouterError) {
      return json({ error: err.message, detail: err.detail }, 502);
    }
    return json({ error: "Internal error", detail: String(err) }, 500);
  }
}

export async function POST(request: Request): Promise<Response> {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const start = parseStart(body["start"]);
  if (!start) return json({ error: "`start` must be `[lon, lat]`" }, 400);

  const hasWorkout = typeof body["workout"] === "string" && body["workout"].trim() !== "";
  const hasManual = typeof body["targetDistanceKm"] === "number";
  if (!hasWorkout && !hasManual) {
    return json(
      { error: "Provide either `workout` or `targetDistanceKm`" },
      400,
    );
  }

  return run({
    ...(hasWorkout ? { workout: body["workout"] as string } : {}),
    ...(hasManual ? { targetDistanceKm: body["targetDistanceKm"] as number } : {}),
    ...(typeof body["title"] === "string" ? { title: body["title"] } : {}),
    ...(typeof body["date"] === "string" ? { date: body["date"] } : {}),
    config: buildConfig(
      start,
      body["hillsPreference"],
      body["greenPreference"],
      body["paces"],
    ),
  });
}

export async function GET(request: Request): Promise<Response> {
  const params = new URL(request.url).searchParams;

  const start = parseStart(params.get("start"));
  if (!start) return json({ error: "`start` query param must be `lon,lat`" }, 400);

  const distanceKm = Number(params.get("distanceKm"));
  if (!Number.isFinite(distanceKm) || distanceKm <= 0) {
    return json({ error: "`distanceKm` query param must be a positive number" }, 400);
  }

  return run({
    targetDistanceKm: distanceKm,
    ...(params.get("title") ? { title: params.get("title")! } : {}),
    ...(params.get("date") ? { date: params.get("date")! } : {}),
    config: buildConfig(
      start,
      params.has("hills") ? Number(params.get("hills")) : undefined,
      params.has("green") ? Number(params.get("green")) : undefined,
      undefined,
    ),
  });
}
