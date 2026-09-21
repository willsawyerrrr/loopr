# iOS 26 Shortcut Specification

Two Shortcuts drive the pipeline from the phone:

- **Runna Route** — the daily/on-demand generator.
- **Update Runna Paces** — a small editor for the config file.

Both read and write a single JSON config file in iCloud Drive so the pace table
and preferences never live in the repo or the function. The route's start point
is the device's **current location**, taken fresh on each run — so routes
generate wherever you set off, not only at home.

## Config file

**Path:** `iCloud Drive / Shortcuts / runna-router-config.json`
(the folder `Save File` writes to by default when "Ask where to save" is off).

```json
{
  "hillsPreference": 0.0,
  "greenPreference": 0.0,
  "paces": {
    "walking": 11.0,
    "conversational pace": 7.5
  }
}
```

| Key | Type | Meaning |
|---|---|---|
| `hillsPreference` | number, `-1`..`1` | `-1` avoid hills, `0` neutral, `1` prefer. |
| `greenPreference` | number, `0`..`1` | `0` no preference, `1` maximally green. |
| `paces` | object | Lowercased Runna pace phrase → minutes per km. Add a row whenever the function returns an "unknown run pace phrase" warning. |

`config.example.json` in the repo is the template; copy it into iCloud Drive and
edit the values once on the device.

The `start` sent to `/api/route` is `[lon, lat]` (longitude first, GeoJSON
order). The Shortcut needs Location access; grant it on first run.

## Shortcut 1 — "Runna Route"

### Actions

1. **Get File** — Service: iCloud Drive, Path:
   `Shortcuts/runna-router-config.json`, "Show Document Picker" off.
2. **Get Dictionary from Input** (the file contents) → `Config`.
3. **Build the date window** — a run planned for today is an all-day event whose
   start is 00:00 today, i.e. already in the past by the time the Shortcut runs,
   so "Start Date is in the next N days" silently skips it. Anchor the window at
   the start of today instead:
   - **Date** → current date.
   - **Adjust Date** → *Get Start of* → *Day* → `TodayStart`.
   - **Adjust Date** → *Add* → `8` *Days* to `TodayStart` → `WindowEnd`.
   (Using *start of today* rather than "now" also absorbs the UTC-vs-local
   day-boundary offset — the Runna calendar's timezone is UTC.)
4. **Find Calendar Events**
   - `Start Date` `is in the range` `TodayStart` to `WindowEnd`
   - Calendar `is` `Runna`
   - `Is All Day` `is` `true`
   - Sort by `Start Date`, ascending; Limit `1`.
   This returns today's run if there is one, otherwise the next upcoming.
5. **If** (there are no events) → **Show Alert** "No planned Runna run in the next
   week" → **Stop Shortcut**.
6. **Get Details of Calendar Events** → repeat for the single event, pulling:
   - `Notes` → `WorkoutText`
   - `Start Date` → `RunDate`
   - `Title` → `RunTitle`
7. **Format Date** — `RunDate` → `yyyy-MM-dd` → `RunDateISO`.
8. **Build the request body:**
   - **Get Current Location**, then **Get Details of Location** twice for
     `Longitude` and `Latitude`; assemble a **List** `[Longitude, Latitude]`
     (longitude first) → `Start`.
   - **Dictionary** action:

     ```json
     {
       "workout": "<WorkoutText>",
       "title": "<RunTitle>",
       "date": "<RunDateISO>",
       "start": <Start>,
       "hillsPreference": <Config.hillsPreference>,
       "greenPreference": <Config.greenPreference>,
       "paces": <Config.paces>
     }
     ```

   Use a **Dictionary** action so `start` stays a real array and `paces` a real
   object. `workout` is the raw multi-line Notes string.
9. **Get Contents of URL**
   - URL `https://loopr.willsawyerrrr.dev/api/route`
   - Method `POST`
   - Request Body `JSON`, keys from the dictionary in step 8
   - Headers: `Content-Type: application/json`
   → response auto-parses to `Response`.
10. **If** `Response.error` `has any value` → **Show Alert** with
    `Response.error` + `Response.detail` → **Stop Shortcut**.
11. **Get Dictionary Value** — `checksum.ok` from `Response` → `ChecksumOk`.
12. **If** `ChecksumOk` `is` `false`:
    - **Show Alert** — "Workout parse looks off. Stated
      `Response.checksum.statedKm` km / `Response.checksum.statedMinutes` min vs
      computed `Response.checksum.computedKm` km /
      `Response.checksum.computedMinutes` min." (Either stated field can be
      empty — show what's there.)
    - **Ask for Input** — Number, "Target distance in km?" → `ManualKm`
    - **Get Contents of URL** — same URL/method, body
      `{ "targetDistanceKm": <ManualKm>, "title": <RunTitle>, "date":
      <RunDateISO>, "start": <Start>, "hillsPreference": <Config.hillsPreference>,
      "greenPreference": <Config.greenPreference> }`
      → overwrite `Response`.
13. **Get Dictionary Value** — `gpx` → `GpxText`; `filename` → `GpxName`.
14. **Text** — `GpxText`; **Save File**
    - Service iCloud Drive, Destination `Shortcuts/routes/`, filename `GpxName`
    - "Ask Where to Save" off, "Overwrite If File Exists" on.
15. **Show Notification** — title `RunTitle`, body:
    "`Response.targetDistanceKm` km target → `Response.route.distanceKm` km loop,
    `Response.route.hilliness` (`Response.route.elevationGainPerKm` m/km). Saved
    as `GpxName`. `Response.warnings` joined by newline."

The Shortcut ends here — it produces the GPX file and nothing more. Importing it
is a manual step **inside the Runna app** (see below), not a share-sheet hand-off.

### Importing the GPX into Runna

Confirmed: Runna's GPX import is **in-app**, not a share-sheet target.

1. Open Runna → the planned workout → **Add Route** (the button in the workout
   action bar).
2. Choose the GPX route option → the file picker opens on Files / iCloud Drive.
3. Pick `Shortcuts/routes/<filename>.gpx` (where step 14 saved it).

No Strava Premium is needed for this path (that requirement is only for attaching
a public Strava route). The route then follows on the watch when recording via
the Runna iOS app.

### Previewing a route on a map

The JSON response carries a **`previewUrl`** — a short link
(`…/api/preview?id=<12 hex>`) to a Leaflet page showing *this exact* route on
OpenStreetMap with a distance / hilliness / climb panel and any warnings.
Opening it makes no second Trail Router call. The link is backed by a key-value
store and expires after 30 days (see `research.md` §4 for the store setup). If
the store is not configured the link falls back to an inline `?r=<token>` form
that carries the geometry itself — same page, just a long URL.

- **From the Shortcut:** after step 12, add **Show Web Page** with
  `Response.previewUrl` — an in-app look you dismiss back to the Shortcut. Wrap it
  in a **Choose from Menu** ("Preview" / "Skip") if you don't always want it.
- **Manual / tuning:** open
  `https://loopr.willsawyerrrr.dev/api/route?distanceKm=<km>&start=<lon>,<lat>&hills=<-1..1>&format=html`
  in a browser and vary `hills`. (This form *does* re-run Trail Router, so the
  loop may differ slightly from a saved one — fine for comparing settings.)

`format=gpx` on any request returns the file directly if you'd rather skip Save
File.

### Notes

- The function never throws on a checksum failure — it returns `checksum.ok:
  false` and the Shortcut decides (step 12).
- `warnings` is an array; show it verbatim. An "unknown run pace phrase" warning
  is the signal to run **Update Runna Paces** and add that phrase.
- `Response.route.overriddenParameters`, when present, means Trail Router clamped
  the request (e.g. target distance out of range); it is also echoed in
  `warnings`.

## Shortcut 2 — "Update Runna Paces"

A minimal editor so new pace phrases can be added on the device without editing
JSON by hand.

### Actions

1. **Get File** — `Shortcuts/runna-router-config.json` →
   **Get Dictionary from Input** → `Config`.
2. **Get Dictionary Value** — `paces` from `Config` → `Paces`.
3. **Ask for Input** — Text, "Pace phrase (exactly as Runna writes it, e.g.
   `tempo pace`)" → `Phrase`.
4. **Text** — lowercase `Phrase` (use **Change Case → lowercase**) → `PhraseKey`.
5. **Ask for Input** — Number, "Minutes per km for “`Phrase`”?" → `MinPerKm`.
6. **Set Dictionary Value** — Dictionary `Paces`, Key `PhraseKey`, Value
   `MinPerKm` → `Paces`.
7. **Set Dictionary Value** — Dictionary `Config`, Key `paces`, Value `Paces` →
   `Config`.
8. **Get Dictionary from Input** is not needed; use **Get File Contents** helper:
   convert `Config` back to text with **Get Text from Input** (Shortcuts
   serialises a dictionary to JSON).
9. **Save File** — `Shortcuts/runna-router-config.json`, "Ask Where to Save" off,
   "Overwrite If File Exists" on.
10. **Show Notification** — "Saved `PhraseKey` = `MinPerKm` min/km".

To edit `hillsPreference` or `greenPreference`, extend this Shortcut with the
same **Ask for Input → Set Dictionary Value → Save File** pattern, or edit the
JSON file directly in the Files app.

## Running it

A **Time-of-Day automation** (**Shortcuts → Automation → Time of Day → Run
Immediately**) runs "Runna Route" each morning, generating the day's route from
wherever the phone is at that minute — usually home. On days you start
elsewhere, run the Shortcut manually from where you set off (Home Screen /
widget for a one-tap launch); it takes a fresh current-location fix each time.

Two things stay manual regardless: Apple forces an unsuppressable notification
banner on "Run Immediately" automations, and importing the GPX into Runna is an
in-app step (workout → Add Route → file picker).

## Manual verification checklist (out of band)

Not automated — confirm on the device after the function is deployed:

1. `GET https://loopr.willsawyerrrr.dev/api/route?distanceKm=3&start=<lon>,<lat>`
   in a browser returns JSON with a `gpx` field.
2. Save that `gpx` to a `.gpx` file and import it via Runna → planned workout →
   **Add Route** (in-app file picker). Confirmed working; no Strava Premium
   needed.
3. The route renders on the watch during a recorded run (watchOS ≥ 11).
4. A structured workout (warm-up / intervals / cool-down) still shows the route
   overlay, not just a plain run.
