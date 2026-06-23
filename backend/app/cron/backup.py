"""Nightly DB backup cron (Phase 4B safety net, CLAUDE.md §14/§6).

``pg_dump`` (custom format, restorable via ``pg_restore``) of the database over
the DIRECT 5432 connection — pg_dump can NOT run through the 6543 transaction
pooler, so this requires ``CONNECTION_STRING_DIRECT`` (Phase 2B). The dump is
uploaded to the PRIVATE R2 bucket under ``backups/<env>/<ts>.dump`` and the most
recent ``settings.backup_keep`` are retained. Run with ``python -m app.cron.backup``.
"""

from __future__ import annotations

import asyncio
import logging
import os
import subprocess
import tempfile
from datetime import UTC, datetime

from app.core.config import get_settings, pick_migration_dsn
from app.core.observability import init_sentry
from app.services.media import get_storage_provider
from app.services.media.r2 import R2StorageProvider

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron.backup")

_BACKUP_PREFIX = "backups"


def _run_pg_dump(dsn: str, out_path: str) -> tuple[int, str]:
    """Dump the DB to ``out_path`` (custom format). Returns (returncode, stderr)."""
    proc = subprocess.run(
        [
            "pg_dump",
            "--format=custom",
            "--no-owner",
            "--no-privileges",
            "--file",
            out_path,
            dsn,
        ],
        capture_output=True,
        text=True,
        timeout=1800,
    )
    return proc.returncode, proc.stderr


def _read_dump(path: str) -> bytes:
    with open(path, "rb") as f:
        return f.read()


async def _prune(provider: R2StorageProvider, prefix: str, keep: int) -> None:
    """Keep only the most recent ``keep`` dumps (keys sort lexically by timestamp)."""
    keys = sorted(await provider.list_keys(prefix=prefix, visibility="private"))
    old = keys[:-keep] if keep > 0 else keys
    for key in old:
        try:
            await provider.delete(object_key=key, visibility="private")
        except Exception as exc:
            log.warning("backup prune failed for %s: %s", key, exc)
    if old:
        log.info("pruned %d old backup(s)", len(old))


async def _run() -> None:
    s = get_settings()
    dsn, used_fallback = pick_migration_dsn(os.environ)
    if not dsn:
        log.warning("no CONNECTION_STRING(_DIRECT) set — skipping backup.")
        return
    if used_fallback:
        log.warning(
            "CONNECTION_STRING_DIRECT not set — pg_dump needs the DIRECT 5432 "
            "(it can't run through the 6543 transaction pooler); skipping backup."
        )
        return
    if not s.r2_configured:
        log.warning("R2 not configured — nowhere to store the backup; skipping.")
        return
    provider = get_storage_provider()
    if not isinstance(provider, R2StorageProvider):
        log.warning("R2 provider unavailable — skipping backup.")
        return

    ts = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    prefix = f"{_BACKUP_PREFIX}/{s.environment}/"
    key = f"{prefix}{ts}.dump"
    fd, path = tempfile.mkstemp(suffix=".dump")
    os.close(fd)
    try:
        rc, stderr = await asyncio.to_thread(_run_pg_dump, dsn, path)
        if rc != 0:
            log.error("pg_dump failed (rc=%s): %s", rc, stderr[-500:])
            return
        data = await asyncio.to_thread(_read_dump, path)
        await provider.put_exact(
            object_key=key,
            data=data,
            content_type="application/octet-stream",
            visibility="private",
        )
        log.info("DB backup uploaded: %s (%d bytes)", key, len(data))
        await _prune(provider, prefix, s.backup_keep)
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def main() -> None:
    init_sentry()
    log.info("Fashion OS backup cron starting.")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
