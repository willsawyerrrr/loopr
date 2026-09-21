# iOS app

A native SwiftUI iOS 26 app that generates, views, saves and exports routes by
calling `POST /api/route`. It is a personal app built for a free Apple
developer team: no App Groups, iCloud/CloudKit or app extensions.

## Layout

```
ios/
  project.yml            XcodeGen spec for the app (the .xcodeproj is generated, not committed)
  RunnaRouter/           SwiftUI app target
  RouteKit/              Swift package: API client, models, GPX, SwiftData store
```

- **`RouteKit`** holds everything the UI and future App Intents share:
  - `RouteService` — `generate(_:)` posts a manual target distance, the start
    `[lon, lat]` and the hills/green preferences.
  - `RouteResponse` — decodes `gpx`, `filename`, `route`, `warnings`,
    `previewUrl` and `coordinates`. `resolvedPoints()` uses `coordinates` when
    the API returns them and otherwise parses the points out of `gpx`.
  - `SavedRoute` — the SwiftData model (metadata plus the coordinates);
    `SavedRoute.makeContainer()` opens the on-device store.
  - `GPXWriter` / `GPXParser` / `GPXFile` — GPX 1.1 output matching the server
    and a `Transferable` that shares a `.gpx` file.
- **`RunnaRouter`** is the UI: a *Generate* tab (distance, hills, green, current
  location as start, map, save, share GPX) and a *Saved* tab (list, detail map,
  swipe to delete, share GPX).

## Run it

```sh
brew install xcodegen
cd ios
xcodegen generate
open RunnaRouter.xcodeproj
```

Pick your device (or a simulator), set your own team under *Signing &
Capabilities* (`DEVELOPMENT_TEAM` is not committed), and run. On a device with a
free team the install expires after 7 days; re-run from Xcode to renew it.

In the simulator, set a location first (*Features → Location*, or
`xcrun simctl location booted set <lat>,<lon>`).

## Tests

```sh
cd ios/RouteKit
swift test
```

Covers response decoding (with and without `coordinates`), GPX writing and
parsing, request encoding, server error handling and the SwiftData store.

## Importing into Runna

Sharing a route produces a `.gpx` file. Save it to Files, then import it in
Runna: planned workout → **Add Route** → file picker.
