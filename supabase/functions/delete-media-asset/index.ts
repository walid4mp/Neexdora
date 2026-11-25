// { table, id }  → deletes Cloudinary assets of the row (owner/admin only) then the row.
// { mode:'raw', publicIds, resourceType } → deletes given assets that belong to the caller's own uploads.
// { mode:'queue' } (x-cron-secret) → flushes public.media_cleanup_queue.
// Secrets: CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET
import { admin, env, getCaller, handle, isCron, json } from "../_shared/common.ts";

const TABLES: Record<string, { owner: string; cols: Record<string, "image" | "video" | "raw"> }> = {
  posts: { owner: "author_id", cols: { image_public_id: "image", video_public_id: "video", file_public_id: "raw" } },
  stories: { owner: "author_id", cols: { image_public_id: "image", video_public_id: "video" } },
  messages: { owner: "sender_id", cols: { image_public_id: "image", video_public_id: "video", voice_public_id: "video", file_public_id: "raw" } },
  group_messages: { owner: "sender_id", cols: { image_public_id: "image", video_public_id: "video", voice_public_id: "video", file_public_id: "raw" } },
  comments: { owner: "author_id", cols: { image_public_id: "image", video_public_id: "video", voice_public_id: "video", file_public_id: "raw" } },
};

async function sha1(s: string) {
  const b = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

async function destroy(publicId: string, type: string): Promise<boolean> {
  const cloud = env("CLOUDINARY_CLOUD_NAME"), key = env("CLOUDINARY_API_KEY"), secret = env("CLOUDINARY_API_SECRET");
  const ts = Math.floor(Date.now() / 1000);
  const signature = await sha1(`invalidate=true&public_id=${publicId}&timestamp=${ts}${secret}`);
  const res = await fetch(`https://api.cloudinary.com/v1_1/${cloud}/${type}/destroy`, {
    method: "POST", body: new URLSearchParams({ public_id: publicId, timestamp: String(ts), api_key: key, signature, invalidate: "true" }),
  });
  const j = await res.json().catch(() => ({}));
  return res.ok && (j.result === "ok" || j.result === "not found");
}

handle(async (req) => {
  const body = await req.json();
  const db = admin();

  if (body.mode === "queue") {
    if (!isCron(req)) return json({ error: "forbidden" }, 403);
    const { data: rows } = await db.from("media_cleanup_queue").select("id,public_id,resource_type").order("id").limit(200);
    let done = 0;
    for (const r of rows ?? []) { if (await destroy(r.public_id, r.resource_type)) { await db.from("media_cleanup_queue").delete().eq("id", r.id); done++; } }
    return json({ ok: true, processed: done });
  }

  const user = await getCaller(req);
  if (!user) return json({ error: "unauthorized" }, 401);

  if (body.mode === "raw") {
    const type = ["image", "video", "raw"].includes(body.resourceType) ? body.resourceType : "raw";
    const ids: string[] = (Array.isArray(body.publicIds) ? body.publicIds : []).map(String).slice(0, 50);
    // only assets uploaded under the caller's own folder prefix may be deleted this way
    const mine = ids.filter((id) => id.includes(user.id));
    let n = 0; for (const id of mine) if (await destroy(id, type)) n++;
    return json({ ok: true, deleted: n, skipped: ids.length - mine.length });
  }

  const spec = TABLES[String(body.table)];
  if (!spec || !body.id) return json({ error: "invalid_request" }, 400);
  const { data: row } = await db.from(String(body.table)).select(`${spec.owner},${Object.keys(spec.cols).join(",")}`).eq("id", body.id).maybeSingle();
  if (!row) return json({ ok: true, note: "already_deleted" });
  const { data: isAdm } = await db.rpc("is_admin", { p_user_id: user.id, p_min_role: "moderator" });
  if ((row as any)[spec.owner] !== user.id && isAdm !== true) return json({ error: "forbidden" }, 403);

  for (const [col, type] of Object.entries(spec.cols)) {
    const pid = (row as any)[col];
    if (pid && !(await destroy(pid, type))) await db.from("media_cleanup_queue").insert({ public_id: pid, resource_type: type }); // retry later
  }
  const { error } = await db.from(String(body.table)).delete().eq("id", body.id);
  if (error) return json({ error: "delete_failed" }, 500);
  return json({ ok: true });
});
