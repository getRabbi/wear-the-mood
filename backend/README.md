# Fashion OS — Backend (FastAPI)

AI orchestration, business logic, credit metering. Part of the Fashion OS
monorepo — see the [root README](../README.md) and [`CLAUDE.md`](../CLAUDE.md).

## Setup (Windows, run from `backend/`)

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt -r requirements-dev.txt
copy .env.example .env        # then fill in real values (this file is git-ignored)
```

## Run

```powershell
uvicorn app.main:app --reload --port 8000
```

- Health check: `GET http://localhost:8000/v1/health`
- All API routes live under `/v1` (CLAUDE.md §13). Errors use the uniform
  envelope: `{"error": {"code", "message", "request_id"}}`.

## Test & lint

```powershell
pytest
ruff check .
ruff format .
```

## Layout (`app/`)

| Folder | Purpose |
|---|---|
| `core/`    | config, error contract, middleware (auth/credits/rate-limit later) |
| `routers/` | versioned API routes (`v1/`) |
| `models/`  | pydantic schemas |
| `services/`| provider wrappers (tryon, bg, llm, …) — added in later phases |
| `workers/` | async job processing (Render worker) — Step 11 |
| `cron/`    | scheduled jobs (daily push) — Step 11 |

> Secrets live only in git-ignored `.env*`, never in `.env.example`.
