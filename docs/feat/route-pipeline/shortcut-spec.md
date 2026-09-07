# iOS 26 Shortcut Specification

Two Shortcuts drive the pipeline from the phone:

- **Runna Route** — the daily/on-demand generator.
- **Update Runna Paces** — a small editor for the config file.

Both read and write a single JSON config file in iCloud Drive so the personal
data (home start point, pace table) never lives in the repo or the function.

## Config file

**Path:** `iCloud Drive / Shortcuts / runna-router-config.json`
(the folder `Save File` writes to by default when "Ask where to save" is off).

```json
{
  "start": [-0.1278, 51.5074],
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
| `start` | `[lon, lat]` | Home start point. **Longitude first** (GeoJSON order), matching the function and Trail Router. |
| `hillsPreference` | number, `-1`..`1` | `-1` avoid hills, `0` neutral, `1` prefer. |
| `greenPreference` | number, `0`..`1` | `0` no preference, `1` maximally green. |
| `paces` | object | Lowercased Runna pace phrase → minutes per km. Add a row whenever the function returns an "unknown run pace phrase" warning. |

`config.example.json` in the repo is the template; copy it into iCloud Drive and
edit the values once on the device.

## Shortcut 1 — "Runna Route"

### Actions

1. **Get File** — Service: iCloud Drive, Path:
   `Shortcuts/runna-router-config.json`, "Show Document Picker" off.
2. **Get Dictionary from Input** (the file contents) → `Config`.
3. **Find Calendar Events**
   - Calendar `is` `Runna`
   - `Is All Day` `is` `true`
   - `Start Date` `is in the next` `7` `days`
   - Sort by `Start Date`, ascending; Limit `1`.
4. **If** (there are no events) → **Show Alert** "No planned Runna run in the next
   7 days" → **Stop Shortcut**.
5. **Get Details of Calendar Events** → repeat for the single event, pulling:
   - `Notes` → `WorkoutText`
   - `Start Date` → `RunDate`
   - `Title` → `RunTitle`
6. **Format Date** — `RunDate` → `yyyy-MM-dd` → `RunDateISO`.
7. **Text** — build the request body (Dictionary action is fine; this is the
   shape):

   ```json
   {
     "workout": "<WorkoutText>",
     "title": "<RunTitle>",
     "date": "<RunDateISO>",
     "start": <Config.start>,
     "hillsPreference": <Config.hillsPreference>,
     "greenPreference": <Config.greenPreference>,
     "paces": <Config.paces>
   }
   ```

   Use a **Dictionary** action so `start` stays a real array and `paces` a real
   object. `workout` is the raw multi-line Notes string.
8. **Get Contents of URL**
   - URL `https://runna-router.willsawyerrrr.dev/api/route`
   - Method `POST`
   - Request Body `JSON`, keys from the dictionary in step 7
   - Headers: `Content-Type: application/json`
   → response auto-parses to `Response`.
9. **If** `Response.error` `has any value` → **Show Alert** with
   `Response.error` + `Response.detail` → **Stop Shortcut**.
10. **Get Dictionary Value** — `checksum.ok` from `Response` → `ChecksumOk`.
11. **If** `ChecksumOk` `is` `false`:
    - **Show Alert** — "Workout parse looks off (stated
      `Response.checksum.statedMinutes` min vs computed
      `Response.checksum.computedMinutes` min)."
    - **Ask for Input** — Number, "Target distance in km?" → `ManualKm`
    - **Get Contents of URL** — same URL/method, body
      `{ "targetDistanceKm": <ManualKm>, "title": <RunTitle>, "date":
      <RunDateISO>, "start": …, "hillsPreference": …, "greenPreference": … }`
      → overwrite `Response`.
12. **Get Dictionary Value** — `gpx` → `GpxText`; `filename` → `GpxName`.
13. **Text** — `GpxText`; **Save File**
    - Service iCloud Drive, Destination `Shortcuts/`, filename `GpxName`
    - "Ask Where to Save" off, "Overwrite If File Exists" on.
14. **Show Notification** — title `RunTitle`, body:
    "`Response.targetDistanceKm` km target → `Response.route.distanceKm` km loop,
    score `Response.route.score`. `Response.warnings` joined by newline."
15. **Get File** (the just-saved GPX) → **Share** → user taps **Runna** (or
    Files → Runna). This step is always interactive.

### Notes

- The function never throws on a checksum failure — it returns `checksum.ok:
  false` and the Shortcut decides (step 11).
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

To edit `start`, `hillsPreference`, or `greenPreference`, extend this Shortcut
with the same **Ask for Input → Set Dictionary Value → Save File** pattern, or
edit the JSON file directly in the Files app.

## Automation — daily unattended run

- **Shortcuts → Automation → New → Time of Day**
  - Time: e.g. 05:30
  - Repeat: Daily
  - **Run Immediately** (no "Run After Confirmation")
- Action: **Run Shortcut → Runna Route**.

Caveat: since iOS 17 (unchanged through iOS 26) a "Run Immediately" automation
fires with no confirmation tap, **but Apple always shows an unsuppressable
notification banner** while it runs. The final "share the GPX into Runna" step
(step 15) is an interactive share-sheet action regardless, so the pipeline is
"one tap in the morning", not fully hands-off. Treat the automation as a prompt
to open the notification and finish the hand-off.

## Manual verification checklist (out of band)

Not automated — confirm on the device after the function is deployed:

1. `GET https://runna-router.willsawyerrrr.dev/api/route?distanceKm=3&start=<lon>,<lat>`
   in a browser returns JSON with a `gpx` field.
2. Save that `gpx` to a `.gpx` file; open it — it should import as a route into a
   Runna workout (entry point: share sheet into Runna, or Runna's in-app file
   picker — verify which).
3. The route renders on the watch during a recorded run (watchOS ≥ 11).
4. A structured workout (warm-up / intervals / cool-down) still shows the route
   overlay, not just a plain run.
