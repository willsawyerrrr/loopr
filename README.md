# loopr

A personal Vercel serverless function that generates a GPX loop route for a run or
walk.

Give it a target distance and a start point, or a
[Runna](https://runna.com) workout description, which it parses to work out the
total distance. Using a small config, it asks the
[Trail Router](https://trailrouter.com) API for a matching loop, picks the
candidate closest to that distance, and converts it to a GPX 1.1 track.

`GET`/`POST` `/api/route` returns JSON by default:

```json
{ "gpx": "…", "filename": "…", "targetDistanceKm": 0, "route": {}, "coordinates": [], "segments": [], "checksum": {}, "warnings": [], "variant": 0 }
```

`variant` is an optional non-negative integer (a body field on `POST`, a query
param on `GET`; anything else is a `400`). Absent or `0` returns the candidate
closest to the target distance, and identical requests return identical routes.
For `variant > 0` the server seeds a PRNG from it, nudges the start Trail Router
is asked about by 40–120 m in a seeded direction, and picks one of the candidates
within ±5% of the target (the closest when none qualify). The same `variant`
repeats the same choice; a different one gives a different loop. The response
carries the applied `variant`.

`coordinates` is the chosen route as `[lon, lat, ele?]` points, so a client can
draw it without parsing the GPX. The response also carries a `previewUrl` — a short link
(`/api/preview?id=…`, backed by a KV store, 30-day expiry) to a Leaflet map of
that exact route on OpenStreetMap. `?format=gpx` returns the file directly;
`?format=html` returns the same map page rendered from a fresh route.

A native iOS app in `ios/` reads the subscribed Runna calendar, lists your
upcoming runs, and generates, views, saves and exports a route for each from
this endpoint. It can also prepare the next route each morning and notify you.
You import the GPX in the Runna app (planned workout → Add Route → file
picker). See `docs/feat/ios-app/overview.md`.

An iOS 26 Shortcut is an alternative client: it reads the same calendar, calls
this function, and saves the GPX to iCloud Drive. See
`docs/feat/route-pipeline/shortcut-spec.md`.

## Development

```sh
npm install
npm test          # vitest
npm run typecheck # tsc --noEmit
```

The short `previewUrl` needs a Redis-compatible KV store — add **Upstash for
Redis** (free) from the Vercel dashboard and connect it to the project. Without
it the code falls back to a long inline preview link.

## Attribution

Routes via Trail Router, map data © OpenStreetMap contributors, ODbL.
