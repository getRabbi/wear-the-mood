"""Style Memory v1: signal folding, honesty rules, correction and reset.

The behaviour worth guarding hardest is the one that is easiest to get wrong:
a user who rejects a render because the FACE looked broken has told us nothing
about whether they like the clothes. If that ever starts moving taste weights,
the profile fills up with the app's own failures dressed as the user's opinions.
"""

from __future__ import annotations

import asyncio
import json

from app.services.style_memory import (
    FACETS,
    PreferenceEntry,
    StyleMemoryError,
    _facet_updates,
    apply_correction,
    build_summary,
    merge_entry,
    record_signal,
    reset,
)


class _FakeConn:
    """In-memory stand-in for the profile + signals tables."""

    def __init__(self) -> None:
        self.profile: dict | None = None
        self.signals: list[dict] = []
        self.dedupe: set[tuple] = set()

    @staticmethod
    def _norm(sql: str) -> str:
        return " ".join(sql.split()).lower()

    def _blank(self, user_id: str) -> dict:
        return {
            "user_id": user_id,
            "version": 1,
            "confidence": 0,
            "signal_count": 0,
            "personalization_enabled": True,
            "preference_summary": None,
            **{facet: "[]" for facet in FACETS},
        }

    def transaction(self):
        class _Tx:
            async def __aenter__(self_):
                return self_

            async def __aexit__(self_, *_a):
                return False

        return _Tx()

    async def execute(self, sql: str, *args):
        s = self._norm(sql)
        if "insert into public.style_memory_profiles" in s:
            if self.profile is None:
                self.profile = self._blank(args[0])
            return "INSERT 0 1"
        if "update public.style_memory_profiles" in s and "signal_count" in s:
            assert self.profile is not None
            for i, facet in enumerate(FACETS):
                self.profile[facet] = args[i + 1]
            self.profile["signal_count"] = args[len(FACETS) + 1]
            self.profile["confidence"] = args[len(FACETS) + 2]
            self.profile["preference_summary"] = args[len(FACETS) + 3]
            return "UPDATE 1"
        if "update public.style_memory_profiles" in s and "personalization_enabled" in s:
            assert self.profile is not None
            self.profile["personalization_enabled"] = args[1]
            return "UPDATE 1"
        if "insert into public.style_memory_signals" in s:
            self.signals.append({"signal_type": args[1], "value": args[3]})
            return "INSERT 0 1"
        if "delete from public.style_memory_profiles" in s:
            self.profile = None
            return "DELETE 1"
        return "OK"

    async def fetchrow(self, sql: str, *args):
        s = self._norm(sql)
        if "from public.style_memory_profiles" in s:
            return self.profile
        return None

    async def fetchval(self, sql: str, *args):
        s = self._norm(sql)
        if "insert into public.style_memory_signals" in s:
            key = (args[0], args[8])
            if args[8] is not None and key in self.dedupe:
                return None
            if args[8] is not None:
                self.dedupe.add(key)
            self.signals.append({"signal_type": args[1], "value": args[4], "context": args[7]})
            return "signal-id"
        if "delete from public.style_memory_signals" in s:
            count = len(self.signals)
            self.signals.clear()
            return count
        return None

    # Convenience for assertions
    def facet(self, name: str) -> list[dict]:
        assert self.profile is not None
        raw = self.profile[name]
        return json.loads(raw) if isinstance(raw, str) else raw


# ── the honesty rules ────────────────────────────────────────────────────────


def test_a_broken_face_teaches_nothing_about_taste() -> None:
    """An identity failure is OUR bug. It must not become "they hate navy"."""
    updates = _facet_updates(
        "reject_look", None, {"colors": ["navy"], "silhouettes": ["blazer"]}, "identity_issue"
    )
    assert updates == []


def test_a_mangled_garment_teaches_nothing_about_taste() -> None:
    updates = _facet_updates("reject_look", None, {"colors": ["navy"]}, "garment_issue")
    assert updates == []


def test_body_proportion_complaints_teach_nothing_about_taste() -> None:
    updates = _facet_updates("reject_look", None, {"colors": ["navy"]}, "body_proportion_issue")
    assert updates == []


def test_a_colour_rejection_records_an_avoided_colour() -> None:
    updates = _facet_updates("reject_look", None, {"colors": ["mustard"]}, "color_issue")
    assert ("avoided_colors", "mustard", 1.0) in updates


def test_not_my_style_records_an_avoided_silhouette() -> None:
    updates = _facet_updates(
        "reject_look", None, {"colors": ["black"], "silhouettes": ["oversized"]}, "not_my_style"
    )
    facets = {facet for facet, _, _ in updates}
    assert facets == {"avoided_silhouettes", "avoided_colors"}


def test_an_occasion_mismatch_blames_the_context_not_the_clothes() -> None:
    updates = _facet_updates(
        "reject_look", None, {"colors": ["black"], "silhouettes": ["gown"]}, "occasion_mismatch"
    )
    assert updates == []


def test_an_unknown_rejection_reason_is_rejected() -> None:
    conn = _FakeConn()
    try:
        asyncio.run(
            record_signal(
                conn,  # type: ignore[arg-type]
                "u",
                signal_type="reject_look",
                context={"reason": "because_i_said_so"},
            )
        )
    except StyleMemoryError:
        return
    raise AssertionError("an unknown reason must not be accepted")


# ── confidence must not overstate ────────────────────────────────────────────


def test_one_observation_is_not_a_fact() -> None:
    entries = merge_entry([], "black", weight=1.0, source="inferred")
    assert entries[0].confidence < 0.35
    assert build_summary({"preferred_colors": [e.as_json() for e in entries]}) is None


def test_repetition_earns_confidence() -> None:
    entries: list[PreferenceEntry] = []
    for _ in range(3):
        entries = merge_entry(entries, "black", weight=1.0, source="inferred")
    assert entries[0].confidence >= 0.35
    summary = build_summary({"preferred_colors": [e.as_json() for e in entries]})
    assert summary is not None
    assert "black" in summary
    # Hedged, never declarative.
    assert "seem" in summary.lower()


def test_inference_never_reaches_certainty() -> None:
    entries: list[PreferenceEntry] = []
    for _ in range(50):
        entries = merge_entry(entries, "black", weight=1.0, source="inferred")
    assert entries[0].confidence < 1.0


def test_a_stated_preference_is_certain_immediately() -> None:
    entries = merge_entry([], "olive", weight=1.0, source="stated")
    assert entries[0].confidence == 1.0
    assert entries[0].source == "stated"


def test_an_inference_cannot_demote_a_stated_preference() -> None:
    entries = merge_entry([], "olive", weight=1.0, source="stated")
    entries = merge_entry(entries, "olive", weight=1.0, source="inferred")
    assert entries[0].source == "stated"
    assert entries[0].confidence == 1.0


# ── recording ────────────────────────────────────────────────────────────────


def test_keeping_a_look_records_its_colours() -> None:
    conn = _FakeConn()
    for _ in range(3):
        asyncio.run(
            record_signal(
                conn,  # type: ignore[arg-type]
                "u",
                signal_type="keep_look",
                context={"colors": ["charcoal"], "silhouettes": ["tailored"]},
                dedupe_key=None,
            )
        )
    values = [e["value"] for e in conn.facet("preferred_colors")]
    assert values == ["charcoal"]
    assert conn.profile is not None
    assert conn.profile["signal_count"] == 3


def test_a_dedupe_key_makes_a_retry_a_no_op() -> None:
    conn = _FakeConn()
    first = asyncio.run(
        record_signal(
            conn,  # type: ignore[arg-type]
            "u",
            signal_type="keep_look",
            context={"colors": ["black"]},
            dedupe_key="result-1:kept",
        )
    )
    second = asyncio.run(
        record_signal(
            conn,  # type: ignore[arg-type]
            "u",
            signal_type="keep_look",
            context={"colors": ["black"]},
            dedupe_key="result-1:kept",
        )
    )
    assert (first, second) == (True, False)
    assert conn.profile is not None
    assert conn.profile["signal_count"] == 1
    assert conn.facet("preferred_colors")[0]["weight"] == 1.5


def test_a_rejection_we_do_not_learn_from_still_counts_as_observation() -> None:
    conn = _FakeConn()
    asyncio.run(
        record_signal(
            conn,  # type: ignore[arg-type]
            "u",
            signal_type="reject_look",
            context={"reason": "identity_issue", "colors": ["navy"]},
        )
    )
    assert conn.profile is not None
    assert conn.profile["signal_count"] == 1
    assert conn.facet("avoided_colors") == []


def test_a_mood_selection_lands_on_moods_not_colours() -> None:
    conn = _FakeConn()
    asyncio.run(
        record_signal(
            conn,  # type: ignore[arg-type]
            "u",
            signal_type="mood_selected",
            value="calm",
        )
    )
    assert [e["value"] for e in conn.facet("preferred_moods")] == ["calm"]
    assert conn.facet("preferred_colors") == []


# ── user control ─────────────────────────────────────────────────────────────


def test_a_correction_states_the_preference_outright() -> None:
    conn = _FakeConn()
    profile = asyncio.run(
        apply_correction(
            conn,
            "u",
            facet="preferred_colors",
            value="Olive",  # type: ignore[arg-type]
        )
    )
    entry = profile["preferred_colors"][0]
    assert entry["value"] == "olive"  # normalized
    assert entry["source"] == "stated"
    assert entry["confidence"] == 1.0


def test_removing_a_preference_takes_only_that_one() -> None:
    conn = _FakeConn()
    asyncio.run(
        apply_correction(conn, "u", facet="preferred_colors", value="olive")  # type: ignore[arg-type]
    )
    asyncio.run(
        apply_correction(conn, "u", facet="preferred_colors", value="black")  # type: ignore[arg-type]
    )
    profile = asyncio.run(
        apply_correction(
            conn,  # type: ignore[arg-type]
            "u",
            facet="preferred_colors",
            value="olive",
            remove=True,
        )
    )
    assert [e["value"] for e in profile["preferred_colors"]] == ["black"]


def test_an_unknown_facet_is_rejected() -> None:
    conn = _FakeConn()
    try:
        asyncio.run(
            apply_correction(
                conn,
                "u",
                facet="favourite_pizza",
                value="margherita",  # type: ignore[arg-type]
            )
        )
    except StyleMemoryError:
        return
    raise AssertionError("an unknown facet must not be accepted")


def test_reset_deletes_the_signals_and_the_profile() -> None:
    conn = _FakeConn()
    asyncio.run(
        record_signal(
            conn,
            "u",
            signal_type="keep_look",
            context={"colors": ["black"]},  # type: ignore[arg-type]
        )
    )
    deleted = asyncio.run(reset(conn, "u"))  # type: ignore[arg-type]
    assert deleted == 1
    assert conn.profile is None
    assert conn.signals == []
