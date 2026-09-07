import { describe, expect, it } from "vitest";
import { DEFAULT_PACES } from "../src/config.js";
import { parseWorkout } from "../src/workout.js";

const SAMPLE_A = `Walk Run • 29m • 29m

5 mins walking warm up

4 reps of:
• 60s at a conversational pace, 30s walking
• 2 mins at a conversational pace, 60s walking

60s at a conversational pace

5 mins walking cool down`;

const SAMPLE_B = `Your First Continuous Run

5 mins walking warm up

750m at a conversational pace

5 mins walking cool down`;

describe("parseWorkout — Sample A", () => {
  const parsed = parseWorkout(SAMPLE_A, DEFAULT_PACES);

  it("expands the repeat block", () => {
    // warm-up + 4×(2 bullet lines × 2 parts) + tail run + cool-down
    expect(parsed.segments).toHaveLength(1 + 4 * 4 + 1 + 1);
  });

  it("splits comma-separated bullet parts", () => {
    const runReps = parsed.segments.filter(
      (s) => s.activity === "run" && s.seconds === 60,
    );
    // one per rep, plus the standalone 60s run
    expect(runReps).toHaveLength(5);
  });

  it("computes ~3.2 km at default paces", () => {
    expect(parsed.targetDistanceMeters).toBeGreaterThan(3100);
    expect(parsed.targetDistanceMeters).toBeLessThan(3300);
  });

  it("passes the stated-minutes checksum", () => {
    expect(parsed.checksum.statedMinutes).toBe(29);
    expect(parsed.checksum.computedMinutes).toBeCloseTo(29, 5);
    expect(parsed.checksum.ok).toBe(true);
  });

  it("has no warnings", () => {
    expect(parsed.warnings).toEqual([]);
  });
});

describe("parseWorkout — Sample B", () => {
  const parsed = parseWorkout(SAMPLE_B, DEFAULT_PACES);

  it("mixes duration and distance segments", () => {
    expect(parsed.segments.map((s) => s.source)).toEqual([
      "duration",
      "distance",
      "duration",
    ]);
    expect(parsed.segments[1]!.meters).toBe(750);
  });

  it("computes ~1.65 km", () => {
    expect(parsed.targetDistanceMeters).toBeGreaterThan(1550);
    expect(parsed.targetDistanceMeters).toBeLessThan(1750);
  });

  it("has no stated checksum and is ok", () => {
    expect(parsed.checksum.statedMinutes).toBeNull();
    expect(parsed.checksum.ok).toBe(true);
  });
});

describe("parseWorkout — headerless continuous run", () => {
  const parsed = parseWorkout(
    `5 mins walking warm up\n\n750m at a conversational pace\n\n5 mins walking cool down`,
    DEFAULT_PACES,
  );

  it("parses the first line when there is no title", () => {
    expect(parsed.segments.map((s) => s.source)).toEqual([
      "duration",
      "distance",
      "duration",
    ]);
    expect(parsed.targetDistanceMeters).toBeGreaterThan(1550);
    expect(parsed.targetDistanceMeters).toBeLessThan(1750);
  });

  it("has no stated checksum and no warnings", () => {
    expect(parsed.checksum.statedMinutes).toBeNull();
    expect(parsed.warnings).toEqual([]);
  });
});

describe("parseWorkout — repeat markers", () => {
  it("handles `Repeat xN`", () => {
    const parsed = parseWorkout(
      `Intervals • 12m\n\nRepeat x3\n• 2 mins at a conversational pace, 60s walking`,
      DEFAULT_PACES,
    );
    expect(parsed.segments).toHaveLength(6);
  });
});

describe("parseWorkout — unknown pace phrase", () => {
  const parsed = parseWorkout(
    `Easy Run\n\n5 mins at an easy running pace`,
    DEFAULT_PACES,
  );

  it("falls back and warns", () => {
    expect(parsed.segments).toHaveLength(1);
    expect(parsed.segments[0]!.activity).toBe("run");
    expect(parsed.warnings.some((w) => w.includes("fallback"))).toBe(true);
  });

  it("uses the fallback pace (7.5 min/km → ~667 m for 5 min)", () => {
    expect(parsed.segments[0]!.distanceMeters).toBeCloseTo((5 / 7.5) * 1000, 5);
  });
});

describe("parseWorkout — checksum mismatch", () => {
  it("reports ok=false when stated and computed diverge", () => {
    const parsed = parseWorkout(
      `Walk Run • 29m\n\n5 mins walking warm up\n\n5 mins walking cool down`,
      DEFAULT_PACES,
    );
    expect(parsed.checksum.statedMinutes).toBe(29);
    expect(parsed.checksum.computedMinutes).toBeCloseTo(10, 5);
    expect(parsed.checksum.ok).toBe(false);
  });
});

describe("parseWorkout — empty input", () => {
  it("returns no segments and warns", () => {
    const parsed = parseWorkout("", DEFAULT_PACES);
    expect(parsed.segments).toEqual([]);
    expect(parsed.targetDistanceMeters).toBe(0);
    expect(parsed.warnings).toContain("No segments parsed from workout text");
  });
});
