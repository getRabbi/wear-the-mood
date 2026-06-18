"""Style Quiz (FEATURES_COMMUNITY_PLUS · Style Quiz).

GET the active quiz, submit answers (idempotent, §9) to compute a "Style DNA"
result, and read the user's latest result. Submitting also appends a 'quiz'
taste signal (the moat, §24) — the rich result lives in quiz_responses.result.
"""

from __future__ import annotations

import json
import logging
from uuid import UUID

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.idempotency import (
    get_stored_response,
    require_idempotency_key,
    reserve_key,
    store_response,
)
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.quiz import (
    ActiveQuiz,
    QuizOption,
    QuizQuestion,
    QuizResult,
    QuizSubmit,
    StyleResult,
)
from app.services.style_quiz import compute_style_result

log = logging.getLogger("fashionos.quiz")

router = APIRouter(tags=["quiz"])

_SUBMIT_ENDPOINT = "POST /v1/quiz/submit"


def _jsonb(value: object) -> object:
    return json.loads(value) if isinstance(value, str) else value


@router.get("/quiz/active", response_model=ActiveQuiz)
async def get_active_quiz(
    user: CurrentUser = Depends(get_current_user),
) -> ActiveQuiz:
    async with get_pool().acquire() as conn:
        quiz = await conn.fetchrow(
            "select id, slug, title, description from public.quizzes "
            "where is_active order by created_at limit 1"
        )
        if quiz is None:
            raise ApiError(ErrorCode.NOT_FOUND, "No active quiz.", 404)
        qrows = await conn.fetch(
            "select id, prompt, options from public.quiz_questions "
            "where quiz_id = $1::uuid order by order_index",
            quiz["id"],
        )
    questions = [
        QuizQuestion(
            id=str(r["id"]),
            prompt=r["prompt"],
            options=[QuizOption(**o) for o in _jsonb(r["options"])],
        )
        for r in qrows
    ]
    return ActiveQuiz(
        id=str(quiz["id"]),
        slug=quiz["slug"],
        title=quiz["title"],
        description=quiz["description"],
        questions=questions,
    )


@router.post("/quiz/{quiz_id}/submit", response_model=QuizResult)
async def submit_quiz(
    quiz_id: UUID,
    body: QuizSubmit,
    user: CurrentUser = Depends(get_current_user),
    idempotency_key: str = Depends(require_idempotency_key),
) -> JSONResponse:
    async with get_pool().acquire() as conn:
        # Replay an identical prior submit instead of recomputing/re-storing (§9).
        stored = await get_stored_response(conn, idempotency_key, user.id, _SUBMIT_ENDPOINT)
        if stored is not None:
            return JSONResponse(status_code=stored.status_code, content=stored.response)

        active = await conn.fetchval(
            "select 1 from public.quizzes where id = $1::uuid and is_active",
            str(quiz_id),
        )
        if active is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Quiz not found.", 404)

        result = compute_style_result(list(body.answers.values()))

        async with conn.transaction():
            if not await reserve_key(conn, idempotency_key, user.id, _SUBMIT_ENDPOINT):
                raise ApiError(ErrorCode.VALIDATION_ERROR, "Request already in progress.", 409)

            row = await conn.fetchrow(
                """
                insert into public.quiz_responses (user_id, quiz_id, answers, result)
                values ($1::uuid, $2::uuid, $3::jsonb, $4::jsonb)
                returning id, created_at
                """,
                user.id,
                str(quiz_id),
                json.dumps(body.answers),
                json.dumps(result.model_dump()),
            )
            # Quietly feed the taste graph (§24): a 'quiz' marker linking to the
            # full result. taste_signals schema is unchanged — we just append.
            await conn.execute(
                """
                insert into public.taste_signals
                  (user_id, signal_type, subject_type, subject_id)
                values ($1::uuid, 'quiz', 'quiz', $2::uuid)
                """,
                user.id,
                str(row["id"]),
            )
            payload = QuizResult(
                id=str(row["id"]), result=result, created_at=row["created_at"]
            ).model_dump(mode="json")
            await store_response(conn, idempotency_key, user.id, _SUBMIT_ENDPOINT, 200, payload)

    return JSONResponse(status_code=200, content=payload)


@router.get("/quiz/result/latest", response_model=QuizResult)
async def latest_result(
    user: CurrentUser = Depends(get_current_user),
) -> QuizResult:
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            "select id, result, created_at from public.quiz_responses "
            "where user_id = $1::uuid order by created_at desc limit 1",
            user.id,
        )
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "No quiz result yet.", 404)
    return QuizResult(
        id=str(row["id"]),
        result=StyleResult(**_jsonb(row["result"])),
        created_at=row["created_at"],
    )
