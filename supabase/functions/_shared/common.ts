import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-user-language, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

export const env = (k: string, required = true): string => {
  const v = Deno.env.get(k) ?? "";
  if (!v && required) throw new Error(`missing_secret:${k}`);
  return v;
};

/** Service-role client — bypasses RLS. Never expose to clients. */
export const admin = (): SupabaseClient =>
  createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });

/** Client that acts AS the caller (RLS + auth.uid() apply). */
export const asCaller = (req: Request): SupabaseClient =>
  createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });

export async function getCaller(req: Request): Promise<{ id: string; email?: string } | null> {
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return null;
  const { data, error } = await admin().auth.getUser(jwt);
  if (error || !data.user) return null;
  return { id: data.user.id, email: data.user.email ?? undefined };
}

export const isCron = (req: Request) => {
  const s = Deno.env.get("CRON_SECRET") ?? "";
  return s.length >= 16 && req.headers.get("x-cron-secret") === s;
};

export async function isSanctioned(uid: string): Promise<boolean> {
  const { data } = await admin().rpc("is_sanctioned", { p_user_id: uid });
  return data === true;
}

export const handle = (fn: (req: Request) => Promise<Response>) =>
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    try {
      return await fn(req);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("[edge] error:", msg);               // never log secrets / payloads
      return json({ success: false, ok: false, error: msg.startsWith("missing_secret") ? msg : "internal_error" }, msg.startsWith("missing_secret") ? 500 : 500);
    }
  });
