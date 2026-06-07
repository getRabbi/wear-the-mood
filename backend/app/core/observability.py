import sentry_sdk

from app.core.config import get_settings


def init_sentry() -> bool:
    """Initialize Sentry if a DSN is configured (CLAUDE.md §14).

    Returns True when Sentry was enabled, False when skipped (no DSN) — so the
    app runs normally in local/dev without a DSN.
    """
    settings = get_settings()
    if not settings.sentry_dsn:
        return False

    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=settings.environment,
        traces_sample_rate=0.1,
        send_default_pii=False,  # never send PII by default (CLAUDE.md §10)
    )
    return True
