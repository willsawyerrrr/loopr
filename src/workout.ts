import { DEFAULTS } from "./config.js";

export type Activity = "walk" | "run";

export interface Segment {
  activity: Activity;
  source: "duration" | "distance";
  /** Present when `source === "duration"`. */
  seconds?: number;
  /** Present when `source === "distance"`. */
  meters?: number;
  /** Resolved distance for this segment, in metres. */
  distanceMeters: number;
  /** Matched pace phrase, if any. */
  phrase?: string;
  /** Expansion factor already applied; always 1. */
  reps: number;
}

export interface ParsedWorkout {
  segments: Segment[];
  /** Σ `segment.distanceMeters`. */
  targetDistanceMeters: number;
  checksum: {
    /** From the `• NNm` header token; `null` when absent. */
    statedMinutes: number | null;
    /** Σ durations + Σ (distance ÷ pace). */
    computedMinutes: number;
    /** `true` when `statedMinutes` is null or within 2 minutes of `computedMinutes`. */
    ok: boolean;
  };
  warnings: string[];
}

const WALK_FALLBACK_MIN_PER_KM = 11.0;

const IGNORE_PATTERNS: RegExp[] = [
  /view in the runna app/i,
  /^📊/,
  /^summary\b/i,
  /^distance:/i,
  /^time:/i,
  /^avg pace:/i,
  /^lap\b/i,
];

const SECTION_HEADER = /^(warm[-\s]?up|session|cool[-\s]?down)\s*:?\s*$/i;
const REPEAT_MARKER = /^(?:repeat\s*[x×]\s*(\d+)|(\d+)\s*reps?\s+of\b:?)/i;

const KM = /(\d+(?:\.\d+)?)\s*km\b/;
const METRES = /(\d+)\s*m\b/;
const MINUTES = /(\d+)\s*min(?:s|utes?)?\b/;
const SECONDS = /(\d+)\s*s\b/;

interface PartResult {
  segment: Omit<Segment, "reps">;
  /** Minutes this part contributes to the duration checksum. */
  checksumMinutes: number;
}

function resolvePace(
  part: string,
  paces: Record<string, number>,
  fallbackRunPaceMinPerKm: number,
  warnings: string[],
): { activity: Activity; phrase?: string; paceMinPerKm: number } | null {
  if (part.includes("walk")) {
    const paceMinPerKm = paces["walking"] ?? WALK_FALLBACK_MIN_PER_KM;
    if (paces["walking"] === undefined) {
      warnings.push(`No "walking" pace configured; using ${WALK_FALLBACK_MIN_PER_KM} min/km`);
    }
    return { activity: "walk", phrase: "walking", paceMinPerKm };
  }

  const phrase = Object.keys(paces)
    .filter((k) => k !== "walking")
    .sort((a, b) => b.length - a.length)
    .find((k) => part.includes(k));
  if (phrase) {
    return { activity: "run", phrase, paceMinPerKm: paces[phrase]! };
  }

  if (part.includes("run") || part.includes("jog")) {
    warnings.push(
      `Unknown run pace phrase in "${part.trim()}"; using fallback ${fallbackRunPaceMinPerKm} min/km`,
    );
    return { activity: "run", paceMinPerKm: fallbackRunPaceMinPerKm };
  }

  return null;
}

function parsePart(
  rawPart: string,
  paces: Record<string, number>,
  fallbackRunPaceMinPerKm: number,
  warnings: string[],
): PartResult | null {
  const part = rawPart.toLowerCase().trim();
  if (!part) return null;

  const km = part.match(KM);
  const metres = km ? null : part.match(METRES);
  const minutes = part.match(MINUTES);
  const seconds = part.match(SECONDS);

  const pace = resolvePace(part, paces, fallbackRunPaceMinPerKm, warnings);
  if (!pace) {
    warnings.push(`Could not classify segment part "${rawPart.trim()}"; skipped`);
    return null;
  }

  if (km || metres) {
    const meters = km ? Math.round(parseFloat(km[1]!) * 1000) : parseInt(metres![1]!, 10);
    return {
      segment: {
        activity: pace.activity,
        source: "distance",
        meters,
        distanceMeters: meters,
        ...(pace.phrase ? { phrase: pace.phrase } : {}),
      },
      checksumMinutes: (meters / 1000) * pace.paceMinPerKm,
    };
  }

  if (minutes || seconds) {
    const secs = minutes ? parseInt(minutes[1]!, 10) * 60 : parseInt(seconds![1]!, 10);
    const distanceMeters = (secs / 60 / pace.paceMinPerKm) * 1000;
    return {
      segment: {
        activity: pace.activity,
        source: "duration",
        seconds: secs,
        distanceMeters,
        ...(pace.phrase ? { phrase: pace.phrase } : {}),
      },
      checksumMinutes: secs / 60,
    };
  }

  warnings.push(`No duration or distance in segment part "${rawPart.trim()}"; skipped`);
  return null;
}

export function parseWorkout(
  text: string,
  paces: Record<string, number>,
  opts?: { fallbackRunPaceMinPerKm?: number },
): ParsedWorkout {
  const fallbackRunPaceMinPerKm =
    opts?.fallbackRunPaceMinPerKm ?? DEFAULTS.fallbackRunPaceMinPerKm;
  const lines = text.split(/\r?\n/).map((l) => l.trim());
  const warnings: string[] = [];
  const segments: Segment[] = [];
  let computedMinutes = 0;

  const firstNonEmpty = lines.find((l) => l.length > 0);
  const statedMatch = firstNonEmpty?.match(/•\s*(\d+)\s*m\b/);
  const statedMinutes = statedMatch ? parseInt(statedMatch[1]!, 10) : null;
  // Only a line carrying the `• NNm` token is demonstrably a title/checksum
  // line and safe to skip; otherwise the first line is a real segment.
  const headerLine = statedMatch ? firstNonEmpty : undefined;

  let pendingReps = 1;
  let inRepeat = false;
  let headerSeen = false;

  for (const line of lines) {
    if (line === "") {
      inRepeat = false;
      pendingReps = 1;
      continue;
    }
    if (!headerSeen && headerLine !== undefined && line === headerLine) {
      headerSeen = true;
      continue;
    }
    if (IGNORE_PATTERNS.some((re) => re.test(line))) continue;
    if (SECTION_HEADER.test(line)) {
      inRepeat = false;
      pendingReps = 1;
      continue;
    }

    const repeat = line.match(REPEAT_MARKER);
    if (repeat) {
      pendingReps = parseInt(repeat[1] ?? repeat[2]!, 10);
      inRepeat = true;
      continue;
    }

    const isBullet = line.startsWith("•");
    const reps = inRepeat && isBullet ? pendingReps : 1;
    const content = line.replace(/^•\s*/, "");

    for (const rawPart of content.split(",")) {
      const result = parsePart(rawPart, paces, fallbackRunPaceMinPerKm, warnings);
      if (!result) continue;
      for (let r = 0; r < reps; r++) {
        segments.push({ ...result.segment, reps: 1 });
        computedMinutes += result.checksumMinutes;
      }
    }

    if (!isBullet) {
      inRepeat = false;
      pendingReps = 1;
    }
  }

  if (segments.length === 0) {
    warnings.push("No segments parsed from workout text");
  }

  const targetDistanceMeters = segments.reduce((sum, s) => sum + s.distanceMeters, 0);
  const ok = statedMinutes === null || Math.abs(statedMinutes - computedMinutes) <= 2;

  return {
    segments,
    targetDistanceMeters,
    checksum: { statedMinutes, computedMinutes, ok },
    warnings,
  };
}
