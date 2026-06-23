# Fashion OS backend image (CLAUDE.md §2). One image powers the api, the worker,
# and the crons — only the start command differs. Build with
# REQUIREMENTS=requirements-worker.txt for the worker (adds the rembg stack §2.2).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    U2NET_HOME=/models

# pg_dump 17 for the nightly DB backup cron (§14). Supabase runs PG17; Debian's
# default client is 15 and refuses a v17 server, so pull it from the PGDG repo.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates gnupg \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
         -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
         > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client-17 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# requirements-worker.txt does `-r requirements.txt`, so copy both for either build.
ARG REQUIREMENTS=requirements.txt
COPY requirements.txt requirements-worker.txt ./
RUN pip install --no-cache-dir -r "${REQUIREMENTS}"

COPY app ./app

EXPOSE 8000

# Default: the API. docker-compose overrides `command` for the worker.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
