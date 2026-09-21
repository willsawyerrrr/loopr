import { describe, expect, it } from "vitest";
import { DEFAULT_PACES } from "../src/config.js";
import { parseWorkout } from "../src/workout.js";

// The Notes-style text the iOS app builds from OCR of a Runna workout screen. The same strings are the
// expected output of `ScreenReadingTests` in ios/RouteKit; the app sends them as `workout`.
const CONTINUOUS_RUN = `5 mins walking warm up

2km at a conversational pace

5 mins walking cool down`;

const WALK_RUN = `5 mins walking warm up

2 reps of:
• 1.25km at a conversational pace
• 60s walking

5 mins walking cool down`;

const TIMED_WALK_RUN = `5 mins walking warm up

4 reps of:
• 60s at a conversational pace
• 30s walking
• 2 mins at a conversational pace
• 60s walking

60s at a conversational pace

5 mins walking cool down`;

const km = (m: number): number => Math.round(m) / 1000;

describe("parseWorkout — text read from a screenshot", () => {
  it("continuous run: 2 km run plus 10 min walking", () => {
    const parsed = parseWorkout(CONTINUOUS_RUN, DEFAULT_PACES);
    expect(parsed.segments.map((s) => s.activity)).toEqual(["walk", "run", "walk"]);
    expect(parsed.segments[1]!.meters).toBe(2000);
    expect(km(parsed.targetDistanceMeters)).toBeCloseTo(2 + 10 / 11, 2);
    expect(parsed.checksum.ok).toBe(true);
    expect(parsed.warnings).toEqual([]);
  });

  it("walk-run with a repeat: 2 × 1.25 km run, 2 × 60 s walk, 10 min walk", () => {
    const parsed = parseWorkout(WALK_RUN, DEFAULT_PACES);
    const run = parsed.segments.filter((s) => s.activity === "run");
    const walk = parsed.segments.filter((s) => s.activity === "walk");
    expect(run.map((s) => s.meters)).toEqual([1250, 1250]);
    expect(walk.map((s) => s.seconds)).toEqual([300, 60, 60, 300]);
    expect(km(parsed.targetDistanceMeters)).toBeCloseTo(2.5 + (10 + 2) / 11, 2);
    expect(parsed.checksum.ok).toBe(true);
    expect(parsed.warnings).toEqual([]);
  });

  it("time-based walk-run with no stated total matches Sample A's structure", () => {
    const parsed = parseWorkout(TIMED_WALK_RUN, DEFAULT_PACES);
    expect(parsed.segments).toHaveLength(1 + 4 * 4 + 1 + 1);
    expect(parsed.targetDistanceMeters).toBeGreaterThan(3100);
    expect(parsed.targetDistanceMeters).toBeLessThan(3300);
    expect(parsed.checksum.statedMinutes).toBeNull();
    expect(parsed.checksum.statedKm).toBeNull();
    expect(parsed.checksum.ok).toBe(true);
    expect(parsed.warnings).toEqual([]);
  });
});
