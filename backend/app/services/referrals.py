"""Referral loop (CLAUDE.md §24) — codes, redemption, rewards.

Each user has a unique referral_code. A new user redeems someone's code once;
both sides are granted bonus credits. All of it is server-verified — the client
never grants credits and can't redeem twice or use its own code (§11, §25).
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from urllib.parse import quote
from uuid import uuid4

import asyncpg

from app.core.config import get_settings
from app.core.credits import grant_credits
from app.core.errors import ApiError
from app.models.common import ErrorCode
from app.services.notifications import create_notification

log = logging.getLogger("fashionos.referrals")

# Unambiguous alphabet (no 0/O/1/I) so codes are easy to read/share.
_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_CODE_LEN = 8

_GRANT = """
    insert into public.credits (user_id, balance) values ($1::uuid, $2)
    on conflict (user_id) do update
      set balance = public.credits.balance + excluded.balance, updated_at = now()
"""


def gen_code() -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(_CODE_LEN))


async def get_or_create_code(conn: asyncpg.Connection, user_id: str) -> str:
    """The user's referral code, generated + persisted on first request. Retries
    on the rare code collision."""
    existing = await conn.fetchval(
        "select referral_code from public.profiles where id = $1::uuid", user_id
    )
    if existing:
        return existing
    for _ in range(5):
        code = gen_code()
        try:
            updated = await conn.fetchval(
                "update public.profiles set referral_code = $2 "
                "where id = $1::uuid and referral_code is null returning referral_code",
                user_id,
                code,
            )
        except asyncpg.UniqueViolationError:
            continue  # code already taken — try another
        if updated:
            return updated
        # Lost a race: another request set it first — read it back.
        existing = await conn.fetchval(
            "select referral_code from public.profiles where id = $1::uuid", user_id
        )
        if existing:
            return existing
    raise ApiError(ErrorCode.INTERNAL_ERROR, "Couldn't create a referral code.", 500)


async def referral_count(conn: asyncpg.Connection, user_id: str) -> int:
    return await conn.fetchval(
        "select count(*) from public.referrals where referrer_id = $1::uuid", user_id
    )


async def redeem(conn: asyncpg.Connection, user_id: str, code: str, *, reward: int) -> int:
    """Redeem a referral code: record it and grant `reward` credits to both
    sides. Returns the reward. Raises on an invalid/own/already-used code."""
    code = code.strip().upper()
    async with conn.transaction():
        referrer_id = await conn.fetchval(
            "select id from public.profiles where referral_code = $1", code
        )
        if referrer_id is None:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "That referral code isn't valid.", 422)
        if str(referrer_id) == user_id:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "You can't use your own code.", 422)
        try:
            await conn.execute(
                "insert into public.referrals (referee_id, referrer_id, code) "
                "values ($1::uuid, $2::uuid, $3)",
                user_id,
                str(referrer_id),
                code,
            )
        except asyncpg.UniqueViolationError as exc:
            raise ApiError(
                ErrorCode.VALIDATION_ERROR, "You've already used a referral code.", 422
            ) from exc
        await conn.execute(_GRANT, user_id, reward)
        await conn.execute(_GRANT, str(referrer_id), reward)
    return reward


# ── Referral REWARDS program (install attribution, §24) ─────────────────────
# The production flow: a public /r/<code> redirect mints an opaque, single-use,
# time-limited attribution token and forwards to the Play listing carrying it as
# the install `referrer`. After a genuinely NEW account installs + authenticates,
# it claims with that token; the REFERRER earns a persistent (top-up) bonus
# exactly once. The referred user earns 0 in this version. Server is the sole
# authority — amount + eligibility are never trusted from the client.


class ClaimStatus(StrEnum):
    awarded = "awarded"
    already_claimed = "already_claimed"
    not_eligible_existing_user = "not_eligible_existing_user"
    self_referral = "self_referral"
    invalid = "invalid"
    expired = "expired"
    reused = "reused"
    disabled = "disabled"


@dataclass(frozen=True)
class ClaimResult:
    status: ClaimStatus
    reward_credits: int = 0


def _sha256(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _install_hash(install_id: str | None) -> str | None:
    """HMAC a per-install id before storage so raw ids never sit in the DB and
    can't be rainbow-tabled. Returns None when no install id is provided (direct
    APK/ADB installs still work, just without the duplicate-install control)."""
    ident = (install_id or "").strip()
    if not ident:
        return None
    key = get_settings().referral_hmac_key.encode("utf-8")
    return hmac.new(key, ident.encode("utf-8"), hashlib.sha256).hexdigest()


def build_referral_url(code: str) -> str:
    base = get_settings().referral_public_base_url.rstrip("/")
    return f"{base}/r/{code}"


async def create_attribution(
    conn: asyncpg.Connection, code: str, *, platform: str = "android"
) -> tuple[str, datetime] | None:
    """Mint an opaque, single-use, time-limited attribution token for [code].
    Returns (raw_token, expires_at) or None when the code is unknown/disabled.
    The raw token is returned to the caller ONCE and never stored/logged — only
    its sha256 hash is persisted."""
    code = (code or "").strip().upper()
    if not code:
        return None
    referrer_id = await conn.fetchval(
        "select id from public.profiles where referral_code = $1", code
    )
    if referrer_id is None:
        return None
    settings = get_settings()
    raw = secrets.token_urlsafe(32)  # ~43 chars, 256 bits of entropy
    expires_at = datetime.now(UTC) + timedelta(days=settings.referral_attribution_window_days)
    await conn.execute(
        "insert into public.referral_attributions "
        "(token_hash, referrer_id, referral_code, platform, expires_at) "
        "values ($1, $2::uuid, $3, $4, $5)",
        _sha256(raw),
        str(referrer_id),
        code,
        platform,
        expires_at,
    )
    return raw, expires_at


async def resolve_redirect(conn: asyncpg.Connection, code: str) -> str:
    """Target URL for GET /r/<code>. A valid code records the click (mints a
    token) and returns the Play listing carrying it as the install `referrer`
    (only the opaque token + utm — never a UUID/email). An invalid/disabled code
    returns the plain landing page (never an exception or open redirect)."""
    settings = get_settings()
    landing = settings.referral_public_base_url.rstrip("/")
    if not settings.referral_enabled:
        return landing
    minted = await create_attribution(conn, code, platform="android")
    if minted is None:
        return landing  # unknown/disabled code → safe landing, no attribution
    raw, _ = minted
    referrer = quote(
        f"referral_token={raw}&utm_source=referral&utm_medium=share", safe=""
    )
    return f"{settings.referral_play_store_url}&referrer={referrer}"


async def referral_summary(conn: asyncpg.Connection, user_id: str) -> dict:
    """The signed-in user's referral standing for GET /v1/referrals/me. History
    is redacted — it never exposes a referred user's identity (§10)."""
    settings = get_settings()
    code = await get_or_create_code(conn, user_id)
    rows = await conn.fetch(
        "select reward_credits, credited_at from public.referral_claims "
        "where referrer_id = $1::uuid order by credited_at desc nulls last limit 10",
        user_id,
    )
    stats = await conn.fetchrow(
        "select count(*) as n, coalesce(sum(reward_credits), 0) as total "
        "from public.referral_claims where referrer_id = $1::uuid",
        user_id,
    )
    return {
        "referral_code": code,
        "referral_url": build_referral_url(code),
        "bonus_per_successful_referral": settings.referral_referrer_bonus_credits,
        "successful_referral_count": int(stats["n"]),
        "total_bonus_credits_earned": int(stats["total"]),
        "enabled": settings.referral_enabled,
        # Redacted history: only amount + when — never who.
        "recent": [
            {"reward_credits": r["reward_credits"], "credited_at": r["credited_at"]}
            for r in rows
        ],
    }


async def claim(
    conn: asyncpg.Connection,
    *,
    referred_user_id: str,
    token: str,
    install_id: str | None,
    platform: str = "android",
) -> ClaimResult:
    """Authoritatively resolve a referral claim (§24). ALL of these must hold to
    award: program enabled; a valid, unexpired, unconsumed token; a real referrer
    that differs from the referred user; a genuinely NEW referred account (created
    after the click, within tolerance); no prior claim by this user; no prior
    award from this installation. The reward goes to the REFERRER's persistent
    top-up bucket, once, idempotently. Everything else returns a reject status
    without granting. Concurrency- and retry-safe at the DB level."""
    settings = get_settings()
    if not settings.referral_enabled:
        return ClaimResult(ClaimStatus.disabled)
    if not token or not token.strip():
        return ClaimResult(ClaimStatus.invalid)

    token_hash = _sha256(token.strip())
    install_h = _install_hash(install_id)
    now = datetime.now(UTC)
    reward = settings.referral_referrer_bonus_credits
    tolerance = timedelta(seconds=settings.referral_new_account_tolerance_seconds)

    try:
        async with conn.transaction():
            # Idempotent: this user already has an award → return it, no re-grant.
            existing = await conn.fetchval(
                "select reward_credits from public.referral_claims "
                "where referred_user_id = $1::uuid",
                referred_user_id,
            )
            if existing is not None:
                return ClaimResult(ClaimStatus.already_claimed, existing)

            attr = await conn.fetchrow(
                "select id, referrer_id, expires_at, consumed_at, created_at "
                "from public.referral_attributions where token_hash = $1 for update",
                token_hash,
            )
            if attr is None:
                return ClaimResult(ClaimStatus.invalid)
            if attr["consumed_at"] is not None:
                return ClaimResult(ClaimStatus.reused)
            if attr["expires_at"] <= now:
                return ClaimResult(ClaimStatus.expired)

            referrer_id = str(attr["referrer_id"])
            if referrer_id == referred_user_id:
                return ClaimResult(ClaimStatus.self_referral)
            if not await conn.fetchval(
                "select 1 from public.profiles where id = $1::uuid", referrer_id
            ):
                return ClaimResult(ClaimStatus.invalid)

            # Genuinely NEW account: created after the click (minus tolerance).
            created = await conn.fetchval(
                "select created_at from auth.users where id = $1::uuid", referred_user_id
            )
            if created is None:
                return ClaimResult(ClaimStatus.invalid)
            if created < attr["created_at"] - tolerance:
                return ClaimResult(ClaimStatus.not_eligible_existing_user)

            # Installation already produced an award?
            if install_h is not None and await conn.fetchval(
                "select 1 from public.referral_claims where install_hash = $1", install_h
            ):
                return ClaimResult(ClaimStatus.reused)

            # Consume the token + record the award + grant + notify (one txn).
            claim_id = uuid4()
            credit_ref = f"referral:{claim_id}"
            await conn.execute(
                "update public.referral_attributions "
                "set consumed_at = now(), consumed_by = $2::uuid where id = $1",
                attr["id"],
                referred_user_id,
            )
            await conn.execute(
                "insert into public.referral_claims "
                "(id, referrer_id, referred_user_id, attribution_id, install_hash, "
                " platform, reward_credits, credit_ref, credited_at) "
                "values ($1, $2::uuid, $3::uuid, $4, $5, $6, $7, $8, now())",
                claim_id,
                referrer_id,
                referred_user_id,
                attr["id"],
                install_h,
                platform,
                reward,
                credit_ref,
            )
            # Grant to the REFERRER only — persistent (survives resets), idempotent.
            await grant_credits(
                conn,
                referrer_id,
                amount=reward,
                reason="referral_bonus",
                ref=credit_ref,
                target="topup",
            )
            await create_notification(
                conn,
                user_id=referrer_id,
                type="referral_reward",
                title=f"You earned {reward} referral credits",
                body="A friend joined Wear The Mood with your link.",
            )
            log.info(
                "referral awarded referrer=%s claim=%s platform=%s",
                referrer_id[:8],
                str(claim_id)[:8],
                platform,
            )
            return ClaimResult(ClaimStatus.awarded, reward)
    except (asyncpg.UniqueViolationError, asyncpg.ForeignKeyViolationError):
        # A concurrent claim landed first (referred_user / attribution / install),
        # or the referred profile isn't provisioned yet. Re-read for idempotency.
        existing = await conn.fetchval(
            "select reward_credits from public.referral_claims "
            "where referred_user_id = $1::uuid",
            referred_user_id,
        )
        if existing is not None:
            return ClaimResult(ClaimStatus.already_claimed, existing)
        return ClaimResult(ClaimStatus.reused)
