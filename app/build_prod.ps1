# Production build with a hard preflight (Part 4/5).
#
# Refuses to build a release artifact unless env/prod.json is a valid PRODUCTION
# config — the exact class of mistake that shipped 1.0.9+10 with Google Sign-In
# off (empty GOOGLE_WEB_CLIENT_ID) and could just as easily ship a build pointing
# at the old Tokyo Supabase, staging, or localhost.
#
# Usage (from E:\dopplefit\app):
#   .\build_prod.ps1              # preflight + build APK + AAB
#   .\build_prod.ps1 -ApkOnly     # preflight + APK only
#   .\build_prod.ps1 -CheckOnly   # preflight only, no build

param(
  [switch]$ApkOnly,
  [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
$appDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $appDir "env\prod.json"

# --- expected production invariants -----------------------------------------
$US_REF     = "ghzabbceoaoertatkjyg"          # authoritative US Supabase project
$TOKYO_REF  = "jqnypzlxredupgsqxbme"          # old project — must NEVER ship
$API_EXPECT = "https://api.wearthemood.com"
$DO_IP      = "159.65.248.247"                # DigitalOcean rollback origin

function Fail([string]$m) { Write-Host "PREFLIGHT FAIL: $m" -ForegroundColor Red; exit 1 }
function Ok([string]$m)   { Write-Host "  ok  $m" -ForegroundColor Green }

if (-not (Test-Path $envFile)) { Fail "env/prod.json not found at $envFile" }
$cfg = Get-Content $envFile -Raw | ConvertFrom-Json

Write-Host "Preflight: env/prod.json" -ForegroundColor Cyan

# 1. ENVIRONMENT
if ($cfg.ENVIRONMENT -ne "prod") { Fail "ENVIRONMENT is '$($cfg.ENVIRONMENT)', expected 'prod'" }
Ok "ENVIRONMENT = prod"

# 2. API_BASE_URL — reject localhost / staging / the DO rollback IP
$api = [string]$cfg.API_BASE_URL
if ($api -ne $API_EXPECT) { Fail "API_BASE_URL is '$api', expected '$API_EXPECT'" }
if ($api -match "localhost|127\.0\.0\.1|$DO_IP|staging") { Fail "API_BASE_URL points at a non-prod host: $api" }
Ok "API_BASE_URL = $api"

# 3. SUPABASE_URL — must be the US project, never Tokyo
$sb = [string]$cfg.SUPABASE_URL
if ($sb -match $TOKYO_REF) { Fail "SUPABASE_URL still points at the OLD Tokyo project ($TOKYO_REF)" }
if ($sb -notmatch $US_REF) { Fail "SUPABASE_URL is not the authoritative US project ($US_REF): $sb" }
Ok "SUPABASE_URL = $sb"

# 4. SUPABASE_ANON_KEY — present, and its `ref` claim matches the US project
$anon = [string]$cfg.SUPABASE_ANON_KEY
if ([string]::IsNullOrWhiteSpace($anon)) { Fail "SUPABASE_ANON_KEY is empty" }
try {
  $payload = $anon.Split(".")[1].Replace("-", "+").Replace("_", "/")
  switch ($payload.Length % 4) { 2 { $payload += "==" } 3 { $payload += "=" } }
  $claims = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload)) | ConvertFrom-Json
} catch { Fail "SUPABASE_ANON_KEY is not a decodable JWT" }
if ($claims.ref -ne $US_REF) { Fail "SUPABASE_ANON_KEY ref is '$($claims.ref)', expected the US project '$US_REF'" }
Ok "SUPABASE_ANON_KEY ref = $($claims.ref)"

# 5. GOOGLE_WEB_CLIENT_ID — present + shaped like a Google Web OAuth client id
$gid = [string]$cfg.GOOGLE_WEB_CLIENT_ID
if ([string]::IsNullOrWhiteSpace($gid)) { Fail "GOOGLE_WEB_CLIENT_ID is empty -- native Google Sign-In would be OFF" }
if ($gid -notmatch '^\d+-[a-z0-9]+\.apps\.googleusercontent\.com$') { Fail "GOOGLE_WEB_CLIENT_ID is malformed: $gid" }
Ok "GOOGLE_WEB_CLIENT_ID = $gid"

# 6. Feature gates are no longer read from this hand-maintained file at all.
#
# They used to be, and that was a live regression vector: env/prod.json is
# git-ignored, and every one of its .bak-* snapshots has the local-background gates
# ABSENT. Restoring any of them would have shipped an AAB with ML Kit silently
# compiled OFF while this preflight still printed "PASSED" -- every Android user
# reverted to the slow Azure BiRefNet path with nothing to notice.
#
# The authority is now app/env/feature_policy.prod.json, which IS committed. This
# step rewrites the gate half of env/prod.json from it (credentials above are
# preserved untouched), so a drifted or truncated local config snaps back to the
# invariant instead of silently shipping.
Write-Host "`nApplying the committed production feature policy" -ForegroundColor Cyan
$repoRoot = Split-Path -Parent $appDir
python "$repoRoot\scripts\render_app_env.py" --profile prod --credentials file --out $envFile
if ($LASTEXITCODE -ne 0) { Fail "could not apply app/env/feature_policy.prod.json" }

# 7. The release-blocking local-cutout verifier (local BG §3). Checks far more than
# gate values: the pinned ML Kit client, the install-time manifest metadata, that
# the native sources exist and are registered on the channel Dart calls, that the
# backend endpoint is present, and that the recorded physical-device evidence still
# matches the native code being shipped.
Write-Host "`nVerifying the local-cutout release invariants" -ForegroundColor Cyan
python "$repoRoot\scripts\verify_local_cutout_release.py" --target android-production --config $envFile
if ($LASTEXITCODE -ne 0) {
  Fail "local-cutout release verification failed (see above). Do not ship this build."
}

Write-Host "Preflight PASSED." -ForegroundColor Green
if ($CheckOnly) { exit 0 }

# --- native unit tests ------------------------------------------------------
# The Kotlin suite for the local-cutout engine is release-blocking (§8): the two
# defects that shipped -- a mask encoder that wrote the value into the wrong
# channel, and a corrupt ML Kit confidence buffer -- were both invisible to the
# Flutter suite and to `flutter analyze`.
Write-Host "`nRunning the Android local-cutout unit tests" -ForegroundColor Cyan
Set-Location "$appDir\android"
& .\gradlew.bat --no-daemon :app:testDebugUnitTest --tests "com.fashionos.app.background.*"
if ($LASTEXITCODE -ne 0) { Fail "Android background-removal unit tests failed" }
Set-Location $appDir

# --- build ------------------------------------------------------------------
Write-Host "`nBuilding release APK..." -ForegroundColor Cyan
flutter build apk --release --dart-define-from-file=env/prod.json
if ($LASTEXITCODE -ne 0) { Fail "flutter build apk failed" }
Write-Host "APK: build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Green

if (-not $ApkOnly) {
  Write-Host "`nBuilding release AAB..." -ForegroundColor Cyan
  flutter build appbundle --release --dart-define-from-file=env/prod.json
  if ($LASTEXITCODE -ne 0) { Fail "flutter build appbundle failed" }
  Write-Host "AAB: build/app/outputs/bundle/release/app-release.aab" -ForegroundColor Green
}

# --- verify the ARTIFACT, not just the source tree --------------------------
# Everything above proves the repository is correct. This proves the bytes that
# will reach Play actually contain the compiled engine and the merged manifest
# metadata that delivers its model -- the difference between "the code is right"
# and "the shipped build has it".
Write-Host "`nInspecting the built artifact" -ForegroundColor Cyan
$artifact = if ($ApkOnly) {
  "$appDir\build\app\outputs\flutter-apk\app-release.apk"
} else {
  "$appDir\build\app\outputs\bundle\release\app-release.aab"
}
python "$repoRoot\scripts\verify_local_cutout_release.py" `
  --target android-production --config $envFile --artifact $artifact
if ($LASTEXITCODE -ne 0) { Fail "the built artifact failed local-cutout verification" }

Write-Host "`nDone." -ForegroundColor Green
