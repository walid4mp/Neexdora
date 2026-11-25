// { url } → { data: { title, description, image_url, domain } }   (SSRF-safe, 1 MB cap, 8 s timeout)
import { getCaller, handle, json } from "../_shared/common.ts";

const BLOCKED = /^(localhost|.*\.local|.*\.internal|metadata\.google\.internal)$/i;
const isPrivateIp = (h: string) =>
  /^(10\.|127\.|0\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|::1$|fc|fd|fe80)/i.test(h);

const meta = (html: string, keys: string[]) => {
  for (const k of keys) {
    const re = new RegExp(`<meta[^>]+(?:property|name)=["']${k}["'][^>]*content=["']([^"']*)["']|<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']${k}["']`, "i");
    const m = html.match(re); const v = (m?.[1] ?? m?.[2])?.trim(); if (v) return decode(v);
  }
  return null;
};
const decode = (s: string) => s.replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">");

handle(async (req) => {
  if (!(await getCaller(req))) return json({ error: "unauthorized" }, 401);
  const { url } = await req.json();
  let u: URL; try { u = new URL(String(url)); } catch { return json({ data: null }); }
  if (!/^https?:$/.test(u.protocol) || BLOCKED.test(u.hostname) || isPrivateIp(u.hostname)) return json({ data: null });

  const res = await fetch(u, { redirect: "follow", signal: AbortSignal.timeout(8000), headers: { "User-Agent": "Mozilla/5.0 (compatible; NexoraLinkPreview/1.0)", Accept: "text/html" } });
  const final = new URL(res.url);
  if (BLOCKED.test(final.hostname) || isPrivateIp(final.hostname)) return json({ data: null });
  const ct = res.headers.get("content-type") ?? "";
  if (!res.ok || !ct.includes("text/html")) return json({ data: null });
  const reader = res.body!.getReader(); let html = "", size = 0; const dec = new TextDecoder();
  while (size < 1_000_000) { const { done, value } = await reader.read(); if (done) break; size += value.length; html += dec.decode(value, { stream: true }); if (/<\/head>/i.test(html)) break; }
  await reader.cancel().catch(() => {});

  const title = meta(html, ["og:title", "twitter:title"]) ?? decode(html.match(/<title[^>]*>([^<]*)<\/title>/i)?.[1]?.trim() ?? "");
  let image = meta(html, ["og:image", "twitter:image"]);
  if (image) { try { image = new URL(image, final).toString(); } catch { image = null; } }
  return json({ data: { title: title || null, description: meta(html, ["og:description", "twitter:description", "description"]), image_url: image, domain: final.hostname.replace(/^www\./, "") } });
});
