from __future__ import annotations

from pydantic import BaseModel, Field


class DeviceTokenRegister(BaseModel):
    """Register (or refresh) this device's FCM token for daily push (§20).
    Sends the device timezone too so the morning push fires at local AM (§20)."""

    token: str = Field(min_length=1, max_length=4096)
    platform: str | None = Field(default=None, max_length=16)  # android | ios | web
    timezone: str | None = Field(default=None, max_length=64)  # IANA name, e.g. Asia/Dhaka
