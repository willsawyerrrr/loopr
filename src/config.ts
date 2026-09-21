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
} as const;

export const DEFAULT_PACES: Record<string, number> = {
  walking: 11.0,
  "conversational pace": 7.5,
};
