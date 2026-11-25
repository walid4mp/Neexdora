#!/usr/bin/env bash
# Always run (if: always()) — removes every restored secret file from the runner.
rm -f ci.env.json android/key.properties android/app/upload-keystore.jks android/app/google-services.json /tmp/gs.json /tmp/fo.dart
git checkout -- lib/firebase_options.dart android/app/google-services.json 2>/dev/null || true
echo "🧹 temporary secret files removed"
