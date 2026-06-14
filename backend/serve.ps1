# serve.ps1 - Local dev backend (FastAPI, hot-reload), wired to the DEV Supabase
# project via backend\.env (ENVIRONMENT=dev).
#
# Usage (from anywhere):
#   E:\dopplefit\backend\serve.ps1
#   E:\dopplefit\backend\serve.ps1 -Port 8000
#
# Binds to 127.0.0.1 on purpose: the phone reaches it through the `adb reverse`
# tunnel set up by app\run.ps1, so the server never needs to listen on the LAN.

param(
  [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $dir   # config.py loads .env relative to the working directory

$py = Join-Path $dir ".venv\Scripts\python.exe"

if (!(Test-Path $py)) {
  Write-Host "ERROR: venv paowa jay nai: $py" -ForegroundColor Red
  Write-Host "       backend\ e venv banao: python -m venv .venv ; .\.venv\Scripts\pip install -r requirements.txt" -ForegroundColor Yellow
  exit 1
}

if (!(Test-Path (Join-Path $dir ".env"))) {
  Write-Host "ERROR: backend\.env nai. .env.example theke copy kore fill koro." -ForegroundColor Red
  exit 1
}

# Free the port first so this is a RELIABLE restart: a stale backend (e.g. one
# whose --reload silently missed a new router file) won't keep serving old code.
$listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty OwningProcess -Unique
foreach ($procId in $listeners) {
  Write-Host "Freeing port $Port (killing PID $procId and its children)..." -ForegroundColor Yellow
  & taskkill /T /F /PID $procId 2>&1 | Out-Null
}
if ($listeners) { Start-Sleep -Seconds 2 }

Write-Host "Fashion OS backend (dev) -> http://127.0.0.1:$Port   (Ctrl+C to stop)" -ForegroundColor Green
& $py -m uvicorn app.main:app --reload --port $Port
