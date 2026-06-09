from pydantic import BaseModel


class CreditsResponse(BaseModel):
    balance: int
    daily_free_used: int
    daily_free_limit: int
    daily_free_remaining: int
