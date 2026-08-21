"""Style Memory v1 — what WTM has learned about a user's taste (spec §12).

The retention moat, deliberately built as the SIMPLEST thing that is genuinely
useful: no model training, no embedding pipeline, no LLM call. A signal arrives,
it moves a weight, the summary is recomputed from the weights. That is the whole
system, and it works from the very first signal.

Three properties matter more than sophistication here:

  1. **It is legible.** Every preference names its own evidence weight, its
     confidence and whether the user STATED it or we inferred it. "Why does WTM
     think this?" has an answer.
  2. **It is honest.** A preference below `_STATE_THRESHOLD` is never phrased as
     a fact (§12.3). We would rather say nothing than tell someone they hate
     oversized jackets on the strength of two renders.
  3. **It separates taste from quality.** A user who rejects a render because
     the FACE looks wrong has told us nothing about whether they like the
     clothes. Only genuinely aesthetic rejections move taste weights — see
     `_TASTE_REJECTIONS`. Getting this backwards would poison the profile with
     the app's own failures.

Everything here is additive and reversible: the user can view, correct, remove a
single inferred preference, turn personalization off without losing their data,
or reset the whole thing.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

import asyncpg

log = logging.getLogger("fashionos.style_memory")

#: Server flag gating every write path below.
FLAG_STYLE_MEMORY = "feature_style_memory"

#: The facets a preference can belong to. Each is a jsonb array column on
#: `style_memory_profiles` holding entry objects.
FACETS = (
    "preferred_colors",
    "avoided_colors",
    "preferred_silhouettes",
    "avoided_silhouettes",
    "preferred_aesthetics",
    "preferred_occasions",
    "preferred_moods",
    "fit_visual_preferences",
)

#: Structured reasons a user can give for "Not me" (§12.1). Kept in one place so
#: the API, the DB constraint and the app all agree on the vocabulary.
REJECTION_REASONS = (
    "identity_issue",
    "garment_issue",
    "not_my_style",
    "body_proportion_issue",
    "color_issue",
    "occasion_mismatch",
    "other",
)

#: The ONLY rejection reasons that say something about taste. The rest are
#: complaints about render quality: a corrupted face or a mangled garment tells
#: us our pipeline failed, not that the user dislikes navy. Treating those as
#: taste would teach the profile to avoid whatever we happened to render badly.
_TASTE_REJECTIONS = frozenset({"not_my_style", "color_issue", "occasion_mismatch"})

#: Signal types that are recorded but never move a weight on their own.
_NEUTRAL_SIGNALS = frozenset({"preference_removed"})

#: A preference is only spoken aloud above this confidence (§12.3).
_STATE_THRESHOLD = 0.35

#: Evidence weight at which a single inferred preference reaches full
#: confidence. Five consistent signals is a real pattern; one is a coincidence.
_FULL_EVIDENCE = 5.0

#: How many signals before the PROFILE as a whole is considered established.
_PROFILE_EVIDENCE = 12.0

#: Cap on entries kept per facet. Prevents an unbounded jsonb array (§50) and
#: keeps the "what WTM knows" screen readable.
_MAX_ENTRIES = 12


class StyleMemoryError(Exception):
    """Invalid Style Memory input (unknown facet, unknown reason)."""


@dataclass(frozen=True)
class PreferenceEntry:
    value: str
    weight: float
    confidence: float
    source: str  # 'inferred' | 'stated'
    updated_at: str

    def as_json(self) -> dict[str, Any]:
        return {
            "value": self.value,
            "weight": round(self.weight, 3),
            "confidence": round(self.confidence, 3),
            "source": self.source,
            "updated_at": self.updated_at,
        }


def _now() -> str:
    return datetime.now(UTC).isoformat()


def _confidence_for(weight: float, source: str) -> float:
    """A stated preference is certain; an inferred one earns confidence with
    repetition and never quite reaches 1.0 on its own."""
    if source == "stated":
        return 1.0
    return round(min(0.95, max(0.0, weight) / _FULL_EVIDENCE), 3)


def _jsonb(raw: object) -> list[dict[str, Any]]:
    if raw is None:
        return []
    if isinstance(raw, str):
        try:
            return json.loads(raw) or []
        except json.JSONDecodeError:
            return []
    return list(raw)  # type: ignore[arg-type]


def _entries(raw: object) -> list[PreferenceEntry]:
    out: list[PreferenceEntry] = []
    for item in _jsonb(raw):
        if not isinstance(item, dict) or not item.get("value"):
            continue
        weight = float(item.get("weight") or 0)
        source = str(item.get("source") or "inferred")
        out.append(
            PreferenceEntry(
                value=str(item["value"]),
                weight=weight,
                confidence=float(item.get("confidence") or _confidence_for(weight, source)),
                source=source,
                updated_at=str(item.get("updated_at") or _now()),
            )
        )
    return out


def merge_entry(
    entries: list[PreferenceEntry], value: str, *, weight: float, source: str
) -> list[PreferenceEntry]:
    """Fold one observation into a facet's entries.

    A STATED preference overrides an inferred one outright — the user telling us
    something is not more evidence, it is the answer. Inferred observations
    accumulate weight, and a stated entry is never demoted back to inferred by a
    later inference.
    """
    value = value.strip().lower()
    if not value:
        return entries
    kept: list[PreferenceEntry] = []
    found = False
    for entry in entries:
        if entry.value != value:
            kept.append(entry)
            continue
        found = True
        if source == "stated":
            new_weight = max(entry.weight, _FULL_EVIDENCE)
            new_source = "stated"
        elif entry.source == "stated":
            # Already settled by the user; keep their answer, note the evidence.
            new_weight = entry.weight + weight
            new_source = "stated"
        else:
            new_weight = entry.weight + weight
            new_source = "inferred"
        kept.append(
            PreferenceEntry(
                value=value,
                weight=new_weight,
                confidence=_confidence_for(new_weight, new_source),
                source=new_source,
                updated_at=_now(),
            )
        )
    if not found:
        start = max(weight, _FULL_EVIDENCE) if source == "stated" else weight
        kept.append(
            PreferenceEntry(
                value=value,
                weight=start,
                confidence=_confidence_for(start, source),
                source=source,
                updated_at=_now(),
            )
        )
    kept.sort(key=lambda e: (-e.weight, e.value))
    return kept[:_MAX_ENTRIES]


def _top(entries: list[PreferenceEntry]) -> PreferenceEntry | None:
    """The strongest entry that is confident enough to speak about."""
    for entry in entries:
        if entry.confidence >= _STATE_THRESHOLD:
            return entry
    return None


def build_summary(profile: dict[str, Any]) -> str | None:
    """One restrained sentence, or None when we do not know enough yet.

    Hedged on purpose ("seems to lean", "lately"). WTM describes a tendency it
    has observed; it does not tell the user who they are.
    """
    colors = _top(_entries(profile.get("preferred_colors")))
    silhouettes = _top(_entries(profile.get("preferred_silhouettes")))
    aesthetics = _top(_entries(profile.get("preferred_aesthetics")))
    parts: list[str] = []
    if colors:
        parts.append(f"{colors.value} tones")
    if silhouettes:
        parts.append(f"{silhouettes.value} shapes")
    if aesthetics:
        parts.append(f"a {aesthetics.value} feel")
    if not parts:
        return None
    if len(parts) == 1:
        body = parts[0]
    elif len(parts) == 2:
        body = f"{parts[0]} and {parts[1]}"
    else:
        body = f"{parts[0]}, {parts[1]} and {parts[2]}"
    return f"Lately you seem to lean toward {body}."


async def ensure_profile(conn: asyncpg.Connection, user_id: str) -> asyncpg.Record:
    """The user's profile row, created empty on first touch."""
    await conn.execute(
        "insert into public.style_memory_profiles (user_id) values ($1::uuid) "
        "on conflict (user_id) do nothing",
        user_id,
    )
    row = await conn.fetchrow(
        "select * from public.style_memory_profiles where user_id = $1::uuid", user_id
    )
    assert row is not None
    return row


async def get_profile(conn: asyncpg.Connection, user_id: str) -> dict[str, Any]:
    """The profile as plain JSON-ready data. Returns the empty shape when the
    user has no row — "we have learned nothing" is a valid answer, not a 404."""
    row = await conn.fetchrow(
        "select * from public.style_memory_profiles where user_id = $1::uuid", user_id
    )
    if row is None:
        return {
            "version": 1,
            "confidence": 0.0,
            "signal_count": 0,
            "personalization_enabled": True,
            "preference_summary": None,
            **{facet: [] for facet in FACETS},
        }
    out: dict[str, Any] = {
        "version": row["version"],
        "confidence": float(row["confidence"]),
        "signal_count": row["signal_count"],
        "personalization_enabled": row["personalization_enabled"],
        "preference_summary": row["preference_summary"],
    }
    for facet in FACETS:
        out[facet] = [e.as_json() for e in _entries(row[facet])]
    return out


async def _write_profile(
    conn: asyncpg.Connection,
    user_id: str,
    facets: dict[str, list[PreferenceEntry]],
    *,
    signal_delta: int,
) -> None:
    """Persist changed facets + recompute the summary. Only the facets actually
    touched are written, so two concurrent signals on different facets cannot
    clobber each other's work."""
    current = await ensure_profile(conn, user_id)
    merged = {facet: _entries(current[facet]) for facet in FACETS}
    merged.update(facets)
    signal_count = max(0, current["signal_count"] + signal_delta)
    confidence = round(min(1.0, signal_count / _PROFILE_EVIDENCE), 3)
    summary = build_summary({facet: [e.as_json() for e in merged[facet]] for facet in FACETS})
    await conn.execute(
        f"""
        update public.style_memory_profiles
           set {", ".join(f"{facet} = ${i + 2}::jsonb" for i, facet in enumerate(FACETS))},
               signal_count = ${len(FACETS) + 2},
               confidence = ${len(FACETS) + 3},
               preference_summary = ${len(FACETS) + 4},
               updated_at = now()
         where user_id = $1::uuid
        """,
        user_id,
        *[json.dumps([e.as_json() for e in merged[facet]]) for facet in FACETS],
        signal_count,
        confidence,
        summary,
    )


#: How a signal maps onto facets. `weight` is the evidence one occurrence is
#: worth: an explicit keep counts for more than a passing mood tap.
_POSITIVE_WEIGHTS = {
    "keep_look": 1.5,
    "save_look": 1.0,
    "share_look": 1.0,
    "wear_again": 1.0,
    "save_product": 0.5,
    "mood_selected": 0.4,
    "occasion_selected": 0.4,
    "event_planned": 0.5,
}


def _facet_updates(
    signal_type: str,
    value: str | None,
    context: dict[str, Any],
    reason: str | None,
) -> list[tuple[str, str, float]]:
    """(facet, value, weight) triples this signal implies. Pure, so the mapping
    is testable without a database."""
    updates: list[tuple[str, str, float]] = []
    if signal_type in _NEUTRAL_SIGNALS:
        return updates

    colors = [str(c) for c in (context.get("colors") or []) if c]
    silhouettes = [str(s) for s in (context.get("silhouettes") or []) if s]
    aesthetics = [str(a) for a in (context.get("aesthetics") or []) if a]

    if signal_type == "reject_look":
        # Only aesthetic rejections teach taste. A broken face or a mangled
        # garment is our failure, and must not be recorded as the user's
        # dislike of whatever they happened to be wearing.
        if reason not in _TASTE_REJECTIONS:
            return updates
        weight = 1.0
        if reason == "color_issue":
            updates += [("avoided_colors", c, weight) for c in colors]
        elif reason == "occasion_mismatch":
            # Nothing generalizable about the clothes — the CONTEXT was wrong.
            return updates
        else:  # not_my_style
            updates += [("avoided_silhouettes", s, weight) for s in silhouettes]
            updates += [("avoided_colors", c, weight * 0.5) for c in colors]
        return updates

    weight = _POSITIVE_WEIGHTS.get(signal_type, 0.5)
    if signal_type == "mood_selected" and value:
        return [("preferred_moods", value, weight)]
    if signal_type == "occasion_selected" and value:
        return [("preferred_occasions", value, weight)]
    if signal_type == "event_planned" and value:
        return [("preferred_occasions", value, weight)]

    updates += [("preferred_colors", c, weight) for c in colors]
    updates += [("preferred_silhouettes", s, weight) for s in silhouettes]
    updates += [("preferred_aesthetics", a, weight) for a in aesthetics]
    if value and signal_type in ("manual_preference",):
        updates.append(("preferred_aesthetics", value, weight))
    return updates


async def record_signal(
    conn: asyncpg.Connection,
    user_id: str,
    *,
    signal_type: str,
    entity_type: str | None = None,
    entity_id: str | None = None,
    value: str | None = None,
    weight: float = 1.0,
    source: str = "inferred",
    context: dict[str, Any] | None = None,
    dedupe_key: str | None = None,
) -> bool:
    """Record one signal and fold it into the summary.

    Returns False when `dedupe_key` has already been seen — the caller's retry
    is then a genuine no-op rather than a second vote (§9). The insert and the
    summary update share a transaction, so a crash between them cannot leave a
    signal that never counted.
    """
    context = context or {}
    reason = context.get("reason")
    if signal_type == "reject_look" and reason not in REJECTION_REASONS:
        raise StyleMemoryError(f"unknown rejection reason: {reason}")

    async with conn.transaction():
        inserted = await conn.fetchval(
            """
            insert into public.style_memory_signals
              (user_id, signal_type, entity_type, entity_id, value, weight,
               source, context, dedupe_key)
            values ($1::uuid, $2, $3, $4, $5, $6, $7, $8::jsonb, $9)
            on conflict (user_id, dedupe_key) where dedupe_key is not null
            do nothing
            returning id
            """,
            user_id,
            signal_type,
            entity_type,
            entity_id,
            value,
            weight,
            source,
            json.dumps(context),
            dedupe_key,
        )
        if inserted is None:
            return False

        updates = _facet_updates(signal_type, value, context, reason)
        if not updates:
            # Still counts toward how much we have observed, even when it moves
            # no weight — a rejection we deliberately do not learn from is
            # evidence that we have been watching.
            await _write_profile(conn, user_id, {}, signal_delta=1)
            return True

        current = await ensure_profile(conn, user_id)
        facets: dict[str, list[PreferenceEntry]] = {}
        for facet, item, item_weight in updates:
            if facet not in FACETS:
                continue
            existing = facets.get(facet) or _entries(current[facet])
            facets[facet] = merge_entry(existing, item, weight=item_weight * weight, source=source)
        await _write_profile(conn, user_id, facets, signal_delta=1)
        return True


async def apply_correction(
    conn: asyncpg.Connection,
    user_id: str,
    *,
    facet: str,
    value: str,
    remove: bool = False,
) -> dict[str, Any]:
    """The user's own edit (§12.2). Adding states a preference outright;
    removing deletes that single inferred entry without touching the rest.

    Either way a `preference_correction` signal is appended, so the audit trail
    shows the user overruled us rather than pretending we guessed right.
    """
    if facet not in FACETS:
        raise StyleMemoryError(f"unknown facet: {facet}")
    normalized = value.strip().lower()
    if not normalized:
        raise StyleMemoryError("value must not be empty")

    async with conn.transaction():
        current = await ensure_profile(conn, user_id)
        entries = _entries(current[facet])
        if remove:
            entries = [e for e in entries if e.value != normalized]
        else:
            entries = merge_entry(entries, normalized, weight=_FULL_EVIDENCE, source="stated")
        await conn.execute(
            """
            insert into public.style_memory_signals
              (user_id, signal_type, entity_type, entity_id, value, weight,
               source, context)
            values ($1::uuid, $2, 'preference', $3, $4, 1, 'stated', $5::jsonb)
            """,
            user_id,
            "preference_removed" if remove else "preference_correction",
            facet,
            normalized,
            json.dumps({"facet": facet, "removed": remove}),
        )
        await _write_profile(conn, user_id, {facet: entries}, signal_delta=0)
    return await get_profile(conn, user_id)


async def set_personalization(
    conn: asyncpg.Connection, user_id: str, *, enabled: bool
) -> dict[str, Any]:
    """Turn personalization off WITHOUT deleting anything. A user who wants us
    to stop using their taste should not have to destroy it to say so."""
    await ensure_profile(conn, user_id)
    await conn.execute(
        "update public.style_memory_profiles set personalization_enabled = $2, "
        "updated_at = now() where user_id = $1::uuid",
        user_id,
        enabled,
    )
    return await get_profile(conn, user_id)


async def reset(conn: asyncpg.Connection, user_id: str) -> int:
    """Erase this user's Style Memory. Returns how many signals were deleted.

    Scoped to one user by the WHERE clause AND by RLS; the service role bypasses
    RLS, so the scoping here is the real guard and is deliberately explicit.
    """
    async with conn.transaction():
        deleted = await conn.fetchval(
            "with gone as (delete from public.style_memory_signals "
            "where user_id = $1::uuid returning 1) select count(*) from gone",
            user_id,
        )
        await conn.execute(
            "delete from public.style_memory_profiles where user_id = $1::uuid", user_id
        )
    return int(deleted or 0)


async def look_attributes(conn: asyncpg.Connection, job_id: str) -> dict[str, list[str]]:
    """The describable attributes of a rendered look: the colours and canonical
    shapes of the garments it actually applied.

    Read from the user's OWN wardrobe rows — never inferred from the image, and
    never from anything the client sent. A look whose pieces we hold no rows for
    (a sample-rack garment) simply yields nothing, which is the correct answer.
    """
    row = await conn.fetchrow(
        "select applied_item_keys, selected_item_keys from public.tryon_jobs where id = $1::uuid",
        job_id,
    )
    if row is None:
        return {"colors": [], "silhouettes": []}
    keys = list(row["applied_item_keys"] or row["selected_item_keys"] or [])
    item_ids = [k[2:] for k in keys if k.startswith("w:")]
    if not item_ids:
        return {"colors": [], "silhouettes": []}
    rows = await conn.fetch(
        "select color, category, subcategory from public.wardrobe_items where id = any($1::uuid[])",
        item_ids,
    )
    colors = sorted({str(r["color"]).lower() for r in rows if r["color"]})
    silhouettes = sorted(
        {
            str(r["subcategory"] or r["category"]).lower()
            for r in rows
            if (r["subcategory"] or r["category"])
        }
    )
    return {"colors": colors, "silhouettes": silhouettes}
