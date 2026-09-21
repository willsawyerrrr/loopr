import { DEFAULT_PACES, DEFAULTS, type RouteConfig } from "../src/config.js";
import {
  generateRoute,
  RouteInputError,
  RouteParseError,
  type GenerateRouteInput,
} from "../src/route.js";
import { encodePreview, previewData, renderMapPage } from "../src/preview.js";
import { putPreview } from "../src/preview-store.js";
import { TrailRouterError } from "../src/trailrouter.js";

type Format = "json" | "html" | "gpx";

function asFormat(value: string | null | undefined): Format {
  return value === "html" || value === "gpx" ? value : "json";
}

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

/** `undefined` when absent, `null` when not a non-negative integer. */
function parseVariant(value: unknown): number | null | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  const n = typeof value === "string" ? Number(value) : value;
  return typeof n === "number" && Number.isSafeInteger(n) && n >= 0 ? n : null;
}

const INVALID_VARIANT = { error: "`variant` must be a non-negative integer" };

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

async function run(
  input: GenerateRouteInput,
  format: Format,
  origin: string,
): Promise<Response> {
  try {
    const { coordinates, ...result } = await generateRoute(input);
    const name = input.title?.trim() || "Runna route";
    const preview = previewData({ ...result, coordinates }, name);

    if (format === "gpx") {
      return new Response(result.gpx, {
        status: 200,
        headers: {
          "Content-Type": "application/gpx+xml",
          "Content-Disposition": `attachment; filename="${result.filename}"`,
        },
      });
    }
    if (format === "html") {
      return new Response(renderMapPage(preview), {
        status: 200,
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    }
    const id = await putPreview(preview);
    const previewUrl = id
      ? `${origin}/api/preview?id=${id}`
      : `${origin}/api/preview?r=${encodePreview(preview)}`;
    return json({ ...result, coordinates, previewUrl }, 200);
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

  const url = new URL(request.url);
  const format = asFormat(
    url.searchParams.get("format") ??
      (typeof body["format"] === "string" ? body["format"] : null),
  );

  const start = parseStart(body["start"]);
  if (!start) return json({ error: "`start` must be `[lon, lat]`" }, 400);

  const variant = parseVariant(body["variant"]);
  if (variant === null) return json(INVALID_VARIANT, 400);

  const hasWorkout = typeof body["workout"] === "string" && body["workout"].trim() !== "";
  const hasManual = typeof body["targetDistanceKm"] === "number";
  if (!hasWorkout && !hasManual) {
    return json(
      { error: "Provide either `workout` or `targetDistanceKm`" },
      400,
    );
  }

  return run(
    {
      ...(hasWorkout ? { workout: body["workout"] as string } : {}),
      ...(hasManual ? { targetDistanceKm: body["targetDistanceKm"] as number } : {}),
      ...(typeof body["title"] === "string" ? { title: body["title"] } : {}),
      ...(typeof body["date"] === "string" ? { date: body["date"] } : {}),
      ...(variant !== undefined ? { variant } : {}),
      config: buildConfig(
        start,
        body["hillsPreference"],
        body["greenPreference"],
        body["paces"],
      ),
    },
    format,
    url.origin,
  );
}

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const params = url.searchParams;
  const format = asFormat(params.get("format"));

  const start = parseStart(params.get("start"));
  if (!start) return json({ error: "`start` query param must be `lon,lat`" }, 400);

  const distanceKm = Number(params.get("distanceKm"));
  if (!Number.isFinite(distanceKm) || distanceKm <= 0) {
    return json({ error: "`distanceKm` query param must be a positive number" }, 400);
  }

  const variant = parseVariant(params.get("variant") ?? undefined);
  if (variant === null) return json(INVALID_VARIANT, 400);

  return run(
    {
      targetDistanceKm: distanceKm,
      ...(params.get("title") ? { title: params.get("title")! } : {}),
      ...(params.get("date") ? { date: params.get("date")! } : {}),
      ...(variant !== undefined ? { variant } : {}),
      config: buildConfig(
        start,
        params.has("hills") ? Number(params.get("hills")) : undefined,
        params.has("green") ? Number(params.get("green")) : undefined,
        undefined,
      ),
    },
    format,
    url.origin,
  );
}
