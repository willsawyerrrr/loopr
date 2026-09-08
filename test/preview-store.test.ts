import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { PreviewData } from "../src/preview.js";

const backing = new Map<string, unknown>();

vi.mock("@upstash/redis", () => ({
  Redis: class {
    async set(k: string, v: unknown): Promise<void> {
      backing.set(k, v);
    }
    async get(k: string): Promise<unknown> {
      return backing.get(k) ?? null;
    }
  },
}));

const DATA: PreviewData = {
  name: "Walk Run",
  latlngs: [
    [51.5, -0.12],
    [51.51, -0.13],
  ],
  target: 3.2,
  route: {
    distanceKm: 3.18,
    ascentM: 60,
    descentM: 60,
    elevationGainPerKm: 18.9,
    hilliness: "rolling",
    greenScore: 0.4,
  },
  warnings: [],
};

beforeEach(() => {
  backing.clear();
  vi.resetModules();
});

afterEach(() => {
  vi.unstubAllEnvs();
});

async function load(env: Record<string, string | undefined>) {
  for (const [k, v] of Object.entries(env)) vi.stubEnv(k, v);
  return import("../src/preview-store.js");
}

describe("preview-store — configured", () => {
  it("round-trips a preview under a 12-hex id", async () => {
    const s = await load({ KV_REST_API_URL: "https://x", KV_REST_API_TOKEN: "t" });
    expect(s.previewStoreAvailable).toBe(true);

    const id = await s.putPreview(DATA);
    expect(id).toMatch(/^[0-9a-f]{12}$/);
    expect(await s.getPreview(id!)).toEqual(DATA);
  });

  it("also reads the UPSTASH_* variable names", async () => {
    const s = await load({
      UPSTASH_REDIS_REST_URL: "https://x",
      UPSTASH_REDIS_REST_TOKEN: "t",
    });
    expect(s.previewStoreAvailable).toBe(true);
  });

  it("returns null for a malformed or unknown id", async () => {
    const s = await load({ KV_REST_API_URL: "https://x", KV_REST_API_TOKEN: "t" });
    expect(await s.getPreview("nope")).toBeNull();
    expect(await s.getPreview("0123456789ab")).toBeNull();
  });
});

describe("preview-store — not configured", () => {
  it("is unavailable and never stores", async () => {
    const s = await load({
      KV_REST_API_URL: undefined,
      KV_REST_API_TOKEN: undefined,
      UPSTASH_REDIS_REST_URL: undefined,
      UPSTASH_REDIS_REST_TOKEN: undefined,
    });
    expect(s.previewStoreAvailable).toBe(false);
    expect(await s.putPreview(DATA)).toBeNull();
    expect(await s.getPreview("0123456789ab")).toBeNull();
  });
});
