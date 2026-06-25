"""Public display-name scrubbing (CLAUDE.md §10) — a raw email must never be
returned as a public name on any social surface."""

from __future__ import annotations

from app.services.display import contains_email, public_display_name, redact_emails


def test_plain_name_passes_through() -> None:
    assert public_display_name("Mim") == "Mim"


def test_name_is_trimmed() -> None:
    assert public_display_name("  Nadia  ") == "Nadia"


def test_bare_email_is_dropped() -> None:
    assert public_display_name("wearthemood24@gmail.com") is None


def test_email_embedded_in_name_is_dropped() -> None:
    assert public_display_name("me wearthemood24@gmail.com") is None


def test_empty_and_blank_are_dropped() -> None:
    assert public_display_name(None) is None
    assert public_display_name("") is None
    assert public_display_name("   ") is None


def test_falls_back_to_next_safe_candidate() -> None:
    # display_name is an email → fall through to the username.
    assert public_display_name("user@example.com", "stylequeen") == "stylequeen"
    # display_name empty → username used.
    assert public_display_name(None, "stylequeen") == "stylequeen"


def test_returns_none_when_every_candidate_is_unsafe() -> None:
    assert public_display_name("a@b.com", "  ", None) is None


# ── caption guards (public free-text must not leak an email, §10) ─────────────


def test_contains_email_detects_an_address() -> None:
    assert contains_email("reach me at wearthemood24@gmail.com") is True
    assert contains_email("wearthemood24@gmail.com") is True


def test_contains_email_false_for_clean_text() -> None:
    assert contains_email("loved this fit today") is False
    assert contains_email(None) is False
    assert contains_email("") is False


def test_redact_emails_replaces_the_token_keeps_rest() -> None:
    assert redact_emails("ping me a@b.com please") == "ping me [hidden] please"


def test_redact_emails_passes_clean_text_through() -> None:
    assert redact_emails("great look") == "great look"
    assert redact_emails(None) is None
    assert redact_emails("") == ""
