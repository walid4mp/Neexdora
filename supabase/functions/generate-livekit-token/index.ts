// Body: { roomName, participantName, effectiveTimeInSeconds } → { token, url }
// Secrets: LIVEKIT_URL (wss://...), LIVEKIT_API_KEY, LIVEKIT_API_SECRET
import { AccessToken } from "npm:livekit-server-sdk@2";
import { admin, env, getCaller, handle, isSanctioned, json } from "../_shared/common.ts";

handle(async (req) => {
  const user = await getCaller(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  if (await isSanctioned(user.id)) return json({ error: "account_sanctioned" }, 403);

  const { roomName, participantName, effectiveTimeInSeconds } = await req.json();
  const room = String(roomName ?? "").slice(0, 128);
  if (!room) return json({ error: "missing_roomName" }, 400);
  const ttl = Math.min(Math.max(Number(effectiveTimeInSeconds) || 3600, 60), 6 * 3600);

  // Only call participants / group members may obtain a token for the room.
  const db = admin();
  const { data: c } = await db.from("calls").select("caller_id,receiver_id").eq("call_id", room).maybeSingle();
  let allowed = !!c && (c.caller_id === user.id || c.receiver_id === user.id);
  if (!allowed) {
    const { data: gc } = await db.from("group_calls").select("group_id").eq("call_id", room).order("started_at", { ascending: false }).limit(1).maybeSingle();
    if (gc) { const { data: m } = await db.rpc("is_group_member", { p_group_id: gc.group_id, p_user_id: user.id }); allowed = m === true; }
  }
  if (!allowed) return json({ error: "forbidden_room" }, 403);

  const at = new AccessToken(env("LIVEKIT_API_KEY"), env("LIVEKIT_API_SECRET"), {
    identity: user.id, name: String(participantName ?? "").slice(0, 80) || user.id, ttl,
  });
  at.addGrant({ roomJoin: true, room, canPublish: true, canSubscribe: true, canPublishData: true });
  return json({ token: await at.toJwt(), url: env("LIVEKIT_URL") });
});
