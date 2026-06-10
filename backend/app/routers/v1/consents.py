"""Consents — explicit, timestamped records (CLAUDE.md §10). Used to gate
biometric face/body capture before any avatar/try-on. Own-row only (§11).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.core.db import get_pool
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.consent import ConsentCreate, ConsentResponse

router = APIRouter(tags=["consents"])


@router.post("/consents", status_code=201, response_model=ConsentResponse)
async def record_consent(
    body: ConsentCreate, user: CurrentUser = Depends(get_current_user)
) -> ConsentResponse:
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            """
            insert into public.consents (user_id, consent_type, version, granted)
            values ($1::uuid, $2, $3, true)
            returning id, consent_type, version, granted, created_at
            """,
            user.id,
            body.consent_type,
            body.version,
        )
    return ConsentResponse(
        id=str(row["id"]),
        consent_type=row["consent_type"],
        version=row["version"],
        granted=row["granted"],
        created_at=row["created_at"],
    )
