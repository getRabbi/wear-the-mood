# Try-on rights and coverage — the owner's guide

*Migrations 0065 (display vs AI rights), 0067 (rights control), 0068 (coverage).*

There are **two switches** on every store and every product, and they answer
different questions. Nothing in this system lets one stand in for the other.

| | Question | Values | Where |
|---|---|---|---|
| **Image rights** | *May* we send this imagery to the AI provider? | `unknown` · `licensed` · `restricted` | Merchants → store → AI virtual try-on → Image rights |
| **Try-on coverage** | *Do* we expose try-on, and for what? | `off` · `all` · `selected` | Merchants → store → AI virtual try-on → Try-on coverage |

Rights are a claim about the world. Coverage is a decision about our product.
A product may legitimately be **licensed and switched off**. A product switched
**on with rights `unknown` is not eligible** — and never becomes eligible,
whatever the operational settings say.

---

## What the server actually decides

`product_tryon_ready()` in the database is the only definition. Every surface —
Home, Discover, Picked for You, All Picks, Search, Product Details, Saved,
restored looks and deep links — reads that one verdict, so they cannot disagree.

A product is try-on ready when **all** of these hold:

1. effective image rights = `licensed`
2. effective coverage policy = `on`
3. `try_on_status` = `ready` (the garment is renderable and has an image)
4. a usable try-on image exists
5. the product is active and servable

Effective rights = the product's own override, else the merchant default.
Effective coverage:

| Store mode | Product override | Result |
|---|---|---|
| `off` | anything | **off** — hard kill, nothing bypasses it |
| `all` | inherit | on |
| `all` | `off` | off |
| `all` | `on` | on |
| `selected` | inherit | off |
| `selected` | `on` | on |
| `selected` | `off` | off |

A merchant with no coverage row reads `off`. That is the state every merchant is
in the moment 0068 is applied — nothing is switched on by deploying it.

---

## The four workflows

### Whole store licensed

Merchants → the store →

1. **Image rights** → `Licensed` → review the confirmation → tick the
   acknowledgement → save. Record the basis and a reference while you are there.
2. **Try-on coverage** → `All eligible products` → confirm the count.

Existing and future eligible products inherit automatically. No per-product work.

### Permission for a few products only

1. **Try-on coverage** → `Selected products only`.
2. Products page → filter to that merchant → tick the products → **Enable
   try-on**.
3. For each, set **Product rights override → Licensed** (with the basis and
   reference). Bulk enabling does *not* license: the bar reports how many of the
   selection still lack rights.

Products imported later stay off until somebody picks them.

### Disable one product from an enabled store

Products → the product → **Product try-on** → `Off`. Everything else in the
store is unaffected.

### Emergency shutdown

Merchants → the store → **Try-on coverage** → `Off` → save. One action, no
confirmation dialog in the way, and **no product settings are erased**. Setting
the store back to `all` or `selected` restores every product decision exactly as
it was.

If permission has actually been *revoked*, set **Image rights → Restricted**
instead. That blocks processing on rights grounds, which is the honest record.

---

## Stale clients cannot get around it

Every catalog try-on request carries `source_product_id`. The backend re-reads
`product_tryon_ready()` for that product at submit time, **before** the image is
sent to moderation and **before** any credit is reserved. A card cached on a
phone while a product was on cannot spend a credit after it was switched off.

Closet garments send no `source_product_id` and are not affected.

---

## What the importer does and does not touch

Feed sync **never** writes:

- `products.tryon_policy_override`
- `products.image_rights_override`
- `merchant_tryon_policy.mode`
- `merchant_feed_config.image_rights_default`

It writes `image_rights_status` only for products that *inherit* (no override),
and it recomputes `try_on_status` from the rights in force. A manual decision
survives every sync.

New products inherit the store's current coverage at read time, so:

- store on `all` → a new eligible product is live immediately
- store on `selected` → a new product is off until picked
- store `off` → off

---

## Reading the diagnostics

The merchant card shows counts straight from `admin_merchant_tryon_summary()`:

- **Try-On ready** — passes every gate right now
- **image rights not licensed** — a rights question, not an operational one
- **missing compatible images** — licensed but nothing usable to send
- **unsupported garment or category** — the engine cannot render it
- **explicitly disabled / enabled** — decisions someone made by hand
- **eligible, awaiting selection** — under `selected`, ready and unpicked

On a product, the readiness panel names the *first* thing standing in the way,
in the order you would fix them: rights, then coverage, then image, then status.

---

## Audit

Every change writes an `admin_audit_log` row with actor, before, after and the
affected count:

| Action | Written by |
|---|---|
| `merchant_set_image_rights` | store rights |
| `merchant_set_tryon_mode` | store coverage |
| `product_set_image_rights_override` / `product_clear_image_rights_override` | product rights |
| `product_set_tryon_override` / `product_clear_tryon_override` | product coverage |
| `product_bulk_set_tryon_override` / `product_bulk_clear_tryon_override` | bulk actions |

Licensing a merchant records `tryon_mode_unchanged` in its metadata, so the audit
shows that the two decisions stayed separate.

---

## Permissions

| Capability | Roles |
|---|---|
| `manage_image_rights` | owner, admin |
| `manage_tryon_coverage` | owner, admin |
| `view_catalog` (read the diagnostics) | owner, admin, content_manager, moderator, support |

Separate capabilities on purpose: pulling the switch at 2am and asserting that a
licence exists are different acts, and the day one of them needs to move the
other must not move with it.
