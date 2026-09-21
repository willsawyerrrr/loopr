export interface RouteConfig {
  /** Route start as `[lon, lat]`. Supplied per request (the Shortcut sends the device's current location); never stored. */
  start: [number, number];
  /** Trail Router hills preference, -1..1. Defaults to `DEFAULTS.hillsPreference`. */
  hillsPreference?: number;
  /** Trail Router green preference, 0..1. Defaults to `DEFAULTS.greenPreference`. */
  greenPreference?: number;
  /** Pace phrase (lowercased) → minutes per km. */
  paces: Record<string, number>;
}

export const DEFAULTS = {
  hillsPreference: 0,
  greenPreference: 0,
  avoidRepetition: true,
  avoidUnsafeStreets: true,
  avoidUnlitStreets: true,
  /** Minutes per km applied when a run phrase is not in `paces`. */
  fallbackRunPaceMinPerKm: 7.5,
  /** Fraction of the target distance a candidate may differ by and still be eligible for a seeded (`variant > 0`) pick. */
  variantTolerance: 0.05,
  /** Bounds, in metres, of the seeded offset applied to the start when asking Trail Router for a `variant > 0` route. */
  variantNudgeMeters: { min: 40, max: 120 },
  /** Route steering (`waypoints` / `heading`). */
  guided: {
    maxWaypoints: 3,
    /** A pin may be at most this fraction of the target distance from the start. */
    pinRadiusFactor: 0.75,
    /** Fraction of the target the final route may differ by without a warning. */
    tolerance: 0.07,
    /** Fraction of the target at which tuning stops early. */
    goodEnough: 0.04,
    maxRequests: 8,
    /** Wall-clock budget for all Trail Router requests of one route, in milliseconds. */
    timeBudgetMs: 15_000,
    /** Route length over straight-line anchor length, assumed before a measurement exists. */
    assumedRouteFactor: 1.25,
    /** Half-angle, in degrees, between the two anchors of a heading-only triangle loop. */
    headingSpreadDegrees: 35,
    /** A route further than this from a pin, in metres, draws a warning. */
    pinMissMeters: 100,
  },
} as const;

export const DEFAULT_PACES: Record<string, number> = {
  walking: 11.0,
  "conversational pace": 7.5,
};
