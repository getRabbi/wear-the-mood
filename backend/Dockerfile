# Fashion OS backend image (CLAUDE.md §2). One image powers the api, the worker,
# and the crons — only the start command differs. Build with
# REQUIREMENTS=requirements-worker.txt for the worker (adds the rembg stack §2.2).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    U2NET_HOME=/models

WORKDIR /app

# requirements-worker.txt does `-r requirements.txt`, so copy both for either build.
ARG REQUIREMENTS=requirements.txt
COPY requirements.txt requirements-worker.txt ./
RUN pip install --no-cache-dir -r "${REQUIREMENTS}"

COPY app ./app

EXPOSE 8000

# Default: the API. docker-compose overrides `command` for the worker.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
