// POST body = payload built by lib/core/services/fcm_services.dart  (type + receiverFcmToken + ...).
// Internal callers (DB triggers / admin-action) authenticate with x-cron-secret and may pass receiverId instead.
import { admin, getCaller, handle, isCron, isSanctioned, json } from "../_shared/common.ts";
import { sendFcm } from "../_shared/fcm.ts";

const TYPE_MAP: Record<string, string> = {
  chat: "chat", story_reply: "chat", call: "incoming_call", group: "group_message", group_call: "incoming_group_call",
};
const CANCEL = new Set(["call_cancelled", "group_call_cancelled"]);
const CALLS = new Set(["call", "group_call"]);
const ACTOR_KEYS = ["senderId", "actorId", "requesterId", "followerId", "accepterId", "callerId", "initiatorId"];

const display = (t: string, type: string) => {
  switch (type) {
    case "image": return t ? `📷 ${t}` : "📷 Photo";
    case "video": return t ? `🎥 ${t}` : "🎥 Video";
    case "voice": return "🎤 Voice message";
    case "gif": return t ? `🎞️ ${t}` : "🎞️ GIF";
    case "sticker": return t ? `😊 ${t}` : "😊 Sticker";
    case "call": return "📞 Missed call";
    default: return t;
  }
};

handle(async (req) => {
  const internal = isCron(req);
  const caller = internal ? null : await getCaller(req);
  if (!internal && !caller) return json({ ok: false, error: "unauthorized" }, 401);

  const p = (await req.json()) as Record<string, unknown>;
  const type = String(p.type ?? "");
  if (!type) return json({ ok: false, error: "missing_type" }, 400);

  const db = admin();
  // --- resolve + validate receiver ------------------------------------------------
  let token = String(p.receiverFcmToken ?? "");
  let receiverId = String(p.receiverId ?? "");
  let receiver: { id: string; fcm_token: string | null; notif_push: boolean; notif_calls: boolean; is_deleted: boolean } | null = null;
  if (token) {
    const { data } = await db.from("users").select("id,fcm_token,notif_push,notif_calls,is_deleted").eq("fcm_token", token).maybeSingle();
    receiver = data;
  } else if (receiverId) {
    const { data } = await db.from("users").select("id,fcm_token,notif_push,notif_calls,is_deleted").eq("id", receiverId).maybeSingle();
    receiver = data; token = data?.fcm_token ?? "";
  }
  if (!receiver || !token || receiver.is_deleted) return json({ ok: true, skipped: "no_target" });
  receiverId = receiver.id;

  // --- caller checks (anti-spoofing / abuse) --------------------------------------
  if (caller) {
    for (const k of ACTOR_KEYS) if (p[k] && String(p[k]) !== caller.id) return json({ ok: false, error: "actor_mismatch" }, 403);
    if (await isSanctioned(caller.id)) return json({ ok: false, error: "account_sanctioned" }, 403);
    const { data: blocked } = await db.rpc("is_blocked_between", { a: caller.id, b: receiverId });
    if (blocked === true) return json({ ok: true, skipped: "blocked" });
    if (caller.id === receiverId && !CANCEL.has(type)) return json({ ok: true, skipped: "self" });
  }

  // --- server-side preference gates (cancel signals always pass) -------------------
  if (!CANCEL.has(type)) {
    if (!receiver.notif_push) return json({ ok: true, skipped: "push_disabled" });
    if (CALLS.has(type) && !receiver.notif_calls) return json({ ok: true, skipped: "calls_disabled" });
    if (type === "chat" || type === "group") {
      const peer = String(p.senderId ?? "");
      const { data: muted } = await db.rpc("is_chat_muted", { p_owner: receiverId, p_peer: peer });
      if (muted === true && type === "chat") return json({ ok: true, skipped: "muted" });
    }
  }

  // --- build data payload (all values must be strings) -----------------------------
  const data: Record<string, string> = {};
  for (const [k, v] of Object.entries(p)) {
    if (k === "receiverFcmToken" || v === null || v === undefined) continue;
    data[k] = typeof v === "string" ? v : String(v);
  }
  delete data.type;
  data.notificationType = TYPE_MAP[type] ?? type;
  if (type === "chat" || type === "group" || type === "story_reply") data.messageBody = display(String(p.messageBody ?? ""), String(p.messageType ?? "text"));
  if (type === "call") { data.supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""; data.supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? ""; }
  if (type === "group_call") { data.supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""; data.supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? ""; }

  const isRing = type === "call" || type === "group_call";
  const r = await sendFcm(token, data, {
    ttl: isRing ? "30s" : CANCEL.has(type) ? "30s" : "60s",
    voip: type === "call",
    alert: type === "call" ? { title: String(p.callerName ?? ""), body: p.callType === "video" ? "Incoming video call..." : "Incoming voice call..." } : undefined,
  });
  if (r.unregistered) await db.from("users").update({ fcm_token: null }).eq("id", receiverId).eq("fcm_token", token);
  return json({ ok: r.ok, status: r.status });
});
