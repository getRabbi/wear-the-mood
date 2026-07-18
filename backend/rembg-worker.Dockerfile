# wtm-rembg-worker image (blueprint §11.4, §11.11) — Azure Container App draining the
# `jobs` queue for local background removal. The rembg model is BAKED IN at build time
# under the pinned U2NET_HOME so startup never downloads it. Non-root.
# Build:  docker build -f backend/rembg-worker.Dockerfile -t wtm-rembg-worker backend
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    U2NET_HOME=/models \
    BG_PROVIDER=rembg \
    QUEUE_PROVIDER=azure

WORKDIR /app

# The heavy background-removal stack (rembg[cpu] + onnxruntime + pillow) lives here only.
COPY requirements.txt requirements-worker.txt ./
RUN pip install --no-cache-dir -r requirements-worker.txt

# Bake the pinned U2Net model into the image and VERIFY it (§11.4): startup must not
# download anything. If rembg's default model changes, pin it explicitly here.
RUN python -c "from rembg import new_session; new_session('u2net')" \
    && test -s /models/u2net.onnx \
    && chmod -R a+rX /models

COPY app ./app
COPY scripts ./scripts

RUN useradd -u 10001 -m appuser && chown -R appuser /app
USER appuser

CMD ["python", "-m", "app.workers.rembg_worker"]
