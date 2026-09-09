# Research: Runna → Trail Router Route Pipeline

## Task statement

Build a personal automation that, for a given planned run in the user's Runna
training plan, computes the target route distance, generates a matching loop
route via Trail Router's free API, converts it to a GPX file, and hands it to the
user on their iPhone to import into Runna manually.

Delivery = an **iOS 26 Shortcut** (calendar read + workout-text hand-off +
trigger + file hand-off) plus a small **Vercel serverless function** (workout
parse + Trail Router call + route selection + GeoJSON→GPX) deployed at
`runna-router.willsawyerrrr.dev`.

Architecture is a thin, documented Shortcut (action-by-action spec + config-file
format, no opaque `.shortcut` in the repo) calling a reviewable TypeScript Vercel
function that holds all real logic.

## Findings

### 1. Runna feed & workout grammar

- Runna exposes the plan as a subscribable iCalendar feed, already subscribed
  into Google Calendar as a calendar named "Runna". Shortcuts reads it via native
  calendar actions. Runna has no public API; the unofficial one is out of scope.
- **Completed runs** — timed events, title e.g. `🏃 Wednesday Evening Walk`,
  description carries `📊 Summary: Distance: 2.82km …` + lap splits. Post-run
  only, not useful for routing.
- **Planned workouts** — all-day events. Detailed ones (~1 week ahead) carry a
  description that is a verbatim text serialization of the app's workout screen.
  Further-out ones are title only (`🏃 Easy Run`), no description; Runna
  backfills detail ~1 week before each week. The tool therefore generates the
  next ~week's route on demand, not a batch of the whole plan.
- The calendar summary can be a bare `🏃 Easy Run` even when the description is
  fully populated — genericness of the title is not a signal. The Shortcut must
  read the Notes field itself.

**Workout description grammar** (from real samples):

- Sections: `Warm-Up` / `Repeat xN` (aka `N reps of:`) / `Session` / `Cool Down`.
- Each segment has **either** a duration (`60s`, `2 mins`, `5 mins`) **or** a
  distance (`750m`, `1km`, `5km`), plus an activity (WALK / RUN).
- Activity / pace, in order: an **explicit pace in the text** (`5km time trial at
  4:25/km`) wins; else `walking` / `rest` → walk; else a configured pace phrase
  (`conversational pace`, and `easy pace` / `tempo` / `5k pace` … as they
  appear) → run at that pace; else → run at the fallback pace with a warning.
  Words like `time trial`, `tempo`, `threshold`, `strides` don't name a pace, so
  those segments would previously be dropped — now a **distance** segment always
  counts (the km is literal) even when the pace was guessed.
- A `•` bullet line can hold two comma-separated segments
  (`2 mins at a conversational pace, 60s walking`).
- The title line — `Type • field • field`, or a bare workout name like `5km Time
  Trial` — carries the checksums: `• 29m` / `• 25-35m` → stated minutes;
  `• 6km` → stated km. Distance-phase workouts tend to carry the km, not a
  single minute figure.
- Footer `📲 View in the Runna app: …/workout?dayId=..._plan_week_3_WALK_RUN_0&weekIndex=3`
  — `dayId`/`weekIndex` are a stable per-workout id if ever needed.

Sample A — title `🏃 Walk Run • 29m`:

```
Walk Run • 29m • 29m

5 mins walking warm up

4 reps of:
• 60s at a conversational pace, 30s walking
• 2 mins at a conversational pace, 60s walking

60s at a conversational pace

5 mins walking cool down
```

Sample B — "Your First Continuous Run", calendar summary a bare `🏃 Easy Run`:
Warm-Up `5 mins walking warm up` (WALK); Session `750m at a conversational pace`
(RUN); Cool Down `5 mins walking cool down` (WALK).

Sample C — "5km Time Trial", app shows `Time Trial · 6km` / `25m - 35m`:
Warm-Up `1km at a conversational pace` (RUN) + `120s walking rest` (WALK);
Session `5km time trial at 4:25/km` (RUN). Total ≈ 6.2 km (the app's "6km"
ignores the walk rest). No `run`/pace-phrase keyword on the session line — the
parser takes the distance literally and the pace from `at 4:25/km`.

### 2. Trail Router API

**Endpoint:** `GET https://trailrouter.com/ors/experimentalroutes` (production).
Dev mirror `https://osm.trailrouter.com/ors/experimentalroutes` is London-only.
GET only; all parameters on the query string.

| Param | Type / range | Meaning |
|---|---|---|
| `coordinates` | string, pipe-separated `lon,lat` pairs | Waypoints. Roundtrip: a single coordinate suffices. |
| `roundtrip` | boolean | `true` = starts and finishes at coordinate 0; other coords ignored. |
| `target_distance` | integer, metres | Desired length. `0` = direct route. |
| `green_preference` | double, `0`..`1` | `1` = very green, `0` = no preference. |
| `hills_preference` | double, `-1`..`1` | `-1` avoid, `0` neutral, `1` prefer. |
| `avoid_unsafe_streets` | boolean | Avoid primary/secondary/tertiary streets without footpaths. |
| `avoid_repetition` | boolean | Avoid out-and-back sections. |
| `avoid_unlit_streets` | boolean | Prefer well-lit streets. |
| `skip_segments` | string, comma-separated waypoint indices | Straight lines between those waypoints. |
| `green_debug` | boolean | Adds a `greenDebug` object per route. |

**Response shape** (verified against the live API — the schema on
`trailrouter.com/api` lists `score`/`hillsScore`/`distanceScore`/
`repetitionScore`, none of which the live endpoint actually returns):

```jsonc
{
  "routes": [                                             // ~10 candidates
    {
      "distance": 3181,                                    // metres, actual length
      "geometry": { "type": "LineString",
                    "coordinates": [[lon, lat, ele], ...] }, // GeoJSON; 3rd value is elevation (m)
      "waypoints": [[lon, lat, ele], ...],                 // loop anchors only, not turn instructions
      "waypointIndices": [0, 33, ...],                     // indices into geometry.coordinates
      "ascent": 73.4,                                      // total climb (m); == descent for a loop
      "descent": 73.4,
      "weight": 4007.3,                                    // routing cost; lower = better WITHIN one
                                                           //   response, NOT comparable across
                                                           //   hills_preference values (hp=1 is ~1000×)
      "duration": 3827043,                                 // ms; not useful (generic walking speed)
      "wayTypes": { "footway": 72.4, "street": 13.3, ... },// metres by surface type
      "greenScore": 0.13,                                  // greenery fraction 0..1
      "inputParameters": { ... },                          // echo
      "overriddenParameters": { "avoidRepetition": false } // non-empty when the backend clamped a param
    }
  ]
}
```

- Top level is `{ "routes": [ ... ] }` — **~10 candidates** per call. `hills_preference`
  is applied server-side (hp −1 → ascent ~40–70 m; hp 0 → ~50–110 m; hp 1 →
  ~75–130 m over ~5 km), so every candidate already reflects the hill
  preference. **Selection is therefore by length**: pick the candidate whose
  `distance` is closest to `target_distance`, tie-broken by lower `weight`. No
  seed / retry loop (that is a GraphHopper/ORS concept).
- `geometry.coordinates` are `[lon, lat, ele]` — **elevation is present** and is
  carried into the GPX `<ele>`.
- Hilliness is derived locally as `ascent / (distance / 1000)` m/km and banded
  per §1: `< 10` flat, `10–25` rolling, `> 25` hilly.
- **No GPX output** — JSON only. Conversion is the function's job.
- **No authentication**, no documented rate limits, no published API terms or
  attribution demand. Treat as best-effort courtesy use: one call per planned
  run, don't hammer, expect it could throttle or disappear without notice.
- The site gives no formal schema/examples — parse defensively.

### 3. iOS 26 Shortcuts

Core actions below are long-standing (iOS 13–17) and unchanged in iOS 26; iOS 26
adds capability on top.

**Calendar:**
- **Find Calendar Events** — filters: `Start Date`, `End Date`, `Is All Day`,
  `Calendar`, `Location`, `Duration`, `Title`, `Notes`. Date filters support
  exact dates, relative windows, and `is in the range` between two dates.
  **Gotcha:** a run planned for today is an all-day event with a start of 00:00
  today, which is in the past once the Shortcut runs — so "Start Date is in the
  next N days" skips today's run. Filter `Start Date is in the range` from the
  *start of today* (Adjust Date → Get Start of Day) to +8 days instead.
- **Get Details of Calendar Events** — exposes `Notes` (the event description),
  `Title`, `Start Date`, `End Date`, `All Day`, `Calendar`, `Location`, `URL`.
  No official notes-length limit documented; add the `• NNm` checksum to catch a
  truncated/malformed parse.

**Get Contents of URL:** GET/POST/PUT/PATCH/DELETE; custom headers; on
POST/PUT/PATCH a Request Body param appears (JSON / Form / File). JSON responses
are auto-parsed into dictionaries/arrays. The built-in JSON body builder only
supports a top-level object (fine here).

**JSON handling:** `Get Dictionary from Input`, `Get Dictionary Value` (supports
nested key paths like `route.distanceKm`), `Repeat with Each`.

**Text:** `Match Text` takes an **ICU regex** (NSRegularExpression engine),
capture groups via parentheses; known bug — case-insensitive matching can fail to
populate groups, so prefer explicit character classes over the `i` flag.
`Get Group from Matched Text`, `Replace Text` (regex toggle, `$1` backrefs),
`Split Text` (newlines / custom separator).

**Files:** `Save File` (turn off "Ask where to save" to write a fixed path like
`Shortcuts/runna-router-config.json`), `Get File` (read the config JSON back),
`Share` / `Open In` to hand a saved file to another app.

**Ask for Input:** Text / Number / URL / Date — used for the pace editor and the
manual-distance fallback.

**iOS 26 additions (noted, not on the v1 path):** `Use Model` (Apple Intelligence
on-device / Private Cloud Compute / ChatGPT) could parse the freeform workout
text as a fallback; Writing Tools actions (`Make List from Text` etc.);
`Show Content` renders scrollable event lists.

**Automations — unattended time-of-day run:** since iOS 17, personal automations
(incl. Time of Day) set to **"Run Immediately"** fire with no confirmation tap —
**but Apple forces an unsuppressable notification banner** in that mode
(confirmed through iOS 26). The final "share GPX into Runna" step is interactive
regardless, so full unattended operation is not the goal.

### 4. Vercel

- Functions at `api/route.ts` (the pipeline) and `api/preview.ts` (renders a
  `previewUrl`). No `vercel.json` needed.
- **Preview store (key-value):** the short `previewUrl` (`?id=<12 hex>`) needs a
  Redis-compatible KV store. Add **Upstash for Redis** from the Vercel
  dashboard → Storage → Create Database → free plan → connect to the
  `runna-router` project; it injects `KV_REST_API_URL` / `KV_REST_API_TOKEN`
  (also read as `UPSTASH_REDIS_REST_URL` / `_TOKEN`). Client: `@upstash/redis`.
  Keys `preview:<id>` with a 30-day TTL. The code degrades to the inline
  `?r=<token>` link when the store env vars are absent, so deploying before the
  store is connected is safe.
- Handler: Web-standard `export function POST(request: Request)` returning
  `Response.json(...)`, or the Node `VercelRequest`/`VercelResponse` signature.
- TypeScript transpiled automatically (esbuild); root `tsconfig.json` honoured
  (no path mappings / project references). Root `package.json` for deps; install
  command inferred from the lockfile.
- **Node runtime:** 24.x (default), 22.x, 20.x — majors only. Node 20 deprecates
  2026-10-01; target **22.x or 24.x**. Pin via `package.json`
  `"engines": { "node": "22.x" }` (wins over the dashboard setting).
- **Custom domain `runna-router.willsawyerrrr.dev`:** Vercel dashboard →
  project → Settings → Domains → Add Domain → enter the subdomain → Vercel shows
  a project-unique CNAME target → add `CNAME runna-router → <value>` at the DNS
  provider for `willsawyerrrr.dev` → Vercel may require a one-time TXT
  verification if the apex is on another account → cert auto-issues once DNS
  resolves. Per project convention, add this domain to the Vercel project as part
  of deployment.

### 5. GPX conversion

- **Coordinate order:** GeoJSON is `[lon, lat, ele?]`; GPX uses `lat="…" lon="…"`
  — latitude first. Every point must be swapped.
- Runna needs a **track** (`<trk><trkseg><trkpt>`), not a `<rte>`. `<time>` is
  omitted. `<ele>` is emitted per point when the Trail Router geometry carries
  elevation (it does for roundtrip routes). Waypoints (`<wpt>`) not needed.
- Minimal valid GPX 1.1:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="runna-router"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
     xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
  <metadata><name>Runna route</name></metadata>
  <trk><name>Runna route</name><trkseg>
    <trkpt lat="51.5074" lon="-0.1278"/>
    ...
  </trkseg></trk>
</gpx>
```

- **Hand-roll** the converter (~15 lines, zero deps, fully reviewable) rather
  than pull `togpx` (stale) or `@dwayneparton/geojson-to-gpx` (newer, TS-native —
  only if metadata/extension needs grow).

### 6. Attribution

- Routing-engine output (directions + geometry) is not a Derivative Database
  under ODbL and needs no attribution as long as it is not redistributed as a
  database.
- ODbL attribution obligations attach to a **publicly used** Produced Work. A
  personal GPX imported into your own watch app is not public.
- Merely calling the API creates no redistribution obligation.
- **v1: no attribution legally required.** As courtesy: `creator="runna-router"`
  on the GPX + a one-line README credit ("Routes via Trail Router, data ©
  OpenStreetMap contributors, ODbL"). Add visible attribution only if the tool is
  ever made public.

## Open questions

1. ~~**Runna GPX import flow**~~ — **resolved (confirmed on device):** import is
   **in-app**, not a share-sheet target. Runna → planned workout → **Add Route**
   → in-app file picker → choose the GPX from Files/iCloud. No Strava Premium
   needed (that requirement is only for attaching a public Strava route). The
   Shortcut's job ends at saving the GPX to a known Files location; the import
   itself stays a manual in-app step.
2. **Runna GPX constraints** — no documented limits on point count, file size, or
   whether `<ele>` is needed for the watch map. Assume track + no elevation
   works; verify.
3. **Does route-following render for a structured workout** (warm-up / intervals
   / cool-down) or only plain runs? Support wording is suggestive, not explicit.
4. **Notes-field length ceiling** in `Get Details of Calendar Events` for very
   long future descriptions (e.g. a 12×400m session). Mitigate with the checksum.
5. **Trail Router API stability / limits** — no published rate limit or SLA; no
   documented `User-Agent` expectation.
6. **`overriddenParameters`** — when/why the backend clamps request params is
   undocumented; the function should surface it.
7. **Pace phrase coverage** — `walking`, `conversational pace`, and explicit
   `M:SS/km` specs seen so far. The rest of the vocabulary (`easy pace`,
   `steady`, `tempo`, `threshold`, `5k pace`, `10k pace`, `marathon pace`,
   `strides`, …) and its min/km values get added to the config over time; an
   unknown phrase surfaces a warning and falls back, but the segment's distance
   still counts.
8. **watchOS build** the user is on (needs ≥ 11 for map display; 26 assumed).

## Assumptions

1. Trail Router response is `{ routes: [ { distance, geometry(LineString
   [lon,lat,ele]), waypoints, waypointIndices, ascent, descent, weight, duration,
   wayTypes, greenScore, inputParameters, overriddenParameters } ] }` — verified
   against the live API; parse defensively (no formal schema published). The
   `score`/`hillsScore`/`distanceScore`/`repetitionScore` fields in the API docs
   do not exist on the live endpoint.
2. `geometry` carries elevation as a 3rd coordinate value; the GPX emits `<ele>`
   per point and omits `<time>`.
3. Trail Router imposes no auth and tolerates modest personal volume; self-limit
   to one call per planned run.
4. The Vercel function does workout parse + route selection + GPX conversion and
   returns a JSON body containing the GPX text plus metadata; the Shortcut never
   parses route geometry.
5. iOS 26 keeps the iOS 13–17 calendar/URL/JSON/text/file action set intact;
   `Get Details of Calendar Events` returns the full `Notes` string for
   Runna-sized descriptions.
6. A Time-of-Day automation set to "Run Immediately" runs the pipeline with no
   confirmation tap but shows an unsuppressable banner; the final Runna hand-off
   is an interactive share-sheet step regardless.
7. Runna accepts a plain GPX 1.1 single-segment track, no waypoints, for a
   planned workout via the in-app **Add Route** picker, and displays it on
   watchOS ≥ 11 when recording via the iOS app. Garmin support is out of scope
   for v1 (same GPX loads into Garmin Connect directly).
8. Regex parsing of the workout description is primary; the header's `• NNm` /
   `• NNkm` figures validate each parse (km check for the distance phase, minutes
   check while paces are known); `Use Model` is a possible future fallback, not v1.
9. Node 22.x on Vercel; `api/route.ts` with a Web-standard handler; no
   `vercel.json` unless headers/routing need tuning.
10. No OSM/Trail Router attribution legally required; courtesy credit in README +
    GPX `creator`.
11. `start` is the device's current location, captured by the Shortcut on each
    run (routes generate wherever you set off). `hills_preference` (0.0) and
    `green_preference` (0.0) live in the Shortcut's iCloud config file; all three
    are passed to the function per request. `roundtrip=true`,
    `avoid_repetition=true`, `avoid_unsafe_streets=true`, `avoid_unlit_streets=true`
    are sensible defaults.

## Sources

- Trail Router API — https://trailrouter.com/api/
- Trail Router, "How Trail Router works" — https://trailrouter.com/blog/how-trail-router-works/
- Runna Support, "How to Follow a Route on Runna (Apple Watch)" — https://support.runna.com/en/articles/11027305-how-to-follow-a-route-on-runna-apple-watch
- Runna Support, "Using your Apple Watch with Runna" — https://support.runna.com/en/articles/6306200-using-your-apple-watch-with-runna-and-getting-the-most-out-of-it
- Apple Support, "What's new in Shortcuts for iOS/iPadOS/macOS/watchOS/visionOS 26" — https://support.apple.com/en-us/125148
- 9to5Mac, "iOS 26's Shortcuts app adds 25+ new actions" — https://9to5mac.com/2025/12/09/ios-26s-shortcuts-app-adds-25-new-actions-heres-everything-new/
- Matthew Cassinelli, "All Automations Now Run Immediately In Shortcuts" — https://matthewcassinelli.com/automations-run-immediately-shortcuts-notifications/
- Matthew Cassinelli, "Find Calendar Events" — https://matthewcassinelli.com/actions/find-calendar-events/
- Apple Support, "Parsing JSON in Shortcuts" — https://support.apple.com/guide/shortcuts/parsing-json-apdde2dfe749/ios
- Apple Support, "Intro to personal automation in Shortcuts" — https://support.apple.com/guide/shortcuts/intro-to-personal-automation-apd690170742/ios
- Vercel Docs, "Using the Node.js Runtime with Vercel Functions" — https://vercel.com/docs/functions/runtimes/node-js
- Vercel Docs, "Supported Node.js versions" — https://vercel.com/docs/functions/runtimes/node-js/node-js-versions
- Vercel Docs, "Adding & Configuring a Custom Domain" — https://vercel.com/docs/domains/working-with-domains/add-a-domain
- OSM Foundation, "Licence/Attribution Guidelines" — https://osmfoundation.org/wiki/Licence/Attribution_Guidelines
- OSM Foundation, "Licence and Legal FAQ" — https://osmfoundation.org/wiki/Licence/Licence_and_Legal_FAQ
- Topografix, GPX 1.1 schema — https://www.topografix.com/GPX/1/1/
