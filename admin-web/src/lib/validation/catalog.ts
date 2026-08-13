import { z } from "zod";

/**
 * Catalog + newsroom input shapes.
 *
 * These are the FIRST of three checks, not the only one: the Server Action
 * re-checks permission, and the RPC validates again inside the database. The
 * URL rules in particular are repeated in SQL on purpose — a try-on image is
 * handed to a paid render, and "the form validated it" is not a guarantee when
 * the form is not the only caller.
 */

const uuid = z.string().uuid();
const reason = z.string().trim().max(500).optional().or(z.literal(""));

/** Absolute http(s) with a host — the same rule the importer and app apply. */
const absoluteHttpUrl = z
  .string()
  .trim()
  .max(1000)
  .refine((v) => /^https?:\/\/[^/\s]+\//.test(v), "Must be an absolute http(s) URL.");

/**
 * Editorial fields a human may correct on a product.
 *
 * Deliberately excludes price, currency, affiliate_ref, external_id and
 * merchant: those are claims about the merchant's OFFER, not editorial copy,
 * and a price typed here that the retailer does not honour is worse than a feed
 * that is briefly stale. The database enforces the same restriction — this
 * schema is the first of the three checks, not the only one.
 *
 * Empty string means "clear this field"; an absent field means "leave it".
 * Title is the exception: a product with no name at all is not a product, so
 * blank is rejected here and again in SQL.
 */
export const productUpdateSchema = z.object({
  productId: uuid,
  title: z.string().trim().min(1, "Title cannot be blank.").max(500).optional(),
  category: z.string().trim().max(120).optional(),
  subcategory: z.string().trim().max(120).optional(),
  brand: z.string().trim().max(200).optional(),
  audience: z
    .enum(["women", "men", "unisex", "kids", "baby"])
    .or(z.literal(""))
    .optional(),
  reason,
});

export const productActiveSchema = z.object({
  productId: uuid,
  active: z.enum(["true", "false"]),
  reason,
});

export const productOverrideSchema = z.object({
  productId: uuid,
  enabled: z.enum(["true", "false"]),
  // Empty = freeze the whole row. A closed list, because an unknown field name
  // would silently protect nothing.
  fields: z
    .array(z.enum(["title", "price", "image_urls", "stock_status"]))
    .max(4)
    .default([]),
  reason,
});

export const productTryOnImageSchema = z.object({
  productId: uuid,
  // Empty clears the override and returns the product to `unsupported`.
  imageUrl: z.union([absoluteHttpUrl, z.literal("")]),
  reason,
});

/**
 * AI image-use rights. The three canonical values from migrations 0053/0057 —
 * this is not a new vocabulary.
 *
 *   unknown     no verified decision. NOT eligible.
 *   licensed    ops has verified the imagery may be sent to the configured AI
 *               processing provider for try-on. May become eligible if the
 *               other readiness conditions also pass.
 *   restricted  explicitly not permitted. NOT eligible.
 */
const imageRights = z.enum(["unknown", "licensed", "restricted"]);

/**
 * What a `licensed` decision rests on (0068). Evidence, never a gate — the
 * closed list exists so the common cases are searchable later, and `other` plus
 * a free-text reference covers the rest. Recorded only when licensing; when
 * rights are withdrawn the RPC clears it, because a reference that described a
 * permission we no longer claim is worse than no reference.
 */
const rightsBasis = z.enum([
  "merchant_permission",
  "product_permission",
  "programme_terms",
  "network_permission",
  "other",
]);

/**
 * A merchant-level default.
 *
 * `acknowledged` exists only for the licensing direction and is checked HERE as
 * well as in the dialog: a form is not a gate, and this is the one mutation in
 * the console that asserts a permission somebody has to have actually obtained.
 * It carries no legal wording — it records that a human confirmed the check was
 * done, which is what the audit row then preserves.
 */
export const merchantImageRightsSchema = z
  .object({
    merchantId: uuid,
    rights: imageRights,
    acknowledged: z.enum(["true", "false"]).default("false"),
    basis: rightsBasis.or(z.literal("")).optional(),
    reference: z.string().trim().max(500).optional().or(z.literal("")),
    reason,
  })
  .refine((v) => v.rights !== "licensed" || v.acknowledged === "true", {
    path: ["acknowledged"],
    message: "Confirm the rights check before licensing a merchant.",
  });

/**
 * A product-level override. `""` means INHERIT — clearing the override and
 * handing the product back to its merchant's default.
 *
 * Deliberately no acknowledgement here. A single product is a small, reversible
 * decision made while looking at the item itself; the merchant switch is the one
 * that moves a catalogue at once and earns the extra step.
 */
export const productImageRightsSchema = z.object({
  productId: uuid,
  rights: imageRights.or(z.literal("")),
  basis: rightsBasis.or(z.literal("")).optional(),
  reference: z.string().trim().max(500).optional().or(z.literal("")),
  reason,
});

// ── try-on coverage (0068) ──────────────────────────────────────────────────
//
// A SECOND, independent switch. Nothing in this section may accept, imply or
// default a rights value: a product switched on whose rights are unknown stays
// ineligible, and the database is what enforces that. These schemas exist so an
// operator cannot post a mode the resolver has never heard of.

/**
 * Merchant coverage.
 *
 *   off       nothing from this merchant is try-on eligible, whatever a
 *             product says. The rollback.
 *   all       every product that passes the rights + technical gates, plus any
 *             imported later, unless the product itself says off.
 *   selected  nothing unless the product says on. Future imports stay off.
 */
const tryOnMode = z.enum(["off", "all", "selected"]);

/**
 * Product coverage. `""` means INHERIT — hand the decision back to the merchant
 * mode, which is a distinct act from switching the product off and is audited
 * under its own action name.
 */
const tryOnOverride = z.enum(["on", "off"]).or(z.literal(""));

/**
 * Switching a merchant to `all` is the one coverage change that can expose a
 * whole catalogue at once, so it carries an acknowledgement — of the EXPOSURE,
 * not of a licence. Nothing here says anything about rights; `off` and
 * `selected` need no acknowledgement because both only ever narrow.
 */
export const merchantTryOnModeSchema = z
  .object({
    merchantId: uuid,
    mode: tryOnMode,
    acknowledged: z.enum(["true", "false"]).default("false"),
    reason,
  })
  .refine((v) => v.mode !== "all" || v.acknowledged === "true", {
    path: ["acknowledged"],
    message: "Confirm the exposure before switching a merchant to all products.",
  });

export const productTryOnOverrideSchema = z.object({
  productId: uuid,
  override: tryOnOverride,
  reason,
});

/**
 * The bulk action behind SELECTED-only administration.
 *
 * Bounded at the same 500 the RPC enforces, and deliberately carries no rights
 * field: bulk-enabling products is not a way to bulk-license them, and the
 * result reports which of the selection remain ineligible rather than fixing
 * the number by granting something.
 */
export const bulkProductTryOnSchema = z.object({
  productIds: z.array(uuid).min(1, "Select at least one product.").max(500, "Select at most 500."),
  override: tryOnOverride,
  reason,
});

export const merchantApprovedSchema = z.object({
  merchantId: uuid,
  approved: z.enum(["true", "false"]),
  reason,
});

export const merchantFeedEnabledSchema = z.object({
  merchantId: uuid,
  enabled: z.enum(["true", "false"]),
  reason,
});

export const merchantIdSchema = z.object({ merchantId: uuid });

export const syncNowSchema = z.object({
  merchantId: uuid,
  // A dry run is the safe default for a feed nobody has trusted yet.
  dryRun: z.enum(["true", "false"]).default("true"),
});

// ── affiliate networks ──────────────────────────────────────────────────────
//
// Note the shape of what an admin can send: a feed's own row id, and on/off.
// There is no field here for a URL, a credential, an advertiser id or a feed
// number, because everything the connector needs it discovers for itself. An
// operator cannot point this system at an arbitrary endpoint, which is the
// property that makes "the key never reaches the browser" true rather than
// merely intended.

export const merchantFeedStateSchema = z.object({
  feedId: uuid,
  enabled: z.enum(["true", "false"]),
  reason,
});

/**
 * The countries a merchant is VERIFIED to deliver to.
 *
 * This is the fallback answer for every product whose own shipping eligibility
 * is unknown — which is most of what an affiliate feed supplies — so an empty
 * list is a refusal, not a wildcard. Codes are ISO-3166-1 alpha-2 and are
 * rejected rather than dropped: a typo that silently vanishes leaves an
 * operator believing a merchant ships somewhere it does not.
 */
export const merchantShippingSchema = z.object({
  merchantId: uuid,
  countries: z
    .string()
    .trim()
    .max(1000)
    .transform((v) =>
      Array.from(
        new Set(
          v
            .split(/[\s,]+/)
            .filter(Boolean)
            .map((c) => c.toUpperCase())
        )
      ).sort()
    )
    .refine((list) => list.every((c) => /^[A-Z]{2}$/.test(c)), {
      message: "Use ISO-3166-1 alpha-2 codes, e.g. BD, PL, GB.",
    })
    .refine((list) => list.length <= 250, { message: "Too many countries." }),
  reason,
});

export const networkDiscoverySchema = z.object({
  // A closed list. New networks arrive as code that knows how to read them,
  // never as a string an admin typed.
  network: z.enum(["awin"]).default("awin"),
});

// ── newsroom ────────────────────────────────────────────────────────────────

export const newsSourceUpsertSchema = z.object({
  sourceId: z.union([uuid, z.literal("")]).optional(),
  slug: z
    .string()
    .trim()
    .min(2)
    .max(60)
    .regex(/^[a-z0-9-]+$/, "Lowercase letters, numbers and dashes only."),
  name: z.string().trim().min(2).max(120),
  // https only: the ingester fetches this server-side, so a plain-http feed is
  // a request we make on somebody else's behalf over a modifiable channel.
  feedUrl: z
    .string()
    .trim()
    .max(1000)
    .refine((v) => /^https:\/\/[^/\s]+/.test(v), "Must be an absolute https URL."),
  publisher: z.string().trim().max(120).optional().or(z.literal("")),
  category: z.string().trim().max(60).optional().or(z.literal("")),
  priority: z.coerce.number().int().min(1).max(1000).default(100),
  autoPublish: z.enum(["true", "false"]).default("false"),
  reason,
});

export const newsSourceEnabledSchema = z.object({
  sourceId: uuid,
  enabled: z.enum(["true", "false"]),
  reason,
});

export const newsItemStatusSchema = z.object({
  itemId: uuid,
  status: z.enum(["draft", "review_required", "published", "archived"]),
  reason,
});

export const newsItemUpdateSchema = z.object({
  itemId: uuid,
  title: z.string().trim().min(2).max(300),
  // Bounded at the same 1200 the RPC enforces. A "summary" long enough to be
  // the article is the copyright problem this system exists to avoid.
  summary: z.string().trim().max(1200, "That is an article, not a summary."),
  attribution: z.string().trim().max(200).optional().or(z.literal("")),
  reason,
});

export const newsSyncNowSchema = z.object({
  sourceId: z.union([uuid, z.literal("")]).optional(),
  dryRun: z.enum(["true", "false"]).default("true"),
});
