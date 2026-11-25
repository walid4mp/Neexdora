// FCM HTTP v1 sender. Needs secret FIREBASE_SERVICE_ACCOUNT (full service-account JSON).
import { env } from "./common.ts";

let cached: { token: string; exp: number } | null = null;

const b64url = (b: ArrayBuffer | string) => {
  const bytes = typeof b === "string" ? new TextEncoder().encode(b) : new Uint8Array(b);
  let s = ""; bytes.forEach((x) => (s += String.fromCharCode(x)));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

function serviceAccount() {
  const sa = JSON.parse(env("FIREBASE_SERVICE_ACCOUNT"));
  if (!sa.client_email || !sa.private_key || !sa.project_id) throw new Error("missing_secret:FIREBASE_SERVICE_ACCOUNT(invalid)");
  return sa as { client_email: string; private_key: string; project_id: string };
}

async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;
  const sa = serviceAccount();
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${header}.${claim}.${b64url(sig)}` }),
  });
  if (!res.ok) throw new Error(`fcm_oauth_failed:${res.status}`);
  const j = await res.json();
  cached = { token: j.access_token, exp: now + (j.expires_in ?? 3600) };
  return cached.token;
}

export type FcmResult = { ok: boolean; status: number; unregistered: boolean };

/** Data-only, high-priority message → delivered to the Dart background handler even when the app is killed. */
export async function sendFcm(token: string, data: Record<string, string>, opts: { ttl?: string; voip?: boolean; alert?: { title: string; body: string } } = {}): Promise<FcmResult> {
  const sa = serviceAccount();
  const message: Record<string, unknown> = {
    token,
    data,
    android: { priority: "high", ttl: opts.ttl ?? "60s" },
  };
  if (opts.alert) {
    message.apns = {
      headers: { "apns-priority": "10", ...(opts.voip ? { "apns-push-type": "voip" } : {}) },
      payload: { aps: { alert: opts.alert, sound: "default", "content-available": 1 } },
    };
  }
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await accessToken()}`, "Content-Type": "application/json" },
    body: JSON.stringify({ message }),
  });
  let unregistered = false;
  if (!res.ok) {
    const t = await res.text();
    unregistered = res.status === 404 || /UNREGISTERED|INVALID_ARGUMENT.*token/i.test(t);
    console.warn("[fcm] send failed", res.status);
  } else await res.body?.cancel();
  return { ok: res.ok, status: res.status, unregistered };
}
