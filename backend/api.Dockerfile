# wtm-api image (blueprint §11.11) — public FastAPI for Heroku (Basic, 1 web dyno)
# and the emergency ACA app. Excludes the rembg/ONNX/Pillow model stack and pg_dump;
# non-root; binds $PORT (Heroku) with one memory-safe uvicorn process (§11.8).
# Build:  docker build -f backend/api.Dockerfile -t wtm-api backend
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000 \
    WEB_CONCURRENCY=1

WORKDIR /app

# Only the light API deps (requirements.txt); the rembg stack lives in the worker image.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY scripts ./scripts

# Non-root runtime (§11.11).
RUN useradd -u 10001 -m appuser && chown -R appuser /app
USER appuser

EXPOSE 8000

# Heroku injects $PORT; default 8000 elsewhere. Exactly one Uvicorn process inside
# the 512 MB dyno (WEB_CONCURRENCY=1) — no multi-worker without measured proof (§11.8).
# Graceful shutdown via Uvicorn's default SIGTERM handling.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD python -c "import os,sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8000')+'/healthz',timeout=2).status==200 else 1)"
