#!/usr/bin/env bash
# Fails LOUDLY (with the names of what is missing) — never prints secret values.
# usage: validate_secrets.sh <debug|release|aab>
set -euo pipefail
MODE="${1:-debug}"
missing=()
need() { [ -n "${!1:-}" ] || missing+=("$1"); }

for v in SUPABASE_URL SUPABASE_ANON_KEY CLOUDINARY_CLOUD_NAME CLOUDINARY_UPLOAD_PRESET \
         GOOGLE_SERVICES_JSON_BASE64; do need "$v"; done
if [ "$MODE" = "release" ] || [ "$MODE" = "aab" ]; then
  for v in ANDROID_KEYSTORE_BASE64 ANDROID_STORE_PASSWORD ANDROID_KEY_PASSWORD ANDROID_KEY_ALIAS; do need "$v"; done
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "::error title=Missing GitHub Secrets::The build cannot run. Add these repository secrets: ${missing[*]}"
  echo "See SETUP_NEW_SERVICES_AR.md for where to get each value."
  exit 1
fi
[ -n "${GIPHY_API_KEY:-}" ] || echo "::warning title=GIPHY_API_KEY not set::The GIF picker will not return results."

# --- format checks (no values printed) ---
case "$SUPABASE_URL" in https://*.supabase.co|https://*.supabase.in) ;; *) echo "::error::SUPABASE_URL must look like https://<ref>.supabase.co"; exit 1;; esac
echo "$GOOGLE_SERVICES_JSON_BASE64" | base64 -d > /tmp/gs.json 2>/dev/null || { echo "::error::GOOGLE_SERVICES_JSON_BASE64 is not valid base64 (use: base64 -w0 google-services.json)"; exit 1; }
python3 - <<'PY'
import json, sys
try: g = json.load(open('/tmp/gs.json'))
except Exception: print("::error::google-services.json (from secret) is not valid JSON"); sys.exit(1)
pk = [c['client_info']['android_client_info']['package_name'] for c in g.get('client', [])]
if 'com.nexora.app' not in pk:
    print(f"::error::google-services.json has no Android app with package 'com.nexora.app' (found: {pk}). Create the Firebase Android app with that exact package name."); sys.exit(1)
raw = open('/tmp/gs.json').read()
if any(x in raw for x in ('your-firebase-project-id', 'REPLACE_WITH', '000000000000')):
    print("::error::google-services.json still contains placeholder values"); sys.exit(1)
PY
rm -f /tmp/gs.json
echo "✅ secrets present and well-formed for mode: $MODE"
