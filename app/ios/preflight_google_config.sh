#!/usr/bin/env bash
# iOS Google sign-in configuration preflight.
#
# Runs on the CI Mac AFTER GoogleService-Info.plist is placed and BEFORE the
# build, so a misconfigured artifact fails here instead of failing silently on a
# tester's phone. Every check is structural — it asserts that values EXIST, MATCH
# each other and are not placeholders. It never prints a client id, a secret, or
# the contents of any plist.
#
# Exit non-zero on the first problem.
set -euo pipefail

PLIST="${1:-app/ios/Runner/GoogleService-Info.plist}"
PBXPROJ="${2:-app/ios/Runner.xcodeproj/project.pbxproj}"
INFO_PLIST="${3:-app/ios/Runner/Info.plist}"

fail() { echo "PREFLIGHT FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; }

echo "iOS Google config preflight"

[ -f "$PLIST" ] || fail "GoogleService-Info.plist not found at $PLIST"
plutil -lint "$PLIST" >/dev/null || fail "GoogleService-Info.plist is not valid"
ok "GoogleService-Info.plist present and well-formed"

read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

# 1) Never ship the compile-check placeholder.
if /usr/libexec/PlistBuddy -c "Print :CI_PLACEHOLDER" "$PLIST" >/dev/null 2>&1; then
  fail "GoogleService-Info.plist is the CI placeholder, not the real file"
fi
ok "not the CI placeholder"

# 2) Required keys are present and non-empty. Values are never echoed.
for key in BUNDLE_ID CLIENT_ID REVERSED_CLIENT_ID PROJECT_ID; do
  value="$(read_key "$key")"
  [ -n "$value" ] || fail "$key is missing or empty in GoogleService-Info.plist"
  case "$value" in
    *PLACEHOLDER*|*placeholder*|*CHANGEME*|*TODO*|*XXX*)
      fail "$key looks like a placeholder value" ;;
  esac
  ok "$key present"
done

# 3) The plist must belong to the bundle we actually build. A plist for another
#    bundle yields an ID token whose audience Supabase will not accept — a
#    failure that looks like a mysterious auth error rather than a config error.
PLIST_BUNDLE="$(read_key BUNDLE_ID)"
PROJECT_BUNDLE="$(grep -m1 -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*' "$PBXPROJ" | sed 's/.*= //')"
[ -n "$PROJECT_BUNDLE" ] || fail "could not read PRODUCT_BUNDLE_IDENTIFIER from the Xcode project"
[ "$PLIST_BUNDLE" = "$PROJECT_BUNDLE" ] \
  || fail "GoogleService-Info.plist BUNDLE_ID does not match the Xcode PRODUCT_BUNDLE_IDENTIFIER"
ok "plist BUNDLE_ID matches the Xcode target"

# 4) CLIENT_ID must be an iOS OAuth client, and REVERSED_CLIENT_ID its reverse.
CLIENT_ID="$(read_key CLIENT_ID)"
REVERSED="$(read_key REVERSED_CLIENT_ID)"
case "$CLIENT_ID" in
  *.apps.googleusercontent.com) ok "CLIENT_ID has the expected shape" ;;
  *) fail "CLIENT_ID is not a *.apps.googleusercontent.com value" ;;
esac
EXPECTED_REVERSED="com.googleusercontent.apps.${CLIENT_ID%%.apps.googleusercontent.com}"
[ "$REVERSED" = "$EXPECTED_REVERSED" ] \
  || fail "REVERSED_CLIENT_ID is not the reverse of CLIENT_ID"
ok "REVERSED_CLIENT_ID is consistent with CLIENT_ID"

# 5) The reversed client id must be a registered URL scheme, or the Google
#    callback never returns to the app.
if [ -f "$INFO_PLIST" ]; then
  if grep -q "$REVERSED" "$INFO_PLIST" 2>/dev/null; then
    ok "REVERSED_CLIENT_ID is a registered URL scheme in Info.plist"
  elif grep -q 'REVERSED_CLIENT_ID' "$INFO_PLIST" 2>/dev/null; then
    ok "Info.plist references REVERSED_CLIENT_ID via a build variable"
  else
    fail "Info.plist does not register the reversed client id as a URL scheme"
  fi
fi

# 6) The Dart side needs the WEB client id as serverClientId; without it the app
#    silently drops to browser OAuth and native sign-in never runs.
WEB_ID="$(python3 - <<'PY' 2>/dev/null || true
import json, pathlib
p = pathlib.Path("app/env/prod.json")
print(json.loads(p.read_text()).get("GOOGLE_WEB_CLIENT_ID", "") if p.exists() else "")
PY
)"
[ -n "$WEB_ID" ] || fail "GOOGLE_WEB_CLIENT_ID is empty in app/env/prod.json"
case "$WEB_ID" in
  *.apps.googleusercontent.com) ;;
  *) fail "GOOGLE_WEB_CLIENT_ID is not a *.apps.googleusercontent.com value" ;;
esac
[ "$WEB_ID" != "$CLIENT_ID" ] \
  || fail "GOOGLE_WEB_CLIENT_ID equals the iOS CLIENT_ID — it must be the WEB client"
ok "GOOGLE_WEB_CLIENT_ID present, distinct from the iOS client"

# 7) The iOS client and the web client must come from the SAME Google Cloud
#    project, or Supabase will reject the token's audience.
IOS_PROJECT_NUMBER="${CLIENT_ID%%-*}"
WEB_PROJECT_NUMBER="${WEB_ID%%-*}"
[ "$IOS_PROJECT_NUMBER" = "$WEB_PROJECT_NUMBER" ] \
  || fail "iOS CLIENT_ID and GOOGLE_WEB_CLIENT_ID belong to different Google Cloud projects"
ok "iOS and web clients share one Google Cloud project"

echo "iOS Google config preflight passed"
