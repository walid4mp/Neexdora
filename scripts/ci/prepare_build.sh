#!/usr/bin/env bash
# Restores service files from secrets, writes the dart-define file and (release only) signing config.
# usage: prepare_build.sh <debug|release|aab>      Cleanup: scripts/ci/cleanup.sh
set -euo pipefail
MODE="${1:-debug}"
echo "$GOOGLE_SERVICES_JSON_BASE64" | base64 -d > android/app/google-services.json
python3 scripts/make_firebase_options.py android/app/google-services.json lib/firebase_options.dart

python3 - <<'PY'
import json, os
keys = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "CLOUDINARY_CLOUD_NAME", "CLOUDINARY_UPLOAD_PRESET", "GIPHY_API_KEY", "APP_VERSION", "BUILD_NUMBER", "COMMIT_SHA"]
json.dump({k: os.environ.get(k, "") for k in keys if os.environ.get(k, "") != ""}, open("ci.env.json", "w"))
PY
chmod 600 ci.env.json

if [ "$MODE" = "release" ] || [ "$MODE" = "aab" ]; then
  echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/upload-keystore.jks
  umask 077
  {
    echo "storePassword=$ANDROID_STORE_PASSWORD"
    echo "keyPassword=$ANDROID_KEY_PASSWORD"
    echo "keyAlias=$ANDROID_KEY_ALIAS"
    echo "storeFile=upload-keystore.jks"
  } > android/key.properties
  # verify keystore/alias/password BEFORE spending minutes on a build
  keytool -list -keystore android/app/upload-keystore.jks -storepass "$ANDROID_STORE_PASSWORD" -alias "$ANDROID_KEY_ALIAS" >/dev/null 2>&1 \
    || { echo "::error::Keystore could not be opened with the given ANDROID_STORE_PASSWORD / ANDROID_KEY_ALIAS"; exit 1; }
fi
echo "✅ build inputs prepared (mode: $MODE)"
