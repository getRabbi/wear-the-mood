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
