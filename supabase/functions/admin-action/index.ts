// Admin/moderator API. Authorization is enforced INSIDE Postgres (rpc as the caller): is_admin() checks the JWT user.
// Body: { action:'ban'|'suspend'|'warn'|'unban'|'resolve_report'|'set_role', ... }
import { admin, asCaller, getCaller, handle, json } from "../_shared/common.ts";
import { sendFcm } from "../_shared/fcm.ts";

handle(async (req) => {
  const me = await getCaller(req); if (!me) return json({ ok: false, error: "unauthorized" }, 401);
  const b = await req.json(); const db = asCaller(req); const svc = admin();
  const notify = async (uid: string, title: string, body: string) => {
    const { data: u } = await svc.from("users").select("fcm_token").eq("id", uid).maybeSingle();
    if (u?.fcm_token) await sendFcm(u.fcm_token, { notificationType: "feedback_reply", title, body, feedbackId: "" }).catch(() => {});
  };
  switch (b.action) {
    case "ban": case "suspend": case "warn": {
      const kind = b.action === "ban" ? "ban" : b.action === "suspend" ? "suspension" : "warning";
      const { data, error } = await db.rpc("admin_apply_sanction", { p_user_id: b.userId, p_kind: kind, p_reason: b.reason, p_duration_hours: b.durationHours ?? null });
      if (error) return json({ ok: false, error: error.message }, 400);
      await notify(b.userId, kind === "warning" ? "Warning" : kind === "ban" ? "Account banned" : "Account suspended", String(b.reason ?? ""));
      return json({ ok: true, sanctionId: data });
    }
    case "unban": {
      const { error } = await db.rpc("admin_revoke_sanction", { p_sanction_id: b.sanctionId, p_reason: b.reason ?? null });
      return error ? json({ ok: false, error: error.message }, 400) : json({ ok: true });
    }
    case "resolve_report": {
      const { error } = await db.rpc("admin_resolve_report", { p_report_id: b.reportId, p_status: b.status, p_resolution: b.resolution ?? null, p_action: b.actionTaken ?? null });
      return error ? json({ ok: false, error: error.message }, 400) : json({ ok: true });
    }
    case "set_role": {
      const { error } = await db.rpc("admin_set_role", { p_user_id: b.userId, p_role: b.role });
      return error ? json({ ok: false, error: error.message }, 400) : json({ ok: true });
    }
    default: return json({ ok: false, error: "invalid_action" }, 400);
  }
});
