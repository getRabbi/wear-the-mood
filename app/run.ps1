# # Dev run helper — launches the app on the USB-connected phone through the adb reverse tunnel.
# # Usage (from E:\dopplefit\app):  .\run.ps1
# # Re-runs the reverse tunnel each time, so it survives unplug/reboot.

# $adb = "E:\SDK\platform-tools\adb.exe"
# & $adb reverse tcp:8000 tcp:8000 | Out-Null

# flutter run `
#   --dart-define-from-file=env/dev.json `
#   --dart-define=API_BASE_URL=http://localhost:8000 `
#   -d ab617080

# Dev run helper — Flutter app run + adb reverse tunnel
# Usage:
#   .\run.ps1
# Optional:
#   .\run.ps1 -Device ab617080
#   .\run.ps1 -Device 192.168.0.12:5555

# Dev run helper — Flutter app run + adb reverse tunnel
# Usage:
#   .\run.ps1
#   .\run.ps1 -Device ab617080
#   .\run.ps1 -Device 192.168.0.12:5555

param(
  [string]$Device = "",
  [int]$Port = 8000,
  [string]$ApiBaseUrl = "http://localhost:8000"
)

$ErrorActionPreference = "Stop"

$adb = "E:\SDK\platform-tools\adb.exe"
$appDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $appDir "env\dev.json"
$preferredDevice = "ab617080"

function Fail {
  param([string]$Message)
  Write-Host ""
  Write-Host "ERROR: $Message" -ForegroundColor Red
  exit 1
}

Set-Location $appDir

if (!(Test-Path $adb)) {
  Fail "ADB paowa jay nai: $adb"
}

if (!(Test-Path $envFile)) {
  Fail "env/dev.json paowa jay nai: $envFile"
}

try {
  flutter --version | Out-Null
} catch {
  Fail "Flutter command kaj korche na. Flutter PATH check koro."
}

Write-Host "Starting ADB server..."
& $adb start-server | Out-Null

# Wireless device hole age connect korbe
if ($Device -match '^\d{1,3}(\.\d{1,3}){3}:\d+$') {
  Write-Host "Connecting wireless device: $Device"
  & $adb connect $Device | Out-Host
  Start-Sleep -Seconds 1
}

$rawDevices = & $adb devices
$devices = @()

foreach ($line in $rawDevices) {
  if ($line -match '^(\S+)\s+device$') {
    $devices += $matches[1]
  }
}

if ($devices.Count -eq 0) {
  Fail "Kono Android device connected nai. USB/Wireless debugging on kore abar run koro."
}

if ($Device -ne "") {
  if ($devices -contains $Device) {
    $targetDevice = $Device
  } else {
    Fail "Ei device connected na: $Device"
  }
} elseif ($devices -contains $preferredDevice) {
  $targetDevice = $preferredDevice
} else {
  $targetDevice = $devices[0]
}

Write-Host "Using device: $targetDevice" -ForegroundColor Green

Write-Host "Setting adb reverse tunnel tcp:$Port -> tcp:$Port"
& $adb -s $targetDevice reverse tcp:$Port tcp:$Port | Out-Null

# Warn early if the backend isn't up - otherwise the app shows NETWORK_ERROR.
try {
  $health = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/v1/health" -TimeoutSec 3 -UseBasicParsing
  if ($health.StatusCode -eq 200) {
    Write-Host "Backend OK on :$Port" -ForegroundColor Green
  }
} catch {
  Write-Host "WARNING: backend :$Port e response dicche na - app NETWORK_ERROR dekhabe." -ForegroundColor Yellow
  Write-Host "         Alada window e chalao:  E:\dopplefit\backend\serve.ps1   (ba root theke .\dev.ps1)" -ForegroundColor Yellow
}

Write-Host "Running Flutter app..."
flutter run `
  --dart-define-from-file="$envFile" `
  --dart-define=API_BASE_URL=$ApiBaseUrl `
  -d $targetDevice