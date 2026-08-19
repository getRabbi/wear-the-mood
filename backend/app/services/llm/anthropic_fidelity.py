"""Claude vision garment-fidelity judge (CLAUDE.md §2.1, §19).

Answers ONE question about a finished try-on: is the person wearing the garment
that was actually selected, or has the model quietly designed a different one?

Why a vision model rather than an image metric: the two images being compared
are a flat garment photo and that garment worn by a person. Pose, drape, folds,
shadow and crop all differ by construction, so every pixel/embedding distance
that is tight enough to catch "a top came back as a cropped shirt" also rejects
correct renders. The failures we must catch are CATEGORICAL — garment family,
sleeve length, hem length, dominant colour, print, presence — and a categorical
question is what a vision model answers reliably and cheaply.

Runs on the cheap vision model already configured for garment tagging, and asks
for compact JSON parsed tolerantly, exactly as that tagger does.
"""

from __future__ import annotations

import base64
import json

from app.services.llm.base import (
    GarmentFidelityFinding,
    GarmentFidelityJudge,
    GarmentFidelityReport,
)

#: Stable rejection codes. These are counted and alerted on, so the wording of
#: the prompt may change but these may not.
CODE_GARMENT_CLASS = "garment_class_changed"
CODE_SLEEVE = "sleeve_length_changed"
CODE_LENGTH = "garment_length_changed"
CODE_COLOR = "dominant_color_changed"
CODE_PRINT = "print_changed"
CODE_MISSING = "garment_missing"

ALL_CODES = (
    CODE_GARMENT_CLASS,
    CODE_SLEEVE,
    CODE_LENGTH,
    CODE_COLOR,
    CODE_PRINT,
    CODE_MISSING,
)

_SYSTEM = (
    "You are a quality inspector for a virtual try-on service. You are given "
    "TWO images: first a REFERENCE photo of a single garment, then a RENDER of a "
    "person supposedly wearing that same garment.\n\n"
    "Decide whether the render shows THAT garment. Judge identity, not "
    "photographic similarity. Pose, body shape, lighting, shadows, folds, drape, "
    "wrinkles, framing and small colour-temperature shifts are EXPECTED and are "
    "never faults.\n\n"
    "Report a fault ONLY when you are confident a material property changed:\n"
    f"  {CODE_GARMENT_CLASS}: it became a different kind of garment "
    "(a t-shirt rendered as a button-up shirt, a jacket, a dress...).\n"
    f"  {CODE_SLEEVE}: sleeve length clearly changed "
    "(long sleeves became short or sleeveless, or the reverse).\n"
    f"  {CODE_LENGTH}: hem length clearly changed "
    "(a normal-length top rendered cropped, a midi skirt rendered mini...).\n"
    f"  {CODE_COLOR}: the dominant colour is a different colour.\n"
    f"  {CODE_PRINT}: a large print/pattern vanished, appeared, or was replaced "
    "by a different design.\n"
    f"  {CODE_MISSING}: the garment is not on the person at all.\n\n"
    "If you are unsure, report NO fault. A correct render wrongly rejected costs "
    "the user their result; be conservative.\n\n"
    'Reply with ONLY compact JSON: {"faithful": true|false, "faults": '
    '[{"code": "...", "detail": "short reason"}]}. '
    "faithful must be false if and only if faults is non-empty."
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


class AnthropicFidelityJudge(GarmentFidelityJudge):
    name = "anthropic"

    def __init__(self, api_key: str, model: str) -> None:
        from anthropic import AsyncAnthropic

        # Bounded, like the tagger: this runs on the single worker loop AFTER a
        # render the user is already waiting on, so it must not be able to hold
        # the queue open indefinitely.
        self._client = AsyncAnthropic(api_key=api_key, timeout=30.0, max_retries=1)
        self._model = model

    async def compare(
        self,
        *,
        garment: bytes,
        garment_media_type: str,
        render: bytes,
        render_media_type: str,
        canonical: str,
    ) -> GarmentFidelityReport:
        msg = await self._client.messages.create(
            model=self._model,
            max_tokens=400,
            system=_SYSTEM,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "REFERENCE garment:"},
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": garment_media_type,
                                "data": base64.standard_b64encode(garment).decode("ascii"),
                            },
                        },
                        {"type": "text", "text": "RENDER of the person wearing it:"},
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": render_media_type,
                                "data": base64.standard_b64encode(render).decode("ascii"),
                            },
                        },
                        {
                            "type": "text",
                            "text": (
                                f"This garment was selected as a {canonical.replace('_', ' ')}. "
                                "Inspect it and reply as JSON."
                            ),
                        },
                    ],
                }
            ],
        )
        text = "".join(block.text for block in msg.content if block.type == "text")
        data = _extract_json(text)

        # Only KNOWN codes count. A model that invents a fault name would
        # otherwise be able to fail renders for reasons nobody can act on or
        # count, which is the opposite of an auditable gate.
        findings = [
            GarmentFidelityFinding(
                code=str(fault.get("code")),
                detail=(str(fault.get("detail"))[:200] if fault.get("detail") else None),
            )
            for fault in (data.get("faults") or [])
            if isinstance(fault, dict) and str(fault.get("code")) in ALL_CODES
        ]
        # The verdict follows the FINDINGS, not the model's own boolean: a reply
        # claiming `faithful: false` with no recognised fault is not something we
        # can show a user or a chart, so it is treated as no fault found.
        return GarmentFidelityReport(
            faithful=not findings,
            findings=findings,
            input_tokens=msg.usage.input_tokens,
            output_tokens=msg.usage.output_tokens,
        )
