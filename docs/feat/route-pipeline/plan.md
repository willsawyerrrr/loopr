# Build Plan: Runna → Trail Router Route Pipeline

Read `research.md` first for the "why". This is the "what to build" for v1.

## Goal

On demand (or from a daily automation), for the next planned run in the user's
Runna plan: read the workout, compute the total target distance, generate a
matching loop route via Trail Router, convert it to GPX, and hand the file to the
user on their iPhone to import into Runna manually.

## Shape of the system

```
iOS 26 Shortcut "Runna Route"
  Find Calendar Events (Runna cal, all-day, start of today → +8 days)
  Get Details → Notes (workout text) + Start Date + Title
  Get File → runna-router-config.json (iCloud Drive)
  POST https://runna-router.willsawyerrrr.dev/api/route
       { workout, paces, start, hillsPreference, greenPreference }
        │
        ▼
  Vercel function  api/route.ts
    parseWorkout(text, paces)   → segments + targetDistanceMeters + checksum
    trailRouter(start, target, prefs) → candidate closest to target distance
    lineStringToGpx(coords, name)     → GPX 1.1 track XML (with <ele>)
    → JSON { gpx, filename, targetDistanceKm,
             route:{distanceKm, ascentM, descentM, elevationGainPerKm, hilliness, greenScore},
             segments, checksum, warnings }
        │
        ▼
  Get Dictionary Value → gpx, checksum.ok, targetDistanceKm, route.distanceKm
  If checksum.ok == false → Ask for Input (manual km) → re-POST { targetDistanceKm, ... }
  Save File → iCloud Drive / Shortcuts / <filename>
  Show notification (distance, hilliness, warnings)
  Import into Runna manually: workout → Add Route → file picker
```

Companion Shortcut **"Update Runna Paces"** edits `runna-router-config.json`.

## Repo layout

```
api/route.ts                 Vercel function (thin HTTP wrapper over src/)
src/
  workout.ts                 parse Runna workout text → segments → target distance
  trailrouter.ts             Trail Router API client + best-route selection
  gpx.ts                     GeoJSON LineString → GPX 1.1 track
  route.ts                   orchestration: text+config → { gpx, metadata }
  config.ts                  types + defaults (prefs, fallback paces)
test/
  workout.test.ts
  gpx.test.ts
  trailrouter.test.ts
  route.test.ts              orchestration with mocked fetch
docs/feat/route-pipeline/
  research.md  plan.md  shortcut-spec.md
config.example.json
package.json  tsconfig.json  vitest.config.ts  .gitignore  README.md
```

- Single package, ESM (`"type": "module"`), Node 22.x pinned in `engines`.
- `api/route.ts` imports from `../src/` via relative paths; Vercel bundles it.
- No `vercel.json` unless CORS/headers force it (see step 5).

## Interfaces / data shapes

### `src/config.ts`

```ts
export interface RouteConfig {
  start: [number, number];          // [lon, lat]
  hillsPreference?: number;          // -1..1, default 0
  greenPreference?: number;          // 0..1, default 0
  paces: Record<string, number>;    // phrase (lowercased) → min/km
}

export const DEFAULTS = {
  hillsPreference: 0,
  greenPreference: 0,
  avoidRepetition: true,
  avoidUnsafeStreets: true,
  avoidUnlitStreets: true,
  fallbackRunPaceMinPerKm: 7.5,     // used when a run phrase is unknown
} as const;

export const DEFAULT_PACES: Record<string, number> = {
  "walking": 11.0,
  "conversational pace": 7.5,
};
```

Home `start` is personal and never committed — it lives only in the user's
iCloud config file. `config.example.json` ships a placeholder.

### `src/workout.ts`

```ts
export type Activity = "walk" | "run";

export interface Segment {
  activity: Activity;
  source: "duration" | "distance";
  seconds?: number;                 // when source === "duration"
  meters?: number;                  // when source === "distance"
  distanceMeters: number;           // resolved distance for this segment
  phrase?: string;                  // matched pace phrase, if any
  reps: number;                     // expansion factor already applied === 1
}

export interface ParsedWorkout {
  segments: Segment[];
  targetDistanceMeters: number;     // Σ segment.distanceMeters
  checksum: {
    statedMinutes: number | null;   // from "• NNm", null if absent
    computedMinutes: number;        // Σ durations + Σ (distance ÷ pace)
    ok: boolean;                    // |stated - computed| <= 2, or stated null
  };
  warnings: string[];               // unknown phrases, unparsed lines, etc.
}

export function parseWorkout(
  text: string,
  paces: Record<string, number>,
  opts?: { fallbackRunPaceMinPerKm?: number },
): ParsedWorkout;
```

Parsing rules:

1. Normalise: split on newlines, trim, drop empty lines for structure but track
   blank lines as `Repeat` block terminators.
2. Ignore lines: `View in the Runna app`, `📊 Summary`, `Distance: …`,
   `Time: …`, `Avg Pace: …`, lap lines. Capture `•\s*(\d+)\s*m\b` on the first
   header line (`Walk Run • 29m • 29m`) as `statedMinutes`.
3. Section headers (`Warm-Up`, `Session`, `Cool Down`, `Warm Up`) — skip, no
   value.
4. Repeat markers: `^(?:Repeat\s*[x×]\s*(\d+)|(\d+)\s*reps? of:?)` → the
   following `•` lines repeat N times until a blank line or the next
   section/repeat header. Emit each expanded segment individually with `reps: 1`.
5. Segment line → split on `,` into parts; each part:
   - duration: `(\d+)\s*s\b` → seconds; `(\d+)\s*min(?:s|utes?)?\b` → minutes×60.
   - distance: `(\d+(?:\.\d+)?)\s*km\b` → ×1000 m; `(\d+)\s*m\b` (not `min`) → m.
     Match `min` before bare `m`.
   - activity: contains `walk` → `walk` (pace = `paces.walking`); else the first
     known pace phrase found in the part → `run` with that pace; else contains
     `run`/`jog` → `run` with `fallbackRunPaceMinPerKm` + warning; else →
     warning, skip the part.
   - resolve `distanceMeters`: `meters` directly, or
     `(seconds/60) / paceMinPerKm * 1000`.
6. `targetDistanceMeters` = Σ. `computedMinutes` = Σ durations(min) +
   Σ (segmentDistanceKm × paceMinPerKm for distance segments).
7. `checksum.ok` = `statedMinutes == null || abs(stated - computed) <= 2`.

### `src/trailrouter.ts`

```ts
export interface TrailRouterRoute {
  distanceMeters: number;
  coordinates: [number, number, number?][];  // [lon, lat, ele?]
  ascentMeters: number;
  descentMeters: number;
  weight: number;                            // routing cost; lower = better within one response
  greenScore: number;
  wayTypes?: Record<string, number>;
  overriddenParameters?: Record<string, unknown>;
}

export interface TrailRouterQuery {
  start: [number, number];          // [lon, lat]
  targetDistanceMeters: number;
  hillsPreference: number;
  greenPreference: number;
}

export async function fetchRoutes(
  q: TrailRouterQuery,
  fetchImpl?: typeof fetch,
): Promise<TrailRouterRoute[]>;      // parsed, defensive, closest-to-target first

export function pickBest(routes: TrailRouterRoute[], targetMeters: number): TrailRouterRoute;
```

- Build `GET https://trailrouter.com/ors/experimentalroutes` with
  `coordinates=<lon>,<lat>`, `roundtrip=true`,
  `target_distance=<round(meters)>`, `hills_preference`, `green_preference`,
  `avoid_repetition=true`, `avoid_unsafe_streets=true`,
  `avoid_unlit_streets=true`.
- Send `User-Agent: runna-router (personal use)`.
- Defensive parse against the live schema (research §2 — not the API-docs
  schema): tolerate missing numeric fields (default 0), require
  `geometry.coordinates` non-empty, `routes` non-empty → else throw
  `TrailRouterError` with status + body snippet. Preserve the 3rd coordinate
  value (elevation) when present.
- `pickBest`: candidate with `distanceMeters` closest to `targetMeters`,
  tie-broken by lower `weight`. `hills_preference` is honoured server-side, so
  every candidate already reflects it — selection only fixes the length.
- No seed/retry loop — Trail Router returns ~10 candidates per call.

### `src/gpx.ts`

```ts
export function lineStringToGpx(
  coordinates: [number, number, number?][],   // [lon, lat, ele?]
  name: string,
): string;
```

- GPX 1.1, single `<trk><trkseg>`, one `<trkpt lat lon>` per coordinate
  (swapped). Nested `<ele>` only when the tuple carries a finite 3rd value; no
  `<time>`. `creator="runna-router"`. XML-escape `name`.

### `src/route.ts`

```ts
export interface RouteResult {
  gpx: string;
  filename: string;                 // e.g. 2026-09-13-walk-run-3.2km.gpx
  targetDistanceKm: number;
  route: {
    distanceKm: number;
    ascentM: number;
    descentM: number;
    elevationGainPerKm: number;
    hilliness: "flat" | "rolling" | "hilly";   // banded on elevationGainPerKm, research §1
    greenScore: number;
    overriddenParameters?: Record<string, unknown>;
  };
  segments: Segment[];
  checksum: ParsedWorkout["checksum"];
  warnings: string[];
}

export async function generateRoute(input: {
  workout?: string;                 // raw Notes text
  targetDistanceKm?: number;        // manual override / bare-event fallback
  title?: string;                   // for filename + gpx name
  date?: string;                    // ISO date for filename
  config: RouteConfig;
}, fetchImpl?: typeof fetch): Promise<RouteResult>;
```

- Exactly one of `workout` / `targetDistanceKm` required. If `workout`: parse it;
  carry `checksum` + `warnings`. If `targetDistanceKm`: synthesise an empty
  parse (`checksum.ok = true`, no segments).
- `filename`: `<date>-<slug(title)>-<km>km.gpx`; fall back to
  `route-<km>km.gpx`.
- Never throw on checksum failure — return it; the Shortcut decides.

### `api/route.ts`

```ts
export async function POST(request: Request): Promise<Response>;
```

- Parse JSON body → `{ workout?, targetDistanceKm?, title?, date?, paces?,
  start, hillsPreference?, greenPreference? }`.
- 400 on: missing `start`; neither `workout` nor `targetDistanceKm`; malformed
  JSON.
- Merge `paces` over `DEFAULT_PACES`; apply `DEFAULTS` for missing prefs.
- Call `generateRoute`; on `TrailRouterError` → 502 with `{ error, detail }`;
  on parse error → 422 `{ error, detail }`.
- 200 → `Response.json(result)`.
- Also accept `GET /api/route?distanceKm=&start=lon,lat&hills=` for quick manual
  testing (thin wrapper mapping query → `generateRoute`).

## Phased delivery (commit breakdown for the implementer)

1. **`chore: Scaffold TypeScript project`** — `package.json` (ESM, Node 22.x,
   scripts: `test`, `typecheck`), `tsconfig.json`, `vitest.config.ts`,
   `.gitignore`, `README.md` (what it is, courtesy attribution line).
2. **`feat: Add Runna workout parser`** — `src/config.ts`, `src/workout.ts` +
   `test/workout.test.ts`. Tests cover Sample A (16 min walk / 13 min run →
   ~3.2 km at default paces, checksum ok), Sample B (5 min walk + 750 m + 5 min
   walk → ~1.65 km), comma-split parts, `reps of:` expansion, unknown phrase →
   warning + fallback, bare title / no description → caller uses override path.
3. **`feat: Add GeoJSON to GPX converter`** — `src/gpx.ts` +
   `test/gpx.test.ts` (coordinate swap, XML escaping, well-formed output,
   single trkseg).
4. **`feat: Add Trail Router API client`** — `src/trailrouter.ts` +
   `test/trailrouter.test.ts` (mocked `fetch`: query construction, defensive
   parse of a sample response, `pickBest` ordering, error on empty/`non-200`).
5. **`feat: Add route generation endpoint`** — `src/route.ts`, `api/route.ts`,
   `config.example.json` + `test/route.test.ts` (mocked fetch, POST happy path,
   manual-override path, 400/422/502 branches, filename shape).
6. **`docs: Add iOS 26 Shortcut specification`** — `docs/feat/route-pipeline/
   shortcut-spec.md`: action-by-action build steps for both shortcuts, the
   config-file JSON schema, the automation setup, and the notification-banner
   caveat.

Docs (`research.md`, `plan.md`) are committed by the orchestrator before
implementation starts.

## `config.example.json`

```json
{
  "start": [-0.1278, 51.5074],
  "hillsPreference": 0.0,
  "greenPreference": 0.0,
  "paces": {
    "walking": 11.0,
    "conversational pace": 7.5
  }
}
```

## Testing

- `vitest`, all unit-level; mock `fetch` for the Trail Router client and the
  endpoint. No live network calls in tests.
- `npm run typecheck` (`tsc --noEmit`) must pass.
- Manual/out-of-band (documented in `shortcut-spec.md`, not automated): deploy to
  Vercel, hit `GET /api/route?distanceKm=3&start=<home>` from a browser, confirm
  the GPX opens and imports into a Runna workout on the phone.

## Risks & non-goals

| Risk / gap | Handling |
|---|---|
| Runna GPX import flow unverified | Documented as a manual check in `shortcut-spec.md`; does not block the function build. |
| Pace vocabulary grows beyond 2 phrases | Unknown run phrase → `warnings` + `fallbackRunPaceMinPerKm`; user adds the phrase to their config. Never silently wrong. |
| Trail Router down / throttling | Function returns 502 with detail; user falls back to manual route apps. Response caching is out of scope for v1. |
| Checksum fails (truncated notes / odd format) | Returned to the Shortcut; Shortcut prompts for manual distance and re-POSTs. |
| `overriddenParameters` present | Surfaced in the response `route.overriddenParameters` and a warning. |

**Non-goals for v1:** custom routing engine; Runna private API; automated GPX
*import* into Runna (stays a manual share-sheet step); Garmin support (same GPX,
loaded into Garmin Connect directly); response caching; scheduling beyond a
single Time-of-Day automation; multiple saved start points.
