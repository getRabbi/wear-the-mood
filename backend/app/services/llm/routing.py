"""Text-LLM routing + a shared OpenAI chat helper (CLAUDE.md §2.1).

`provider_order()` decides which backends are usable and in what order (primary
first, the other as automatic fallback). `openai_chat_json()` is the one place
the OpenAI chat SDK is called for the stylist / news / packing text tasks, so
those providers stay thin.
"""

from __future__ import annotations

from app.core.config import get_settings, is_secret_set


def provider_order() -> list[str]:
    """Usable text backends, best first: ['anthropic','openai'] (or reversed by
    LLM_PRIMARY), filtered to whichever keys are actually set."""
    s = get_settings()
    available = {
        "anthropic": is_secret_set(s.anthropic_api_key),
        "openai": is_secret_set(s.openai_api_key),
    }
    order = ["openai", "anthropic"] if s.llm_primary == "openai" else ["anthropic", "openai"]
    return [name for name in order if available[name]]


async def openai_chat_json(
    api_key: str, model: str, system: str, user: str, *, max_tokens: int
) -> tuple[str, int | None, int | None]:
    """One OpenAI chat completion → (text, input_tokens, output_tokens). Lazy-
    imports the SDK so importing this module never requires it."""
    from openai import AsyncOpenAI

    resp = await AsyncOpenAI(api_key=api_key).chat.completions.create(
        model=model,
        max_tokens=max_tokens,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    )
    text = resp.choices[0].message.content or ""
    usage = resp.usage
    in_tok = usage.prompt_tokens if usage else None
    out_tok = usage.completion_tokens if usage else None
    return text, in_tok, out_tok
