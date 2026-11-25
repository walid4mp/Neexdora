#!/usr/bin/env bash
# Safe push to https://github.com/walid4mp/Neexdora (main) from Termux — NO force push, history preserved.
#   export GITHUB_TOKEN=...   # a NEW fine-grained token (Contents: read/write) — never paste tokens in chats
#   bash scripts/push_to_github.sh
set -euo pipefail
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN first (see comment above)}"
REPO="walid4mp/Neexdora"; SRC="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --quiet "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO}.git" "$TMP/repo"
cd "$TMP/repo"; git checkout main
rsync -a --exclude '.git' --exclude 'build' --exclude '.dart_tool' --exclude 'coverage' "$SRC"/ ./   # no --delete: nothing is removed
git config user.name  "${GIT_AUTHOR_NAME:-WHSTO}"; git config user.email "${GIT_AUTHOR_EMAIL:-noreply@users.noreply.github.com}"
git add -A
git diff --cached --stat | tail -5
git diff --cached --name-only | grep -E '(^|/)(\.env|key\.properties|.*\.jks|service-account.*\.json)$' && { echo "❌ secret-looking file staged — aborting"; exit 1; } || true
git commit -m "chore: rebrand to Nexora, CI/CD fixes, Supabase backend (migrations 001-009 + Edge Functions), secrets cleanup"
git push origin main            # plain push; fails (rather than overwrites) if main moved
echo "✅ pushed. Watch: https://github.com/${REPO}/actions"
