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

`?format=gpx` returns the file directly; `?format=html` returns a Leaflet map
page for eyeballing the route on OpenStreetMap.

An iOS 26 Shortcut reads the workout from the subscribed Runna calendar, calls
this function, and saves the GPX to iCloud Drive; you import it in the Runna app
(planned workout → Add Route → file picker). See
`docs/feat/route-pipeline/shortcut-spec.md`.

## Development

```sh
npm install
npm test          # vitest
npm run typecheck # tsc --noEmit
```

## Attribution

Routes via Trail Router, map data © OpenStreetMap contributors, ODbL.
