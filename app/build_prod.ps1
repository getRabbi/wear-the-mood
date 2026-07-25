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
