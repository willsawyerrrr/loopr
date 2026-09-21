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
    `[lon, lat]` and the hills/green preferences. `RouteRequest.regenerated()`
    adds a random `variant` (1–1,000,000) so the server returns a different loop
    than the last one; first generations send none.
  - `RouteShape` — the start (with an optional name), the pins (at most 3) and
    rough heading (degrees clockwise from north, normalised to `[0, 360)`;
    `CompassPoint` maps `N`…`NW` to and from degrees) that steer a loop. Shapes
    saved without a start decode without one. `applied(to:)` sets the
    request's `waypoints` and `heading`, both omitted when empty;
    `unreachablePins(from:targetKm:)` flags pins beyond the distance the server
    accepts.
  - `StartPlace` / `DefaultStartStore` — a chosen start (point and optional
    name) and the *Default start* from Settings, kept in `UserDefaults`.
  - `RunPlan` / `CalendarEvent` / `PlannedRun` — the pure calendar logic, with no
    EventKit import: picks all-day events in `[start of today, +8 days)`
    earliest first, builds the workout request from an event, chooses the
    calendar (`Runna`, case-insensitive contains, unless one is chosen) and
    computes the next 06:00.
  - `PaceStore` — the pace table (phrase to min/km) in `UserDefaults`, seeded
    with the defaults from `src/config.ts`.
  - `RouteResponse` — decodes `gpx`, `filename`, `route`, `warnings`,
    `previewUrl`, `coordinates`, `segments` and `checksum`. `resolvedPoints()`
    uses `coordinates` when the API returns them and otherwise parses the
    points out of `gpx`.
  - `OCRLayout` / `WorkoutText` / `WorkoutOutline` / `ScreenshotRoutePipeline` —
    the screenshot logic (see below), pure and free of Vision.
  - `SavedRoute` — the SwiftData model (metadata, coordinates, server warnings,
    the shape used, where it started from and, for calendar runs, the event key); `SavedRoute.makeContainer()` opens
    the on-device store.
  - `GPXWriter` / `GPXParser` / `GPXFile` — GPX 1.1 output matching the server
    and a `Transferable` that shares a `.gpx` file.
  - `RouteDistance` — converts a `Measurement<UnitLength>` to km and enforces
    the 1–50 km range.
  - `StartResolver` / `LastStartStore` — picks the start for a request: the
    route's own chosen start, else the default start, else a fresh location fix
    if one arrives within 8 s, else the last device location, else a clear
    error. A chosen or default start never asks for the location.
    `LastStartStore` holds the last device location only: a chosen or default
    start never overwrites it, a real fix always does.
  - `RouteFormat` — the shared distance / name / subtitle strings.
- **`Loopr`** is the UI: a *Runs* tab (upcoming Runna runs, and a *From
  screenshot* button), a *Generate* tab
  (distance, hills, green, shape, map, save, share GPX; the route starts at the chosen or default start, else the current location) and
  a *Saved* tab (list, detail map, swipe to delete, share GPX). The *Shape route*
  sheet (`ShapeSheet`) is shared by the *Generate* tab and the run detail. The EventKit
  adapter (`RunCalendar`), route generation for a run (`RunPreparation`) and the
  background refresh (`MorningRefresh`) live here, as do the Vision and
  Foundation Models code for screenshots (`ScreenshotOCR`, `WorkoutRewriter`). Generating again on the
  *Generate* tab, *Regenerate* on a run and the snippet's **Regenerate** all send
  a fresh `variant`.

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
- **Tapping a run** opens its detail. With no saved route it shows the run's
  title, date and workout notes, the *Shape route* row and a **Generate route**
  button; nothing is generated until the button is tapped. Generating sends the
  workout text (the event's Notes) with the title, the date (`yyyy-MM-dd`), the
  start point, the shape, the hills/green preferences and the pace table. The
  start is the shape's chosen start, else the default start, else the current
  location, else the last start point used. Once a route
  exists the map, where it started from, stats, warnings (verbatim), *Share GPX*
  and *Regenerate* are shown. A run with no Notes reports that it has no workout.
- **Saving:** a generated route is saved automatically, once per event (keyed by
  event identifier plus date), and appears in *Saved* too. *Regenerate* sends a
  fresh `variant` and updates that same saved route with a different loop.

## Shape sheet

A **Shape route** row on the *Generate* tab and on a run's detail opens a sheet
with a map centred on the start. The row shows the current shape (`Custom start ·
2 pins · NE`, or `Off`).

- **Start:** a *Start and finish* row above the pins shows where the loop starts
  and ends: *Current location* unless a start is chosen or a default start is
  set. Search for a place or address in the sheet's search field (suggestions
  come from `MKLocalSearchCompleter`) and pick one, or tap *Set start* and tap
  the map. The start marker (the runner) is draggable once chosen, and a dropped
  start is named after what is there when that can be looked up. *Reset* returns
  to the default start, or the current location. The map recentres on the start.
  Choosing a start needs no location access; the device location is only asked
  for while no start is chosen and there is no default start.

- **Pins:** tap the map to drop up to 3 numbered pins, drag one to move it, and
  remove it from its context menu or the minus button beneath the map. The loop
  passes through the pins in a sensible order.
- **Heading:** *Any*, `N`, `NE`, `E`, `SE`, `S`, `SW`, `W` or `NW` picks the direction
  the loop should head toward. With pins, it chooses which side the loop bulges
  and the visiting order.
- **Clear** removes the pins and the heading; **Done** keeps them.
- The shape is sent as `waypoints` and `heading` with every request from that
  screen, including regenerations; its start is sent as the request's `start`.
  The result map numbers the pins and marks the start.
- On a run, the shape defaults to the one the saved route was generated with and
  is saved with the route, so *Regenerate* keeps it. A run with no route
  can be shaped before it is first generated. Morning refresh reuses the saved
  shape, or none.
- Siri and Shortcuts requests are not shaped and use the default start, if any.
- The *From screenshot* screen has no shape either: it uses the default start.

Limits:

- A pin further from the start than 0.75 × the target distance can't be part of a
  loop of that length. The distance is measured from the chosen start (else the
  default start, else the device location). The pin turns orange and the server
  rejects the request; move it closer or raise the distance.
- When the pins force a length well off the target, the route is still returned
  and the server adds a warning giving its real length.
- Trail Router isn't guaranteed to follow pins exactly: a route passes near each
  pin, on the nearest routable path, and may not be a clean loop.

## Settings

A gear on the *Runs* tab opens:

- **Calendar** — pick which calendar holds the runs (default: automatic).
- **Default start** — an optional place (search, or tap the map) that routes
  start and finish at when they have no start of their own; *Clear* removes it.
  It is stored as a name and coordinate. When set it is the start for the
  morning refresh, Siri and Shortcuts, the screenshot flow and any generation
  without a per-route start; a shape's own start overrides it. When unset,
  routes start from the current location as usual.
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
permission. The request is submitted each time the app moves to the background
(the scene's handler must be registered first, so it is never submitted while
launching), and each run reschedules the next.

iOS decides when background refreshes happen and may run them late or not at
all, notably if the app is rarely opened or Low Power Mode is on. It starts at
the default start when one is set. Otherwise, without a location fix in the
background it uses the last device location, so open the app where you run from. A run's *Generate route* button always generates a missing route.

## Siri and Shortcuts

The intents live in the app target (`Loopr/Intents/`) and run in the app's
own process, so they share the SwiftData store with the UI. No entitlements
beyond the location usage string are needed.

| Intent | What it does |
|---|---|
| `CreateRouteOfDistanceIntent` | Backs the phrases that say the distance aloud. Takes a whole-kilometre `DistanceEntity` (1–50 km) and otherwise behaves like `CreateRouteIntent`. |
| `CreateRouteIntent` | Takes a distance, generates a loop from the default start (or the current location, or the last start point), and returns a map snippet with **Save** and **Regenerate** buttons. Runs in the background. |
| `CreateRouteFromScreenshotIntent` | Takes a screenshot of a Runna workout, reads its distance and returns the same map snippet. Not a Siri phrase; see *Route from a screenshot*. |
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
  opening the app; **Regenerate** produces a different loop for the same distance (a fresh `variant` each tap).
  Generated routes are held in memory until saved, so a route that has sat
  unsaved after the app process exits must be re-requested.
- **Start point:** the default start from *Settings* when set, otherwise the
  current location when a fix arrives in time, otherwise the last device
  location (recorded whenever the app or an intent gets a fix). With none of
  these, the intent asks you to open the app once and allow location, or set a
  default start. The spoken line names the start ("… route from Home.") unless
  it was the current location, and the snippet does the same; **Regenerate**
  keeps the start.
- **Preferences:** hills and green use the values set on the *Generate* tab
  (or in *Settings*).
- **Time budget:** the API call times out after 25 s to stay inside the
  ~30 s background limit.
- **Saved routes** are `AppEntity` / `IndexedEntity` values, indexed in
  Spotlight when saved and removed when deleted, and matched by name for
  Siri.

## Route from a screenshot

A screenshot of the Runna workout screen turns into a route the same way a
calendar run does: the recognised text is sent to `POST /api/route` as
`workout`, and the server's parser works out the distance.

**Getting the image.** iOS has no API to capture another app's screen, and
Siri's on-screen awareness only exposes an app's own content, so Siri can't read
Runna. "The current Runna screen" therefore means a screenshot:

- **In the app:** on the *Runs* tab, *From screenshot* opens a sheet with a
  `PhotosPicker` limited to screenshots (newest first, no Photos permission
  needed) and a paste button for an image on the clipboard. The sheet shows the
  recognised text in an editor; correct it and *Make route from this text* to
  regenerate. The result is the same as everywhere else: map, stats, warnings,
  *Save route* and *Share GPX*.
- **From Shortcuts, Back Tap or the Action Button:** `CreateRouteFromScreenshotIntent`
  takes an image (`IntentFile`) and runs in the background. Build a one-action
  shortcut, *Take Screenshot* followed by *Create Route from Screenshot*, then
  bind it under *Settings → Accessibility → Touch → Back Tap*, or to the Action
  Button. With Runna's workout screen showing, a double tap makes the route and
  shows the usual map snippet with **Save** and **Regenerate**. It is not an App
  Shortcut phrase: Siri can't supply the image, so it appears only in the
  Shortcuts app. Its optional *Distance* parameter is used instead of the
  workout when given, and is what the shortcut asks for when the workout can't
  be confirmed.
- There is no Share Extension. Sharing a screenshot into Loopr would need an
  App Group to hand the image to the app, which a free Apple team doesn't get.

**Reading the screen.** `ScreenshotOCR` runs Vision's `RecognizeTextRequest`
(accurate level, English) and turns each observation into an `OCRFragment` with
its position. `OCRLayout` orders them top to bottom and joins fragments that
share a row, first dropping the step numbers in the left gutter and the `WALK` /
`RUN` badges at the right of each step. `WorkoutText.read` then produces the
Notes-style text:

- only the steps between the `Description` heading and the `Start Workout`
  button are kept; the title, status bar, briefing card, quick actions, coach
  card and any completed-activity card sit outside them;
- section headers separate blocks with a blank line; a `Repeat xN` header
  (also `Repeat ×N`, `Repeat Nx`, a leading icon glyph) becomes `N reps of:` and
  each row until the next header becomes a bullet, as in the calendar Notes;
- common OCR confusions are fixed (`O`/`o` as `0` and `I`/`l` as `1` in
  quantities, `2,5km`, `60S`, `60 secs`, `4:25 /km`), the info glyph after
  `pace` is dropped and wrapped lines are joined.

The `Type • Nkm` line under the title is not sent. That figure counts only the
running, so the server's checksum, which compares it with the whole workout,
would flag a correct parse. It is checked separately instead (below).

**Checks and fallbacks.** `ScreenshotRoutePipeline` accepts the response only
when:

1. `checksum.ok` is true, and
2. when the screen states a running distance, the parsed running steps
   (`segments` with `activity == "run"`) agree with it to within 0.3 km or 10 %.

If either fails, or the server can't derive a distance (422), and the on-device
model is available (`SystemLanguageModel.default.availability == .available`),
Foundation Models rewrites the recognised lines into structured steps
(`@Generable`: blocks of `repeats` and `steps`, rendered to Notes-style text by
`WorkoutOutline`) and the request is retried once. If that doesn't pass either,
or the model is unavailable, or there isn't time left in an intent's budget, the
problems are shown verbatim, the recognised text stays editable, and a manual
distance (prefilled with the best guess) generates a loop from the existing
manual request. In the intent this is the *Distance* parameter's prompt. A route
with a wrong distance is never returned silently.

A workout with no stated running distance (a time-based walk/run) has nothing to
check against, so its route is returned with a note that the distance comes from
the steps at the pace settings. A rewritten workout is noted too. Edited text is
sent as written, without a rewrite.

**Limits.**

- The intent shares the ~30 s background budget: location and recognition
  overlap and the requests together get 20 s, so the rewrite retry is skipped
  when less than 8 s remains.
- The recognition fixtures are Vision's output (macOS) for real screenshots of a
  distance-based continuous run and a distance-based walk/run with a repeat,
  plus the structure of a time-based walk/run. Other layouts (long workouts that
  scroll, other step types, light mode, a different Runna version) are
  unverified, and the steps must be fully visible in the screenshot. A simulator
  test also reads a rendered workout image through the app's Vision helper.
- The rewrite fallback and the intent's background timing were not run on a
  device.

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
parsing, request encoding (manual and workout), route shapes (pin cap, heading
normalisation, compass points, request fields, reach check, the start and
decoding shapes saved without one, persistence on saved routes), server error
handling, the SwiftData store, distance conversion, start-point resolution
(chosen, default and device starts and the last-used store), the default start
store, the display
strings, run selection and request building from calendar events, calendar
choice, the morning schedule time and the pace table.

Also covers the screenshot pipeline: OCR fixtures of real Runna screens
(fragments with positions and plain lines) to the expected Notes-style text,
OCR confusions, wrapped lines, repeat variants, and the pipeline's accept,
rewrite and manual-distance decisions with a mocked transport.
`test/screenshot-workout.test.ts` feeds the same expected texts to the server's
parser. The image-to-text step is checked by `ScreenshotOCRTests` in the app
target, which renders a workout screen and runs it through Vision (it compiles
`ScreenshotOCR.swift` into the test bundle rather than launching the app, and
Vision is slow in the simulator, about a minute):

```sh
cd ios && xcodegen generate
xcodebuild test -project Loopr.xcodeproj -scheme Loopr \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The EventKit adapter is a thin wrapper over that logic and is not unit-tested.
Voice invocation, background location inside an intent, calendar access and
background refresh only behave like production on a device; check them there
after installing.

## Importing into Runna

Sharing a route produces a `.gpx` file. Save it to Files, then import it in
Runna: planned workout → **Add Route** → file picker.
