# dev.ps1 - ONE command to test on your phone with the laptop.
#
# What it does:
#   1. Makes sure the dev backend is running on :Port (starts it in a new
#      window if it isn't), and waits until it's healthy.
#   2. Hands off to app\run.ps1 -> connects the phone, sets the adb reverse
#      tunnel, and runs the Flutter app pointing at the local backend.
#
# Usage (from E:\dopplefit):
#   .\dev.ps1
#   .\dev.ps1 -Device 192.168.1.218:37943   # a specific wireless device:port
#   .\dev.ps1 -Device ab617080              # a specific USB device id
#
# The phone talks to the laptop through `adb reverse`, so USB OR wireless
# debugging both work. Backend stays in its own window so you can watch logs.

param(
  [string]$Device = "",
  [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
$root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Join-Path $root "backend"
$appDir     = Join-Path $root "app"

function Test-Backend {
  try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/v1/health" -TimeoutSec 3 -UseBasicParsing
    return $r.StatusCode -eq 200
  } catch {
    return $false
  }
}

Write-Host "==> Backend check (:$Port) ..." -ForegroundColor Cyan
if (Test-Backend) {
  Write-Host "    Already running." -ForegroundColor Green
} else {
  Write-Host "    Down - notun window e start korchi..." -ForegroundColor Yellow
  Start-Process powershell -ArgumentList @(
    "-NoExit", "-File", "$backendDir\serve.ps1", "-Port", "$Port"
  )

  $deadline = (Get-Date).AddSeconds(45)
  while (-not (Test-Backend)) {
    if ((Get-Date) -gt $deadline) {
      Write-Host "ERROR: backend health timeout. Notun window-er log dekho." -ForegroundColor Red
      exit 1
    }
    Start-Sleep -Seconds 2
    Write-Host "    waiting for backend..."
  }
  Write-Host "    Backend up." -ForegroundColor Green
}

Write-Host "==> Worker check ..." -ForegroundColor Cyan
$workerRunning = $false
try {
  $workerRunning = [bool](Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*app.workers.worker*' })
} catch {
  $workerRunning = $false
}
if ($workerRunning) {
  Write-Host "    Already running." -ForegroundColor Green
} else {
  Write-Host "    Starting worker (bg removal + try-on) in a new window..." -ForegroundColor Yellow
  Start-Process powershell -ArgumentList @("-NoExit", "-File", "$backendDir\worker.ps1")
}

Write-Host "==> Launching app on phone..." -ForegroundColor Cyan
& "$appDir\run.ps1" -Device $Device -Port $Port
