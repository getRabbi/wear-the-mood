# wtm-rembg-worker image (blueprint §11.4, §11.11) — the event-driven Azure
# Container Apps Job `wtm-rembg-job` draining the `jobs` queue.
#
# Cold start is the whole ballgame here. Jobs have NO warm pool, so every single
# execution pays image-pull + interpreter start + ONNX model load. Phase 5 tuned
# this image for that, not for disk:
#   * multi-stage — pip, wheels and build metadata stay in the builder stage;
#   * the U2Net model is BAKED and VERIFIED at build time, so an execution never
#     reaches the network for it;
#   * bytecode is PRE-COMPILED. The usual PYTHONDONTWRITEBYTECODE=1 saves a little
#     image size but makes every cold start recompile the whole dependency tree —
#     exactly backwards for a Job that cold-starts every time.
#
# Build:  docker build -f backend/rembg-worker.Dockerfile -t wtm-rembg-worker backend

# ── builder: install the heavy stack into a self-contained venv ───────────────
FROM python:3.12-slim AS builder

# Which rembg ONNX model to bake: u2net (176 MB, best quality, default) or u2netp
# (4.7 MB, ~5-8x faster session init). Build the fast image with
# `--build-arg REMBG_MODEL=u2netp`. ONLY the selected model is baked, so the
# u2netp image never carries the 176 MB u2net weight.
ARG REMBG_MODEL=u2net

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    U2NET_HOME=/models

WORKDIR /build
COPY requirements.txt requirements-worker.txt ./

RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements-worker.txt

# Bake the SELECTED model and VERIFY it (§11.4). A missing/short file fails the
# build rather than shipping an image that would download at execution time.
RUN /opt/venv/bin/python -c "from rembg import new_session; new_session('${REMBG_MODEL}')" \
    && test -s /models/${REMBG_MODEL}.onnx \
    && chmod -R a+rX /models

# Drop test/build residue that never runs in production.
RUN find /opt/venv -type d -name '__pycache__' -prune -exec rm -rf {} + \
    && find /opt/venv -type d -name 'tests' -prune -exec rm -rf {} + \
    && find /opt/venv -type d -name '*.dist-info' -exec rm -rf {}/RECORD \; 2>/dev/null || true

# ── runtime ──────────────────────────────────────────────────────────────────
FROM python:3.12-slim

# Re-declare after FROM (build args don't cross stages) and pin it into the runtime
# ENV so RembgBackgroundRemover selects the SAME model that was baked above.
ARG REMBG_MODEL=u2net

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    U2NET_HOME=/models \
    BG_PROVIDER=rembg \
    QUEUE_PROVIDER=azure \
    REMBG_MODEL=${REMBG_MODEL} \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /models /models

COPY app ./app
COPY scripts ./scripts

# Pre-compile BOTH the dependency tree and our own code so no cold start pays for
# it. Failures are tolerated: a module that cannot be byte-compiled ahead of time
# still imports normally at runtime.
RUN python -m compileall -q /opt/venv/lib /app/app || true

RUN useradd -u 10001 -m appuser && chown -R appuser /app
USER appuser

# Default to the FINITE batch entrypoint — the Job overrides this explicitly, but
# the always-on worker loop is no longer a valid way to run this image (Phase 5 §A).
CMD ["python", "-m", "app.workers.rembg_batch"]
