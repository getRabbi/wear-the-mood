"""Nightly DB backup cron (Phase 4B). Mocked pg_dump + R2 — no DB, no network."""

from __future__ import annotations

import asyncio
from types import SimpleNamespace

import app.cron.backup as backup
from app.services.media.r2 import R2StorageProvider


class _FakeProvider(R2StorageProvider):
    def __init__(self, existing: list[str] | None = None) -> None:
        self.puts: list[tuple[str, bytes, str]] = []
        self.deleted: list[str] = []
        self._existing = existing or []

    async def put_exact(self, *, object_key, data, content_type, visibility) -> None:
        self.puts.append((object_key, data, visibility))

    async def list_keys(self, *, prefix, visibility) -> list[str]:
        return list(self._existing)

    async def delete(self, *, object_key, visibility, thumbnail_key=None) -> None:
        self.deleted.append(object_key)


def _settings(**kw):
    base = {"environment": "prod", "r2_configured": True, "backup_keep": 7}
    base.update(kw)
    return SimpleNamespace(**base)


def test_backup_happy_path(monkeypatch) -> None:
    prov = _FakeProvider()
    monkeypatch.setattr(backup, "pick_migration_dsn", lambda env: ("dsn-5432", False))
    monkeypatch.setattr(backup, "get_settings", _settings)
    monkeypatch.setattr(backup, "get_storage_provider", lambda: prov)

    def fake_dump(dsn: str, out_path: str) -> tuple[int, str]:
        with open(out_path, "wb") as f:
            f.write(b"PGDMP-fake")
        return (0, "")

    monkeypatch.setattr(backup, "_run_pg_dump", fake_dump)

    asyncio.run(backup._run())

    assert len(prov.puts) == 1
    key, data, vis = prov.puts[0]
    assert key.startswith("backups/prod/") and key.endswith(".dump")
    assert vis == "private"
    assert data == b"PGDMP-fake"


def test_backup_skips_without_direct_5432(monkeypatch) -> None:
    prov = _FakeProvider()
    monkeypatch.setattr(backup, "pick_migration_dsn", lambda env: ("dsn-6543", True))  # fallback
    monkeypatch.setattr(backup, "get_settings", _settings)
    monkeypatch.setattr(backup, "get_storage_provider", lambda: prov)
    monkeypatch.setattr(backup, "_run_pg_dump", lambda d, p: (0, ""))

    asyncio.run(backup._run())
    assert prov.puts == []  # pg_dump can't use the pooler — skipped


def test_backup_no_upload_on_dump_failure(monkeypatch) -> None:
    prov = _FakeProvider()
    monkeypatch.setattr(backup, "pick_migration_dsn", lambda env: ("dsn-5432", False))
    monkeypatch.setattr(backup, "get_settings", _settings)
    monkeypatch.setattr(backup, "get_storage_provider", lambda: prov)
    monkeypatch.setattr(backup, "_run_pg_dump", lambda d, p: (1, "boom"))

    asyncio.run(backup._run())
    assert prov.puts == []


def test_prune_keeps_most_recent(monkeypatch) -> None:
    existing = [f"backups/prod/2026010{i}T000000Z.dump" for i in range(1, 10)]  # 9
    prov = _FakeProvider(existing=existing)
    asyncio.run(backup._prune(prov, "backups/prod/", keep=7))
    assert prov.deleted == sorted(existing)[:2]  # 2 oldest removed
