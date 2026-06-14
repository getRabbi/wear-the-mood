# worker.ps1 - Local async job worker (try-on + background removal), wired to the
# DEV Supabase via backend\.env. Processes the `tryon_jobs` / cutout queues so a
# freshly added wardrobe item actually finishes "Removing background" locally.
#
# Uses BG_PROVIDER=stub by default (config.py) -> light, no rembg/onnxruntime, so
# it runs fine in the same dev venv as the API.
#
# Usage (from anywhere):
#   E:\dopplefit\backend\worker.ps1

$ErrorActionPreference = "Stop"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $dir   # config.py loads .env relative to the working directory

$py = Join-Path $dir ".venv\Scripts\python.exe"

if (!(Test-Path $py)) {
  Write-Host "ERROR: venv paowa jay nai: $py" -ForegroundColor Red
  exit 1
}
if (!(Test-Path (Join-Path $dir ".env"))) {
  Write-Host "ERROR: backend\.env nai." -ForegroundColor Red
  exit 1
}

Write-Host "Fashion OS worker (dev) - try-on + background removal   (Ctrl+C to stop)" -ForegroundColor Green
& $py -m app.workers.worker
