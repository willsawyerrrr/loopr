# runna-router

A personal Vercel serverless function that turns the next planned run in a
[Runna](https://runna.com) training plan into a GPX loop route.

Given a Runna workout description (or a manual target distance) plus a small
config, it computes the total target route distance, asks the
[Trail Router](https://trailrouter.com) API for a matching loop, picks the
candidate closest to that distance, and converts it to a GPX 1.1 track.

`GET`/`POST` `/api/route` returns JSON by default:

```json
{ "gpx": "…", "filename": "…", "targetDistanceKm": 0, "route": {}, "segments": [], "checksum": {}, "warnings": [] }
```

The response also carries a `previewUrl` — a short link
(`/api/preview?id=…`, backed by a KV store, 30-day expiry) to a Leaflet map of
that exact route on OpenStreetMap. `?format=gpx` returns the file directly;
`?format=html` returns the same map page rendered from a fresh route.

An iOS 26 Shortcut reads the workout from the subscribed Runna calendar, calls
this function, and saves the GPX to iCloud Drive; you import it in the Runna app
(planned workout → Add Route → file picker). See
`docs/feat/route-pipeline/shortcut-spec.md`.

A native iOS app in `ios/` generates, views, saves and exports routes from the
same endpoint. See `docs/feat/ios-app/overview.md`.

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
