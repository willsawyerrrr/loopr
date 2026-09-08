import { decodePreview, renderMapPage } from "../src/preview.js";
import { getPreview } from "../src/preview-store.js";

function page(body: string, status: number): Response {
  return new Response(body, {
    status,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

function errorPage(message: string, status: number): Response {
  return page(
    `<!doctype html><meta charset="utf-8"><title>Route preview</title>` +
      `<body style="font:15px/1.5 -apple-system,system-ui,sans-serif;margin:3rem auto;max-width:28rem;padding:0 1rem">` +
      `<p>${message}</p><p style="color:#666">Generate the route again to get a fresh preview link.</p></body>`,
    status,
  );
}

/**
 * Renders the map page for a `previewUrl`. `?id=` looks the route up in the
 * key-value store (short link, 30-day TTL); `?r=` decodes an inline token
 * (the fallback used when no store is configured). Neither makes a Trail
 * Router call — the map is exactly the route `/api/route` returned.
 */
export async function GET(request: Request): Promise<Response> {
  const params = new URL(request.url).searchParams;
  const id = params.get("id");
  const token = params.get("r");

  if (id) {
    const data = await getPreview(id);
    return data
      ? page(renderMapPage(data), 200)
      : errorPage("This preview link has expired or was not found.", 404);
  }

  if (token) {
    try {
      return page(renderMapPage(decodePreview(token)), 200);
    } catch {
      return errorPage("This preview link is malformed.", 400);
    }
  }

  return errorPage("Missing preview id.", 400);
}
