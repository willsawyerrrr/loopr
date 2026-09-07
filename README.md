# runna-router

A personal Vercel serverless function that turns the next planned run in a
[Runna](https://runna.com) training plan into a GPX loop route.

Given a Runna workout description (or a manual target distance) plus a small
config, it computes the total target route distance, asks the
[Trail Router](https://trailrouter.com) API for a matching loop, converts the
best candidate to a GPX 1.1 track, and returns JSON:

```json
{ "gpx": "…", "filename": "…", "targetDistanceKm": 0, "route": {}, "segments": [], "checksum": {}, "warnings": [] }
```

An iOS 26 Shortcut reads the workout from the subscribed Runna calendar, calls
this function, saves the GPX, and hands it to the Runna app via the share sheet.
See `docs/feat/route-pipeline/shortcut-spec.md`.

## Development

```sh
npm install
npm test          # vitest
npm run typecheck # tsc --noEmit
```

## Attribution

Routes via Trail Router, map data © OpenStreetMap contributors, ODbL.
