"""Style Quiz models (FEATURES_COMMUNITY_PLUS · Style Quiz).

A short quiz whose result is a "Style DNA" card. Each option's `key` is a style
trait the backend tallies into the result; the result also feeds taste_signals.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field, model_validator


class QuizOption(BaseModel):
    key: str
    label: str
    image_url: str | None = None


class QuizQuestion(BaseModel):
    id: str
    prompt: str
    options: list[QuizOption]


class ActiveQuiz(BaseModel):
    id: str
    slug: str
    title: str
    description: str | None = None
    questions: list[QuizQuestion]


class QuizSubmit(BaseModel):
    """The user's answers: {question_id: chosen option key}."""

    answers: dict[str, str] = Field(default_factory=dict)

    @model_validator(mode="after")
    def _require_answers(self) -> QuizSubmit:
        if not self.answers:
            raise ValueError("Answer at least one question.")
        return self


class StyleResult(BaseModel):
    """The computed Style DNA card."""

    title: str
    keywords: list[str]
    description: str
    palette: list[str] = Field(default_factory=list)


class QuizResult(BaseModel):
    id: str
    result: StyleResult
    created_at: datetime
