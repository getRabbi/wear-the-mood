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

# 6. Local-background feature gates — the canonical ANDROID PRODUCTION values.
#
# These were NOT checked before, and that is a live regression vector: env/prod.json
# is git-ignored and hand-maintained, and every one of its .bak-* snapshots has the
# gates ABSENT. Restoring any of them, or a typo, would have shipped an AAB with
# ML Kit silently compiled OFF while this preflight still printed "PASSED" — every
# Android user reverted to the slow Azure BiRefNet path with nothing to notice.
#
# `bool.fromEnvironment` only reads the exact string "true", so "True", "1", "yes"
# or a stray space all compile to FALSE. Require literals, not truthiness.
$ANDROID_PROD_GATES = [ordered]@{
  LOCAL_BG_REMOVAL_ENABLED = "true"   # master switch
  LOCAL_BG_ANDROID_ENABLED = "true"   # ML Kit arm, shipped in 1.0.16+19
  LOCAL_BG_IOS_ENABLED     = "false"  # Apple Vision stays dormant
}

# Deliberately NOT in the required set above. For a diagnostics switch the
# dangerous accident is silently ON, not silently off, so absence is the safe
# state and must not block a build. If it IS present it must say 'false' -- an
# internal diagnostic build is never produced by this script.
$ANDROID_PROD_FORBIDDEN_TRUE = @("LOCAL_BG_IOS_DIAGNOSTICS_ENABLED")

foreach ($gate in $ANDROID_PROD_GATES.Keys) {
  $expected = $ANDROID_PROD_GATES[$gate]
  $prop = $cfg.PSObject.Properties[$gate]
  if (-not $prop) {
    Fail "$gate is MISSING from env/prod.json (expected '$expected'). A missing gate compiles to false."
  }
  $actual = [string]$prop.Value
  if ($actual -ne "true" -and $actual -ne "false") {
    # NOTE: keep this file's STRING literals pure ASCII. There is no BOM, so
    # PowerShell 5.1 decodes it as Windows-1252, where the UTF-8 em-dash byte 0x94
    # becomes a smart closing quote and silently terminates the string early.
    Fail "$gate is '$actual' - must be the exact string 'true' or 'false'. Dart treats anything else as false."
  }
  if ($actual -ne $expected) {
    Fail "$gate is '$actual', but Android production requires '$expected'."
  }
  Ok "$gate = $actual"
}

foreach ($gate in $ANDROID_PROD_FORBIDDEN_TRUE) {
  $prop = $cfg.PSObject.Properties[$gate]
  if (-not $prop) { Ok "$gate absent (compiles false)"; continue }
  $actual = [string]$prop.Value
  if ($actual -eq "true") {
    Fail "$gate is 'true' - diagnostics must never ship in an Android production build."
  }
  if ($actual -ne "false") {
    Fail "$gate is '$actual' - must be the exact string 'false' (or absent)."
  }
  Ok "$gate = false"
}

Write-Host "Preflight PASSED." -ForegroundColor Green
if ($CheckOnly) { exit 0 }

# --- build ------------------------------------------------------------------
Set-Location $appDir
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
Write-Host "`nDone." -ForegroundColor Green
