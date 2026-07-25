"""Style DNA result computation (FEATURES_COMMUNITY_PLUS · Style Quiz).

Rule-based + deterministic: each chosen option's `key` is a style trait; the
result is the user's dominant traits. (An LLM-written description could be layered
in via app.services.llm — the provider wrapper + ai_usage_log cost logging are
already used by the stylist — but rule-based keeps this fast, free and offline,
which matters while the Anthropic account has no credits.)
"""

from __future__ import annotations

from app.models.quiz import StyleResult

_TRAIT_LABEL = {
    "minimal": "Minimal",
    "classic": "Classic",
    "bold": "Bold",
    "earthy": "Earthy",
    "romantic": "Romantic",
    "street": "Street",
}

_TRAIT_PHRASE = {
    "minimal": "clean lines and understated neutrals",
    "classic": "timeless, tailored pieces",
    "bold": "statement colours and standout pieces",
    "earthy": "warm, natural tones and organic textures",
    "romantic": "soft, flowing, feminine touches",
    "street": "relaxed, urban, sneaker-ready looks",
}

_TRAIT_COLOR = {
    "minimal": "#9E9E9E",
    "classic": "#1A1A1A",
    "bold": "#B44C2E",
    "earthy": "#8B6B4A",
    "romantic": "#D9A7B0",
    "street": "#3A3A55",
}


def _join_phrases(phrases: list[str]) -> str:
    if len(phrases) == 1:
        return phrases[0]
    return ", ".join(phrases[:-1]) + " and " + phrases[-1]


def compute_style_result(answer_keys: list[str]) -> StyleResult:
    """Tally the chosen trait keys → the top (up to) 3 traits, with ties broken
    by first appearance, into a Style DNA card."""
    counts: dict[str, int] = {}
    order: list[str] = []
    for raw in answer_keys:
        key = raw.strip().lower()
        if key in _TRAIT_LABEL:
            if key not in counts:
                order.append(key)
                counts[key] = 0
            counts[key] += 1

    if not counts:  # answers didn't map to known traits — safe default
        order = ["classic"]
        counts = {"classic": 1}

    ranked = sorted(order, key=lambda k: (-counts[k], order.index(k)))
    top = ranked[:3]
    return StyleResult(
        title=" · ".join(_TRAIT_LABEL[k] for k in top),
        keywords=top,
        description="Your Style DNA blends " + _join_phrases([_TRAIT_PHRASE[k] for k in top]) + ".",
        palette=[_TRAIT_COLOR[k] for k in top],
    )
