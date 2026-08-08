"""Merchant product ingestion (DISCOVER §17, §35).

This package is the IMPORTER. It does not own the catalog — `merchants`,
`products`, `product_variants` and `product_is_servable()` were created by
migration 0053 and are untouched here. What this adds is the thing that keeps
them true over time: a run that reads a merchant's feed, decides what changed,
and writes as little as possible.

The design rules, and why each exists:

* **`external_id` is the identity.** Everything is an upsert keyed on
  `(merchant_id, external_id)`, which 0053 already made unique. A feed that
  re-lists the same product a thousand times produces one row.

* **Unchanged means untouched.** The normalized payload is hashed; a matching
  hash short-circuits before any UPDATE. Without this every run would bump
  `updated_at` on the whole catalog, `last_synced_at` would stop meaning
  "confirmed recently", and the churn would be indistinguishable from real
  price movement.

* **Absence is not deletion.** A product missing from a feed is counted, not
  removed — feeds truncate, paginate badly, and time out. Only after
  `missing_runs_before_deactivate` consecutive absences is it deactivated, and
  deactivation means `active = false`, which `product_is_servable()` already
  suppresses. Rows are never deleted, so a product that comes back returns with
  its saves, its interactions and its id intact.

* **A human always wins.** `manual_override` freezes a row, or named fields of
  it, against the feed. An importer that can quietly revert a curator's work is
  an importer nobody will leave switched on.

* **Rights are not assumed.** Imagery is only marked `licensed` when the
  merchant's own config says its feed is licensed; otherwise the product lands
  `unknown`, which the existing servability rule already hides.
"""

from app.services.catalog.models import (
    FeedProduct,
    FeedVariant,
    SyncCounts,
    SyncOutcome,
)
from app.services.catalog.sync import sync_merchant

__all__ = [
    "FeedProduct",
    "FeedVariant",
    "SyncCounts",
    "SyncOutcome",
    "sync_merchant",
]
