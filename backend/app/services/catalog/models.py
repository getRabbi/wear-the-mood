"""Normalized feed shapes + the hash that decides whether anything changed."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from datetime import datetime

# Bounded so one pathological feed cannot write an unreadable error blob into
# product_sync_runs.errors, which is a table a human is expected to read.
MAX_RUN_ERRORS = 25

# Currency is ISO-4217 and money is integer minor units everywhere (0053). A
# feed that hands us a float price is rejected rather than rounded: silently
# turning 19.99 into 1998 poisha is the exact class of drift the catalog's money
# design exists to prevent.
ALLOWED_STOCK = {"in_stock", "low_stock", "out_of_stock", "unknown"}
ALLOWED_TRY_ON = {"unsupported", "pending", "ready"}
ALLOWED_RIGHTS = {"unknown", "licensed", "restricted"}


@dataclass(frozen=True)
class FeedVariant:
    """One size/colour combination as the feed describes it."""

    external_id: str
    color: str | None = None
    size: str | None = None
    price_minor: int | None = None
    original_price_minor: int | None = None
    stock_status: str = "unknown"
    available: bool = True


@dataclass
class FeedProduct:
    """One product, normalized out of whatever shape the merchant published.

    Adapters are responsible for producing THIS; everything downstream — the
    hash, the upsert, the readiness rules — works only on normalized data, so a
    new feed format never reaches the writer.
    """

    external_id: str
    title: str
    price_minor: int
    currency: str

    description: str | None = None
    brand: str | None = None
    category: str | None = None
    subcategory: str | None = None
    audience: str | None = None
    original_price_minor: int | None = None

    image_urls: list[str] = field(default_factory=list)
    image_focal_x: float = 0.5
    image_focal_y: float = 0.5

    colors: list[str] = field(default_factory=list)
    sizes: list[str] = field(default_factory=list)
    variants: list[FeedVariant] = field(default_factory=list)

    country_availability: list[str] = field(default_factory=list)
    stock_status: str = "unknown"

    # What the FEED claims about try-on. Never trusted as-is: the writer
    # re-derives readiness from the resolved image, so a feed cannot mark a
    # product ready and hand us nothing to render.
    try_on_status: str = "unsupported"

    affiliate_ref: str | None = None
    sponsored: bool = False

    starts_at: datetime | None = None
    ends_at: datetime | None = None

    def content_hash(self) -> str:
        """A stable digest of everything the importer would write.

        Sorted and JSON-encoded so key order, list order from a paginated feed,
        and dict iteration cannot make an unchanged product look changed. This
        is what makes a second run a no-op — the property the whole "no churn"
        requirement rests on.
        """
        payload = {
            "external_id": self.external_id,
            "title": self.title,
            "description": self.description,
            "brand": self.brand,
            "category": self.category,
            "subcategory": self.subcategory,
            "audience": self.audience,
            "price_minor": self.price_minor,
            "original_price_minor": self.original_price_minor,
            "currency": self.currency,
            "image_urls": list(self.image_urls),
            "image_focal_x": round(self.image_focal_x, 4),
            "image_focal_y": round(self.image_focal_y, 4),
            "colors": sorted(self.colors),
            "sizes": sorted(self.sizes),
            "country_availability": sorted(self.country_availability),
            "stock_status": self.stock_status,
            "try_on_status": self.try_on_status,
            "affiliate_ref": self.affiliate_ref,
            "sponsored": self.sponsored,
            "starts_at": self.starts_at.isoformat() if self.starts_at else None,
            "ends_at": self.ends_at.isoformat() if self.ends_at else None,
            "variants": sorted(
                (
                    v.external_id,
                    v.color,
                    v.size,
                    v.price_minor,
                    v.original_price_minor,
                    v.stock_status,
                    v.available,
                )
                for v in self.variants
            ),
        }
        encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
        return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


@dataclass
class SyncCounts:
    """What a run did. Mirrors the columns on product_sync_runs."""

    fetched: int = 0
    created: int = 0
    updated: int = 0
    unchanged: int = 0
    deactivated: int = 0
    reactivated: int = 0
    skipped: int = 0

    def as_dict(self) -> dict[str, int]:
        return {
            "fetched": self.fetched,
            "created": self.created,
            "updated": self.updated,
            "unchanged": self.unchanged,
            "deactivated": self.deactivated,
            "reactivated": self.reactivated,
            "skipped": self.skipped,
        }


@dataclass
class SyncOutcome:
    """The result of one attempt, whatever happened."""

    run_id: str | None
    status: str
    counts: SyncCounts = field(default_factory=SyncCounts)
    errors: list[dict[str, str]] = field(default_factory=list)
    error_message: str | None = None
    dry_run: bool = False

    def add_error(self, external_id: str | None, message: str) -> None:
        """Record a per-item failure, up to the cap.

        Truncating rather than growing without bound: the 26th identical
        'missing price' is not new information, and the run summary has to stay
        something a person can read at 3am.
        """
        if len(self.errors) < MAX_RUN_ERRORS:
            self.errors.append({"external_id": external_id or "", "error": message[:400]})
