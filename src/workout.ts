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
  /** min/km used to resolve this segment (duration→distance, and the checksum). */
  paceMinPerKm: number;
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
    /** Minutes from the header's `• NNm` (or `• NN-NNm` midpoint); `null` when absent. */
    statedMinutes: number | null;
    /** Kilometres from the header's `• NNkm`; `null` when absent. */
    statedKm: number | null;
    /** Σ durations + Σ (distance ÷ pace). */
    computedMinutes: number;
    /** `targetDistanceMeters / 1000`. */
    computedKm: number;
    /** Both stated values (when present) agree with the computed ones. */
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
  /^no (?:faster|slower) than\b/i,
  /^aim (?:for|to)\b/i,
];

const SECTION_HEADER = /^(warm[-\s]?up|session|cool[-\s]?down)\s*:?\s*$/i;
const REPEAT_MARKER = /^(?:repeat\s*[x×]\s*(\d+)|(\d+)\s*reps?\s+of\b:?)/i;

const KM = /(\d+(?:\.\d+)?)\s*km\b/;
const METRES = /(\d+)\s*m\b/;
const MINUTES = /(\d+)\s*min(?:s|utes?)?\b/;
const SECONDS = /(\d+)\s*s\b/;
/** An explicit pace like `4:25/km` or `5:20 / km`. */
const PACE_SPEC = /(\d{1,2}):(\d{2})\s*\/?\s*km/;
/** Words marking a running segment even without a configured pace phrase. */
const RUN_CUES =
  /\b(?:run|running|jog|tempo|threshold|interval|intervals|reps?|strides?|trial|effort|fartlek|progression|pace|fast|hard|sprint|surge)\b/;

/** A bare workout-name line (`5km Time Trial`, `Easy Run`) — a title, not a segment. */
const TITLE_NAME =
  /\b(?:time trial|easy run|long run|tempo(?: run)?|intervals?|interval session|fartlek|recovery run|progression run|threshold(?: run)?|hill (?:repeats?|session)|race|parkrun|steady(?: run)?|continuous run|walk run)\b/i;
/** Markers that make a line a segment even if it also names a workout type. */
const SEGMENT_MARKERS = /\bat\b|walk|\brest\b|\bmins?\b|\bsecs?\b|\d\s*s\b/i;

interface Classification {
  activity: Activity;
  paceMinPerKm: number;
  phrase?: string;
  /** false when the pace is a fallback guess, not configured or stated in the text. */
  paceKnown: boolean;
}

function classify(
  part: string,
  paces: Record<string, number>,
  fallbackRunPaceMinPerKm: number,
  warnings: string[],
): Classification {
  const spec = part.match(PACE_SPEC);
  const specPace = spec
    ? parseInt(spec[1]!, 10) + parseInt(spec[2]!, 10) / 60
    : null;

  if (/\bwalk|\brest\b/.test(part)) {
    const configured = paces["walking"];
    if (configured === undefined && specPace == null) {
      warnings.push(
        `No "walking" pace configured; using ${WALK_FALLBACK_MIN_PER_KM} min/km`,
      );
    }
    return {
      activity: "walk",
      paceMinPerKm: specPace ?? configured ?? WALK_FALLBACK_MIN_PER_KM,
      phrase: "walking",
      paceKnown: specPace != null || configured != null,
    };
  }

  const phrase = Object.keys(paces)
    .filter((k) => k !== "walking")
    .sort((a, b) => b.length - a.length)
    .find((k) => part.includes(k));
  if (phrase) {
    return {
      activity: "run",
      paceMinPerKm: specPace ?? paces[phrase]!,
      phrase,
      paceKnown: true,
    };
  }

  if (specPace != null) {
    return { activity: "run", paceMinPerKm: specPace, paceKnown: true };
  }

  const label = RUN_CUES.test(part) ? "pace" : "activity or pace";
  warnings.push(
    `No configured ${label} for "${part.trim()}"; using fallback ${fallbackRunPaceMinPerKm} min/km`,
  );
  return { activity: "run", paceMinPerKm: fallbackRunPaceMinPerKm, paceKnown: false };
}

interface PartResult {
  segment: Omit<Segment, "reps">;
  /** Minutes this part contributes to the duration checksum. */
  checksumMinutes: number;
  paceKnown: boolean;
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
  const seconds = minutes ? null : part.match(SECONDS);

  if (!km && !metres && !minutes && !seconds) {
    // Not a segment — a title, a coaching note, or a pace-only cue line.
    if (/\bat\b|\bwalk|\brest\b|pace/i.test(part)) {
      warnings.push(`"${rawPart.trim()}" has no distance or duration; skipped`);
    }
    return null;
  }

  const c = classify(part, paces, fallbackRunPaceMinPerKm, warnings);

  if (km || metres) {
    const meters = km
      ? Math.round(parseFloat(km[1]!) * 1000)
      : parseInt(metres![1]!, 10);
    return {
      segment: {
        activity: c.activity,
        source: "distance",
        meters,
        distanceMeters: meters,
        paceMinPerKm: c.paceMinPerKm,
        ...(c.phrase ? { phrase: c.phrase } : {}),
      },
      checksumMinutes: (meters / 1000) * c.paceMinPerKm,
      paceKnown: c.paceKnown,
    };
  }

  const secs = minutes
    ? parseInt(minutes[1]!, 10) * 60
    : parseInt(seconds![1]!, 10);
  return {
    segment: {
      activity: c.activity,
      source: "duration",
      seconds: secs,
      distanceMeters: (secs / 60 / c.paceMinPerKm) * 1000,
      paceMinPerKm: c.paceMinPerKm,
      ...(c.phrase ? { phrase: c.phrase } : {}),
    },
    checksumMinutes: secs / 60,
    paceKnown: c.paceKnown,
  };
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
  let anyAssumedPace = false;

  const header = lines.find((l) => l.length > 0) ?? "";
  // The first line is a title, not a segment, when it uses the `Type • … • …`
  // format, or names a workout type without reading like a segment.
  const isTitle =
    /\s•\s/.test(header) ||
    (TITLE_NAME.test(header) && !SEGMENT_MARKERS.test(header));
  const headerLine = isTitle ? header : undefined;

  const minMatch = header.match(/•\s*(\d+)\s*(?:-\s*(\d+)\s*)?m\b/);
  const statedMinutes = minMatch
    ? minMatch[2]
      ? Math.round((parseInt(minMatch[1]!, 10) + parseInt(minMatch[2], 10)) / 2)
      : parseInt(minMatch[1]!, 10)
    : null;
  const kmMatch = header.match(/•\s*(\d+(?:\.\d+)?)\s*km\b/);
  const statedKm = kmMatch ? parseFloat(kmMatch[1]!) : null;

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
      if (!result.paceKnown) anyAssumedPace = true;
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

  const targetDistanceMeters = segments.reduce(
    (sum, s) => sum + s.distanceMeters,
    0,
  );
  const computedKm = targetDistanceMeters / 1000;

  // The minutes check only bites when every pace was configured or stated —
  // a fallback guess makes the minute total unreliable, but the distance total
  // (from literal `Nkm` / `Nm` segments) is still trustworthy.
  const minutesOk =
    statedMinutes === null ||
    anyAssumedPace ||
    Math.abs(statedMinutes - computedMinutes) <= 3;
  const kmOk =
    statedKm === null ||
    Math.abs(statedKm - computedKm) <= Math.max(1, 0.15 * statedKm);

  return {
    segments,
    targetDistanceMeters,
    checksum: {
      statedMinutes,
      statedKm,
      computedMinutes,
      computedKm,
      ok: minutesOk && kmOk,
    },
    warnings,
  };
}
