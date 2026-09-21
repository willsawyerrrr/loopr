# iOS app

A native SwiftUI iOS 26 app that generates, views, saves and exports routes by
calling `POST /api/route`. It reads the subscribed Runna calendar itself, so
upcoming runs turn into routes without the "Runna Route" Shortcut. It is a personal app built for a free Apple
developer team: no App Groups, iCloud/CloudKit or app extensions.

## Layout

```
ios/
  project.yml            XcodeGen spec for the app (the .xcodeproj is generated, not committed)
  Loopr/                 SwiftUI app target
  RouteKit/              Swift package: API client, models, GPX, SwiftData store
```

- **`RouteKit`** holds everything the UI and the App Intents share:
  - `RouteService` — `generate(_:)` posts either a manual target distance or a
    Runna workout (`workout`, `title`, `date`, `paces`), plus the start
    `[lon, lat]` and the hills/green preferences.
  - `RunPlan` / `CalendarEvent` / `PlannedRun` — the pure calendar logic, with no
    EventKit import: picks all-day events in `[start of today, +8 days)`
    earliest first, builds the workout request from an event, chooses the
    calendar (`Runna`, case-insensitive contains, unless one is chosen) and
    computes the next 06:00.
  - `PaceStore` — the pace table (phrase to min/km) in `UserDefaults`, seeded
    with the defaults from `src/config.ts`.
  - `RouteResponse` — decodes `gpx`, `filename`, `route`, `warnings`,
    `previewUrl` and `coordinates`. `resolvedPoints()` uses `coordinates` when
    the API returns them and otherwise parses the points out of `gpx`.
  - `SavedRoute` — the SwiftData model (metadata, coordinates, server warnings
    and, for calendar runs, the event key); `SavedRoute.makeContainer()` opens
    the on-device store.
  - `GPXWriter` / `GPXParser` / `GPXFile` — GPX 1.1 output matching the server
    and a `Transferable` that shares a `.gpx` file.
  - `RouteDistance` — converts a `Measurement<UnitLength>` to km and enforces
    the 1–50 km range.
  - `StartResolver` / `LastStartStore` — a fresh location fix if one arrives
    within 8 s, otherwise the last start point used, otherwise a clear error.
  - `RouteFormat` — the shared distance / name / subtitle strings.
- **`Loopr`** is the UI: a *Runs* tab (upcoming Runna runs), a *Generate* tab
  (distance, hills, green, current location as start, map, save, share GPX) and
  a *Saved* tab (list, detail map, swipe to delete, share GPX). The EventKit
  adapter (`RunCalendar`), route generation for a run (`RunPreparation`) and the
  background refresh (`MorningRefresh`) live here.

## Runs tab

Lists the runs on the Runna calendar from the start of today through the next 8
days: all-day events only, earliest first. Each row shows the title and date;
once a route exists it also shows the distance and a checkmark.

- **Calendar access:** the app asks for full calendar access
  (`requestFullAccessToEvents()`) from a button on the tab. If access is denied
  the tab says so and offers a button that opens the system Settings.
- **Calendar:** the calendar whose title contains `Runna` (case-insensitive). If
  there is none, the tab prompts you to choose one under *Settings → Calendar*;
  the choice is kept and takes precedence.
- **Tapping a run** generates its route if it has none: the workout text is the
  event's Notes, sent with the title, the date (`yyyy-MM-dd`), the start point,
  the hills/green preferences and the pace table. The start is the current
  location, or the last start point used. The map, stats, warnings (verbatim),
  *Share GPX* and *Regenerate* are shown. A run with no Notes reports that it
  has no workout.
- **Saving:** a generated route is saved automatically, once per event (keyed by
  event identifier plus date), and appears in *Saved* too. *Regenerate* updates
  that same saved route.

## Settings

A gear on the *Runs* tab opens:

- **Calendar** — pick which calendar holds the runs (default: automatic).
- **Route preferences** — the hills and green sliders, the same values the
  *Generate* tab and Siri use.
- **Paces** — an editable table of Runna pace phrase to min/km, seeded with the
  server defaults and sent as `paces` with each workout. When the server warns
  that a pace isn't configured, add the phrase here and regenerate.
- **Prepare routes each morning** — off by default; see below.

## Morning refresh

With *Prepare routes each morning* on, the app schedules a background app
refresh (`BGAppRefreshTask`, `dev.willsawyerrrr.Loopr.refresh`) for the next
06:00 local. When it runs, it generates the route for today's run (or the next
one) if it doesn't have one, saves it, and posts a notification "Route ready:
`<title>` · `<distance>`". Turning the setting on asks for notification
permission. Each run reschedules the next.

iOS decides when background refreshes happen and may run them late or not at
all, notably if the app is rarely opened or Low Power Mode is on. Without a
location fix in the background it uses the last start point, so open the app
where you run from. Tapping a run in the *Runs* tab always generates a missing route.

## Siri and Shortcuts

The intents live in the app target (`Loopr/Intents/`) and run in the app's
own process, so they share the SwiftData store with the UI. No entitlements
beyond the location usage string are needed.

| Intent | What it does |
|---|---|
| `CreateRouteOfDistanceIntent` | Backs the phrases that say the distance aloud. Takes a whole-kilometre `DistanceEntity` (1–50 km) and otherwise behaves like `CreateRouteIntent`. |
| `CreateRouteIntent` | Takes a distance, generates a loop from the current location (or the last start point), and returns a map snippet with **Save** and **Regenerate** buttons. Runs in the background. |
| `OpenRouteIntent` | Opens a saved route in the app. |

Say the distance in the phrase — *"Create a 10 km route in Loopr"*,
*"Make me a 10 km route with Loopr"* or *"Plan a 10 km run in
Loopr"* (1–50 whole kilometres; "a" or "an", so *"Create an 8 km route…"*
works too). Siri phrases can only embed an `AppEntity` /
`AppEnum`, not a `Measurement`, so the spoken distance is a `DistanceEntity`.
Leave the distance out — *"Create a route in Loopr"*, *"Make me a route
with Loopr"*, *"Generate a run route with Loopr"* or *"Plan a run
in Loopr"* — and Siri asks *"How far do you want to run?"*, accepting any
length in km or miles (also the parameter when the action is used in a
Shortcut). *"Open `<route>` in Loopr"* opens a saved route.

- **Snippet:** the map is a `MKMapSnapshotter` image with the route drawn on it
  (a live `Map` renders blank in a snippet). **Save** stores the route without
  opening the app; **Regenerate** produces a new loop for the same distance.
  Generated routes are held in memory until saved, so a route that has sat
  unsaved after the app process exits must be re-requested.
- **Start point:** the current location when a fix arrives in time, otherwise
  the last start point used (recorded whenever the app or an intent gets a
  fix). With neither, the intent asks you to open the app once and allow
  location.
- **Preferences:** hills and green use the values set on the *Generate* tab
  (or in *Settings*).
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
open Loopr.xcodeproj
```

Pick your device (or a simulator), set your own team under *Signing &
Capabilities* (`DEVELOPMENT_TEAM` is not committed), and run. Calendar runs
need a device (or simulator) with the Runna calendar subscribed. On a device with a
free team the install expires after 7 days; re-run from Xcode to renew it.

In the simulator, set a location first (*Features → Location*, or
`xcrun simctl location booted set <lat>,<lon>`).

## Tests

```sh
cd ios/RouteKit
swift test
```

Covers response decoding (with and without `coordinates`), GPX writing and
parsing, request encoding (manual and workout), server error handling, the
SwiftData store, distance conversion, start-point resolution, the display
strings, run selection and request building from calendar events, calendar
choice, the morning schedule time and the pace table.

The EventKit adapter is a thin wrapper over that logic and is not unit-tested.
Voice invocation, background location inside an intent, calendar access and
background refresh only behave like production on a device; check them there
after installing.

## Importing into Runna

Sharing a route produces a `.gpx` file. Save it to Files, then import it in
Runna: planned workout → **Add Route** → file picker.
