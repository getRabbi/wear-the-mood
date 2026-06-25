"""Claude vision garment tagger (CLAUDE.md §2.1) — MIT SDK, commercial API.

Lazy-imports the anthropic SDK (worker-only dep). Asks for compact JSON and
parses it tolerantly. Token usage is returned for cost logging (§14).
"""

from __future__ import annotations

import base64
import json

from app.services.llm.base import GarmentTagger, GarmentTags

_SYSTEM = (
    "You are a fashion cataloguer. Given a photo of a single clothing item, reply "
    "with ONLY compact JSON (no prose, no markdown) with keys: "
    'category (one of "Tops","Bottoms","Outerwear","Shoes","Accessories","Dresses" or null), '
    "subcategory (e.g. t-shirt, jeans, sneakers), "
    "color (primary color word), "
    "pattern (e.g. solid, striped, floral, checked or null), "
    "tags (array of 3-6 lowercase descriptive keywords)."
)


def _extract_json(text: str) -> dict:
    text = text.strip()
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end <= start:
        return {}
    try:
        parsed = json.loads(text[start : end + 1])
    except (ValueError, TypeError):
        return {}
    return parsed if isinstance(parsed, dict) else {}


class AnthropicGarmentTagger(GarmentTagger):
    name = "anthropic"

    def __init__(self, api_key: str, model: str) -> None:
        from anthropic import AsyncAnthropic

        # Bounded timeout + a single retry so a slow/overloaded tagging call can't
        # stall the single worker loop (it would hold up the cutout reveal of the
        # NEXT item + try-on jobs). Tagging is best-effort anyway (CLAUDE.md §2.1).
        self._client = AsyncAnthropic(api_key=api_key, timeout=30.0, max_retries=1)
        self._model = model

    async def tag(self, image: bytes, media_type: str) -> GarmentTags:
        b64 = base64.standard_b64encode(image).decode("ascii")
        msg = await self._client.messages.create(
            model=self._model,
            max_tokens=300,
            system=_SYSTEM,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {"type": "base64", "media_type": media_type, "data": b64},
                        },
                        {"type": "text", "text": "Catalogue this item as JSON."},
                    ],
                }
            ],
        )
        text = "".join(block.text for block in msg.content if block.type == "text")
        data = _extract_json(text)
        return GarmentTags(
            category=data.get("category"),
            subcategory=data.get("subcategory"),
            color=data.get("color"),
            pattern=data.get("pattern"),
            tags=[str(t).lower() for t in (data.get("tags") or [])][:6],
            input_tokens=msg.usage.input_tokens,
            output_tokens=msg.usage.output_tokens,
        )
