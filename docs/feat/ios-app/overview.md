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

- **`RouteKit`** holds everything the UI and the App Intents share:
  - `RouteService` — `generate(_:)` posts a manual target distance, the start
    `[lon, lat]` and the hills/green preferences.
  - `RouteResponse` — decodes `gpx`, `filename`, `route`, `warnings`,
    `previewUrl` and `coordinates`. `resolvedPoints()` uses `coordinates` when
    the API returns them and otherwise parses the points out of `gpx`.
  - `SavedRoute` — the SwiftData model (metadata plus the coordinates);
    `SavedRoute.makeContainer()` opens the on-device store.
  - `GPXWriter` / `GPXParser` / `GPXFile` — GPX 1.1 output matching the server
    and a `Transferable` that shares a `.gpx` file.
  - `RouteDistance` — converts a `Measurement<UnitLength>` to km and enforces
    the 1–50 km range.
  - `StartResolver` / `LastStartStore` — a fresh location fix if one arrives
    within 8 s, otherwise the last start point used, otherwise a clear error.
  - `RouteFormat` — the shared distance / name / subtitle strings.
- **`RunnaRouter`** is the UI: a *Generate* tab (distance, hills, green, current
  location as start, map, save, share GPX) and a *Saved* tab (list, detail map,
  swipe to delete, share GPX).

## Siri and Shortcuts

The intents live in the app target (`RunnaRouter/Intents/`) and run in the app's
own process, so they share the SwiftData store with the UI. No entitlements
beyond the location usage string are needed.

| Intent | What it does |
|---|---|
| `CreateRouteOfDistanceIntent` | Backs the phrases that say the distance aloud. Takes a whole-kilometre `DistanceEntity` (1–50 km) and otherwise behaves like `CreateRouteIntent`. |
| `CreateRouteIntent` | Takes a distance, generates a loop from the current location (or the last start point), and returns a map snippet with **Save** and **Regenerate** buttons. Runs in the background. |
| `OpenRouteIntent` | Opens a saved route in the app. |

Say the distance in the phrase — *"Create a 10 km route in Runna Router"*,
*"Make me a 10 km route with Runna Router"* or *"Plan a 10 km run in Runna
Router"* (1–50 whole kilometres; "a" or "an", so *"Create an 8 km route…"*
works too). Siri phrases can only embed an `AppEntity` /
`AppEnum`, not a `Measurement`, so the spoken distance is a `DistanceEntity`.
Leave the distance out — *"Create a route in Runna Router"*, *"Make me a route
with Runna Router"*, *"Generate a run route with Runna Router"* or *"Plan a run
in Runna Router"* — and Siri asks *"How far do you want to run?"*, accepting any
length in km or miles (also the parameter when the action is used in a
Shortcut). *"Open `<route>` in Runna Router"* opens a saved route.

- **Snippet:** the map is a `MKMapSnapshotter` image with the route drawn on it
  (a live `Map` renders blank in a snippet). **Save** stores the route without
  opening the app; **Regenerate** produces a new loop for the same distance.
  Generated routes are held in memory until saved, so a route that has sat
  unsaved after the app process exits must be re-requested.
- **Start point:** the current location when a fix arrives in time, otherwise
  the last start point used (recorded whenever the app or an intent gets a
  fix). With neither, the intent asks you to open the app once and allow
  location.
- **Preferences:** hills and green use the values set on the *Generate* tab.
- **Time budget:** the API call times out after 25 s to stay inside the
  ~30 s background limit.
- **Saved routes** are `AppEntity` / `IndexedEntity` values, indexed in
  Spotlight when saved and removed when deleted, and matched by name for
  Siri.

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
parsing, request encoding, server error handling, the SwiftData store,
distance conversion, start-point resolution and the display strings.

Voice invocation and background location inside an intent only behave like
production on a device; check them there after installing.

## Importing into Runna

Sharing a route produces a `.gpx` file. Save it to Files, then import it in
Runna: planned workout → **Add Route** → file picker.
