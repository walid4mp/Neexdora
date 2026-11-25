// Pulls latest Shorts (<= 60 s) of active rows in public.reel_channels into public.reels_cache.
// Auth: x-cron-secret OR an admin user JWT.   Secret: YOUTUBE_API_KEY
import { admin, env, getCaller, handle, isCron, json } from "../_shared/common.ts";

const yt = async (path: string, params: Record<string, string>) => {
  const r = await fetch(`https://www.googleapis.com/youtube/v3/${path}?${new URLSearchParams({ ...params, key: env("YOUTUBE_API_KEY") })}`, { signal: AbortSignal.timeout(15000) });
  if (!r.ok) throw new Error(`youtube_${r.status}`);
  return r.json();
};
const secs = (iso: string) => { const m = iso.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/); return (+(m?.[1] ?? 0)) * 3600 + (+(m?.[2] ?? 0)) * 60 + (+(m?.[3] ?? 0)); };

handle(async (req) => {
  const db = admin();
  if (!isCron(req)) {
    const u = await getCaller(req); if (!u) return json({ error: "unauthorized" }, 401);
    const { data: ok } = await db.rpc("is_admin", { p_user_id: u.id, p_min_role: "admin" }); if (ok !== true) return json({ error: "forbidden" }, 403);
  }
  const { data: channels } = await db.from("reel_channels").select("id,youtube_channel_id,channel_name").eq("is_active", true);
  let added = 0;
  for (const ch of channels ?? []) {
    try {
      const c = await yt("channels", { part: "contentDetails,snippet", id: ch.youtube_channel_id });
      const item = c.items?.[0]; if (!item) continue;
      await db.from("reel_channels").update({ channel_name: item.snippet?.title ?? ch.channel_name, channel_avatar_url: item.snippet?.thumbnails?.default?.url }).eq("id", ch.id);
      const list = await yt("playlistItems", { part: "contentDetails", playlistId: item.contentDetails.relatedPlaylists.uploads, maxResults: "30" });
      const ids = (list.items ?? []).map((x: any) => x.contentDetails.videoId).join(",");
      if (!ids) continue;
      const vids = await yt("videos", { part: "snippet,contentDetails,statistics", id: ids });
      const rows = (vids.items ?? []).filter((v: any) => secs(v.contentDetails.duration) <= 60).map((v: any) => ({
        youtube_video_id: v.id, channel_id: ch.id, title: v.snippet.title, description: v.snippet.description?.slice(0, 500) ?? null,
        thumbnail_url: v.snippet.thumbnails?.high?.url ?? v.snippet.thumbnails?.default?.url ?? null,
        original_like_count: Number(v.statistics?.likeCount ?? 0), original_view_count: Number(v.statistics?.viewCount ?? 0),
        published_at: v.snippet.publishedAt, cached_at: new Date().toISOString(), category: v.snippet.categoryId ?? null,
      }));
      if (rows.length) { const { error } = await db.from("reels_cache").upsert(rows, { onConflict: "youtube_video_id" }); if (!error) added += rows.length; }
    } catch (e) { console.warn("[sync-reels] channel failed", ch.youtube_channel_id, String(e)); }
  }
  return json({ ok: true, upserted: added, channels: channels?.length ?? 0 });
});
