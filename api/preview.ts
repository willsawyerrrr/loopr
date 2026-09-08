import { decodePreview, renderMapPage } from "../src/preview.js";

/**
 * Renders the map page for a `previewUrl` token issued by `/api/route`. The
 * token carries the exact chosen route, so this shows precisely what was saved
 * — no second Trail Router call.
 */
export async function GET(request: Request): Promise<Response> {
  const token = new URL(request.url).searchParams.get("r");
  if (!token) {
    return new Response("Missing `r` preview token", { status: 400 });
  }
  let html: string;
  try {
    html = renderMapPage(decodePreview(token));
  } catch {
    return new Response("Malformed preview token", { status: 400 });
  }
  return new Response(html, {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}
