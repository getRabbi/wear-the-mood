"""Safe public display names (CLAUDE.md §10).

A raw email — or any contact handle — must NEVER appear on a public/community
surface: the feed, a post, a comment, a public profile, the leaderboard, or a
notification. Some `profiles.display_name` values ended up holding an email
(user-entered or legacy), so every public boundary runs the stored name through
[public_display_name], which drops empty/email-like values. Callers fall back to
their own neutral label ("Someone") — never to the auth email.
"""

from __future__ import annotations

import re

# An email appearing ANYWHERE in the value (not just a full match), so values
# like "me me@example.com" are rejected too.
_EMAIL_RE = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")


def public_display_name(*candidates: str | None) -> str | None:
    """First candidate safe to show publicly: non-empty and not email-like.

    Used for the priority "display_name → username → (caller's own fallback)".
    Returns None when nothing is safe, so callers render their own neutral
    label and never leak an email (CLAUDE.md §10, §19)."""
    for candidate in candidates:
        if not candidate:
            continue
        name = candidate.strip()
        if not name or _EMAIL_RE.search(name):
            continue
        return name
    return None


def contains_email(text: str | None) -> bool:
    """True when [text] holds an email-like token. Used to keep raw emails out of
    public community content — captions/comments must not expose one (§10)."""
    return bool(text) and _EMAIL_RE.search(text) is not None


# Neutral marker for an email scrubbed from public free-text (legacy rows).
EMAIL_REDACTION = "[hidden]"


def redact_emails(text: str | None) -> str | None:
    """Replace any email-like token in public free-text (e.g. a legacy caption)
    with [EMAIL_REDACTION], so a raw email saved before validation can't show on
    a community surface (§10). Returns the text unchanged when it has none."""
    if not text:
        return text
    return _EMAIL_RE.sub(EMAIL_REDACTION, text)
