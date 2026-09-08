import { randomBytes } from "node:crypto";
import { Redis } from "@upstash/redis";
import type { PreviewData } from "./preview.js";

const REST_URL = process.env["KV_REST_API_URL"] ?? process.env["UPSTASH_REDIS_REST_URL"];
const REST_TOKEN =
  process.env["KV_REST_API_TOKEN"] ?? process.env["UPSTASH_REDIS_REST_TOKEN"];

const redis: Redis | null =
  REST_URL && REST_TOKEN ? new Redis({ url: REST_URL, token: REST_TOKEN }) : null;

/** Whether a key-value store is configured. When false, callers fall back to the inline token. */
export const previewStoreAvailable = redis !== null;

const TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days
const ID = /^[0-9a-f]{12}$/;
const key = (id: string): string => `preview:${id}`;

function newId(): string {
  return randomBytes(6).toString("hex");
}

/**
 * Store a route preview and return its short id, or `null` when no store is
 * configured or the write fails — never throws, so route generation is unaffected.
 */
export async function putPreview(data: PreviewData): Promise<string | null> {
  if (!redis) return null;
  const id = newId();
  try {
    await redis.set(key(id), data, { ex: TTL_SECONDS });
    return id;
  } catch {
    return null;
  }
}

/** Fetch a stored preview by id, or `null` if the store is off, the id is malformed, or it has expired. */
export async function getPreview(id: string): Promise<PreviewData | null> {
  if (!redis || !ID.test(id)) return null;
  try {
    return (await redis.get<PreviewData>(key(id))) ?? null;
  } catch {
    return null;
  }
}
