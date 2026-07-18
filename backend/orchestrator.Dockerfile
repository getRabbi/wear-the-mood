# wtm-ai-orchestrator image (blueprint §11.11) — Azure Container App draining the
# `enrichment` queue (FASHN try-on / AI Studio / tagging / embeddings / bookkeeping),
# AND the base image for the six scheduled Jobs + recovery Job. Includes the pg_dump
# client for the backup task; excludes the rembg/ONNX/Pillow stack. Non-root.
# Build:  docker build -f backend/orchestrator.Dockerfile -t wtm-orchestrator backend
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    QUEUE_PROVIDER=azure

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# pg_dump 17 for the nightly DB backup task (§11.7). Supabase runs PG17; pull the v17
# client from PGDG (Debian's default is older). Pinned to trixie-pgdg for this base.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates gnupg \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
         -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt trixie-pgdg main" \
         > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client-17 \
    && rm -rf /var/lib/apt/lists/*

COPY app ./app
COPY scripts ./scripts

RUN useradd -u 10001 -m appuser && chown -R appuser /app
USER appuser

# Default: drain the enrichment queue. ACA Jobs override the command per task
# (e.g. `python -m app.tasks.backup`, `python -m app.tasks.recovery`).
CMD ["python", "-m", "app.workers.ai_orchestrator"]
