"use server";

import { revalidatePath } from "next/cache";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import {
  bulkProductTryOnSchema,
  merchantApprovedSchema,
  merchantFeedEnabledSchema,
  merchantFeedStateSchema,
  merchantIdSchema,
  merchantImageRightsSchema,
  merchantShippingSchema,
  merchantTryOnModeSchema,
  networkDiscoverySchema,
  productActiveSchema,
  productImageRightsSchema,
  productOverrideSchema,
  productTryOnImageSchema,
  productTryOnOverrideSchema,
  productUpdateSchema,
  syncNowSchema,
} from "@/lib/validation/catalog";

/**
 * Catalog + automation mutations.
 *
 * Every one follows the console's existing contract: `requirePermission` first,
 * zod second, then an audited `admin_*` RPC that re-asserts the admin is active
 * inside the database and writes a before/after audit row. There is no path
 * here that touches a table directly, so an unaudited catalog mutation is not
 * something this file can express.
 */

export type ActionState = { ok: boolean; error?: string; message?: string };
const FAIL = (error: string): ActionState => ({ ok: false, error });

// ── products ────────────────────────────────────────────────────────────────

export async function updateProduct(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_products");
  const parsed = productUpdateSchema.safeParse({
    productId: fd.get("productId"),
    title: fd.get("title") ?? undefined,
    category: fd.get("category") ?? undefined,
    subcategory: fd.get("subcategory") ?? undefined,
    brand: fd.get("brand") ?? undefined,
    audience: fd.get("audience") ?? undefined,
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) {
    return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  }
  const d = parsed.data;
  // `null` means "leave this field alone" in the RPC; "" means "clear it". The
  // form only ever submits fields it rendered, so an untouched column stays
  // untouched rather than being blanked by an absent input.
  const { error } = await getAdminClient().rpc("admin_update_product", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_product_id: d.productId,
    p_title: d.title ?? null,
    p_category: d.category ?? null,
    p_subcategory: d.subcategory ?? null,
    p_brand: d.brand ?? null,
    p_audience: d.audience ?? null,
    p_reason: d.reason || null,
  });
  if (error) return FAIL("Could not update the product.");
  revalidatePath("/products");
  return { ok: true, message: "Saved." };
}

export async function setProductActive(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_products");
  const parsed = productActiveSchema.safeParse({
    productId: fd.get("productId"),
    active: fd.get("active"),
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_set_product_active", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_product_id: parsed.data.productId,
    p_active: parsed.data.active === "true",
    p_reason: parsed.data.reason || null,
  });
  if (error) return FAIL("Could not update the product.");
  revalidatePath("/products");
  return { ok: true };
}

export async function setProductOverride(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_products");
  const parsed = productOverrideSchema.safeParse({
    productId: fd.get("productId"),
    enabled: fd.get("enabled"),
    fields: fd.getAll("fields").map(String).filter(Boolean),
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_set_product_override", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_product_id: parsed.data.productId,
    p_enabled: parsed.data.enabled === "true",
    p_fields: parsed.data.fields,
    p_reason: parsed.data.reason || null,
  });
  if (error) return FAIL("Could not update the override.");
  revalidatePath("/products");
  return { ok: true };
}

export async function setProductTryOnImage(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_products");
  const parsed = productTryOnImageSchema.safeParse({
    productId: fd.get("productId"),
    imageUrl: (fd.get("imageUrl") ?? "").toString().trim(),
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) {
    return FAIL(parsed.error.issues[0]?.message ?? "Invalid image URL.");
  }
  const { error } = await getAdminClient().rpc("admin_set_product_tryon_image", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_product_id: parsed.data.productId,
    p_image_url: parsed.data.imageUrl || null,
    p_reason: parsed.data.reason || null,
  });
  // The RPC refuses unlicensed or malformed imagery; surfacing its refusal
  // rather than a generic failure is the difference between a fixable message
  // and a mystery.
  if (error) return FAIL(error.message.includes("INVALID_IMAGE_URL")
    ? "That is not an absolute http(s) image URL."
    : "Could not set the try-on image.");
  revalidatePath("/products");
  return { ok: true };
}

/**
 * The explicit product-level AI image-rights decision.
 *
 * An empty `rights` clears the override and returns the product to its
 * merchant's default — a distinct decision from setting one, and the RPC audits
 * it under its own action name for exactly that reason.
 *
 * `manage_image_rights`, not `manage_products`: every other product mutation is
 * merchandising, and this one asserts that permission exists to send somebody
 * else's photograph to a generative model.
 */
export async function setProductImageRights(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_image_rights");
  const parsed = productImageRightsSchema.safeParse({
    productId: fd.get("productId"),
    rights: (fd.get("rights") ?? "").toString(),
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) {
    return FAIL(parsed.error.issues[0]?.message ?? "Invalid rights value.");
  }
  const { error } = await getAdminClient().rpc("admin_set_product_image_rights", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_product_id: parsed.data.productId,
    // null is a real value to the RPC and means "inherit".
    p_rights: parsed.data.rights === "" ? null : parsed.data.rights,
    p_reason: parsed.data.reason || null,
    // Evidence, recorded only when licensing — the RPC clears it otherwise.
    p_basis: parsed.data.basis || null,
    p_reference: parsed.data.reference || null,
  });
  if (error) return FAIL("Could not update image rights.");
  revalidatePath("/products");
  revalidatePath("/merchants");
  return { ok: true, message: "Saved." };
}

// ── try-on coverage (0068) ──────────────────────────────────────────────────
//
// The second switch. Note what is absent from every function below: any rights
// parameter at all. Coverage cannot license anything, and the database enforces
// that independently — `product_tryon_ready()` requires licensed effective
// rights AND an on effective policy, so the worst a coverage mistake can do is
// expose products that were already cleared, or switch everything off.

/**
 * Merchant coverage: off / all / selected.
 *
 * Deliberately a separate action from `setMerchantImageRights` rather than a
 * second field on it. Licensing a merchant does not switch it on, and switching
 * a merchant off does not retract the licence — collapsing the two would mean an
 * emergency shutdown had to be performed by withdrawing a factual claim about
 * permission, which is not something an operator should ever have to do at 2am.
 */
export async function setMerchantTryOnMode(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_tryon_coverage");
  const parsed = merchantTryOnModeSchema.safeParse({
    merchantId: fd.get("merchantId"),
    mode: (fd.get("mode") ?? "").toString(),
    acknowledged: fd.get("acknowledged") ?? "false",
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) {
    return FAIL(parsed.error.issues[0]?.message ?? "Invalid coverage mode.");
  }
  const { error } = await getAdminClient().rpc("admin_set_merchant_tryon_mode", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_merchant_id: parsed.data.merchantId,
    p_mode: parsed.data.mode,
    p_reason: parsed.data.reason || null,
  });
  if (error) return FAIL("Could not update try-on coverage.");
  revalidatePath("/merchants");
  revalidatePath("/products");
  return { ok: true, message: "Saved." };
}

/** Product coverage: on / off / "" = inherit the merchant mode. */
export async function setProductTryOnOverride(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_tryon_coverage");
  const parsed = productTryOnOverrideSchema.safeParse({
    productId: fd.get("productId"),
    override: (fd.get("override") ?? "").toString(),
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) return FAIL("Invalid try-on setting.");
  const { error } = await getAdminClient().rpc("admin_set_product_tryon_override", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_product_id: parsed.data.productId,
    p_override: parsed.data.override === "" ? null : parsed.data.override,
    p_reason: parsed.data.reason || null,
  });
  if (error) return FAIL("Could not update try-on for this product.");
  revalidatePath("/products");
  revalidatePath("/merchants");
  return { ok: true, message: "Saved." };
}

/**
 * Bulk coverage across a selection.
 *
 * Returns the RPC's own accounting rather than "done": part of the point of this
 * control is that enabling twenty products whose rights are not licensed enables
 * twenty products and makes five of them eligible, and an operator who is not
 * told that will believe the other fifteen are live.
 */
export async function bulkSetProductTryOn(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_tryon_coverage");
  const parsed = bulkProductTryOnSchema.safeParse({
    productIds: fd.getAll("productIds").map(String).filter(Boolean),
    override: (fd.get("override") ?? "").toString(),
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) {
    return FAIL(parsed.error.issues[0]?.message ?? "Invalid selection.");
  }
  const { data, error } = await getAdminClient().rpc("admin_bulk_set_product_tryon", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_product_ids: parsed.data.productIds,
    p_override: parsed.data.override === "" ? null : parsed.data.override,
    p_reason: parsed.data.reason || null,
  });
  if (error) return FAIL("Could not apply the bulk change.");

  const result = (data ?? {}) as {
    requested?: number;
    updated?: number;
    try_on_ready_after?: number;
    not_licensed?: number;
  };
  revalidatePath("/products");
  revalidatePath("/merchants");

  const updated = result.updated ?? 0;
  const blocked = result.not_licensed ?? 0;
  if (parsed.data.override === "on") {
    return {
      ok: true,
      message:
        `${updated} updated, ${result.try_on_ready_after ?? 0} now try-on ready` +
        (blocked > 0
          ? ` — ${blocked} could not become eligible because image rights are not licensed.`
          : "."),
    };
  }
  return {
    ok: true,
    message:
      parsed.data.override === "off"
        ? `${updated} switched off.`
        : `${updated} returned to the merchant setting.`,
  };
}

// ── merchants ───────────────────────────────────────────────────────────────

/**
 * The merchant-level AI image-rights default.
 *
 * This is the mutation that can move a whole catalogue at once, so it carries
 * the acknowledgement the schema enforces and the RPC's propagation is bounded
 * to products that INHERIT — an explicit product decision is never overwritten
 * by a merchant-wide one.
 *
 * There is deliberately no "license everything" here and no network-wide
 * variant: licensing is per merchant, by name, every time.
 *
 * It also does NOT touch try-on coverage (0068). Licensing records that we are
 * permitted to; switching on is a separate decision, made separately, so that
 * "we have permission and are not using it yet" is a state the system can hold.
 */
export async function setMerchantImageRights(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_image_rights");
  const parsed = merchantImageRightsSchema.safeParse({
    merchantId: fd.get("merchantId"),
    rights: (fd.get("rights") ?? "").toString(),
    acknowledged: fd.get("acknowledged") ?? "false",
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) {
    return FAIL(parsed.error.issues[0]?.message ?? "Invalid rights value.");
  }
  const { error } = await getAdminClient().rpc("admin_set_merchant_image_rights", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_merchant_id: parsed.data.merchantId,
    p_rights: parsed.data.rights,
    p_reason: parsed.data.reason || null,
    // Evidence for the claim, recorded only when licensing. It changes no gate:
    // this is what a reader six months from now needs to know WHAT was verified.
    p_basis: parsed.data.basis || null,
    p_reference: parsed.data.reference || null,
  });
  if (error) {
    return FAIL(
      error.message.includes("NO_FEED_CONFIG")
        ? "This merchant has no feed configuration, so it has no default to set."
        : "Could not update image rights."
    );
  }
  revalidatePath("/merchants");
  revalidatePath("/products");
  return { ok: true, message: "Saved." };
}

export async function setMerchantApproved(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_merchants");
  const parsed = merchantApprovedSchema.safeParse({
    merchantId: fd.get("merchantId"),
    approved: fd.get("approved"),
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_set_merchant_approved", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_merchant_id: parsed.data.merchantId,
    p_approved: parsed.data.approved === "true",
    p_reason: parsed.data.reason || null,
  });
  if (error) return FAIL("Could not update the merchant.");
  revalidatePath("/merchants");
  return { ok: true };
}

export async function setMerchantFeedEnabled(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_merchants");
  const parsed = merchantFeedEnabledSchema.safeParse({
    merchantId: fd.get("merchantId"),
    enabled: fd.get("enabled"),
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_set_merchant_feed_enabled", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_merchant_id: parsed.data.merchantId,
    p_enabled: parsed.data.enabled === "true",
    p_reason: parsed.data.reason || null,
  });
  if (error) {
    return FAIL(
      error.message.includes("NO_FEED_CONFIG")
        ? "This merchant has no feed configured yet."
        : "Could not update the feed."
    );
  }
  revalidatePath("/merchants");
  return { ok: true };
}

/**
 * Record where a merchant is verified to deliver.
 *
 * This is the only place that answer can come from. Products imported from an
 * affiliate feed carry no shipping data at all, and rather than pretend an
 * absent list means "everywhere", the catalog treats them as unknown and asks
 * this list instead. Setting it is therefore a claim someone is making, which
 * is why it is audited like any other.
 */
export async function setMerchantShipping(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_merchants");
  const parsed = merchantShippingSchema.safeParse({
    merchantId: fd.get("merchantId"),
    countries: fd.get("countries") ?? "",
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) {
    return FAIL(parsed.error.issues[0]?.message ?? "Invalid country list.");
  }
  const { error } = await getAdminClient().rpc("admin_set_merchant_shipping", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_merchant_id: parsed.data.merchantId,
    p_countries: parsed.data.countries,
    p_reason: parsed.data.reason || null,
  });
  if (error) {
    return FAIL(
      error.message.includes("INVALID_COUNTRY")
        ? "Use ISO-3166-1 alpha-2 codes, e.g. BD, PL, GB."
        : "Could not update shipping countries."
    );
  }
  revalidatePath("/merchants");
  revalidatePath("/products");
  return { ok: true, message: "Saved." };
}

export async function clearFeedLock(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_merchants");
  const parsed = merchantIdSchema.safeParse({ merchantId: fd.get("merchantId") });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_clear_feed_lock", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_merchant_id: parsed.data.merchantId,
  });
  if (error) return FAIL("Could not clear the lock.");
  revalidatePath("/merchants");
  return { ok: true };
}

// ── sync ────────────────────────────────────────────────────────────────────

/**
 * "Sync Now".
 *
 * The console does NOT import from the browser process: ingestion is the
 * backend's job, it can take minutes, and a Next.js server action is the wrong
 * lifetime for it. This queues the request by writing a `product_sync_runs` row
 * the worker claims — the same table the runner already writes, so a queued run
 * and a cron run are the same thing in the history.
 */
export async function requestProductSync(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("run_product_sync");
  const parsed = syncNowSchema.safeParse({
    merchantId: fd.get("merchantId"),
    dryRun: fd.get("dryRun") ?? "true",
  });
  if (!parsed.success) return FAIL("Invalid input.");

  const { error } = await getAdminClient().rpc("admin_request_product_sync", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_merchant_id: parsed.data.merchantId,
    p_dry_run: parsed.data.dryRun === "true",
  });
  if (error) {
    return FAIL(
      error.message.includes("AUTOMATION_OFF")
        ? "Product automation is switched off."
        : error.message.includes("FEED_DISABLED")
          ? "This merchant's feed is disabled."
          : "Could not queue the sync."
    );
  }
  revalidatePath("/automation");
  revalidatePath("/merchants");
  return { ok: true, message: "Sync queued. The worker will pick it up shortly." };
}

// ── affiliate networks ──────────────────────────────────────────────────────

/**
 * Turn one discovered feed on or off.
 *
 * The unit of consent is the FEED, not the merchant: an advertiser offers
 * twenty-one of them and we want five. Enabling is deliberately the only thing
 * an admin does here — nobody types a feed id, a URL or a credential, because
 * the connector discovered all three and the browser is never told any of them.
 */
export async function setMerchantFeedState(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_merchants");
  const parsed = merchantFeedStateSchema.safeParse({
    feedId: fd.get("feedId"),
    enabled: fd.get("enabled"),
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_set_merchant_feed_state", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_feed_id: parsed.data.feedId,
    p_enabled: parsed.data.enabled === "true",
    p_reason: parsed.data.reason || null,
  });
  if (error) {
    return FAIL(
      error.message.includes("FEED_REMOVED")
        ? "The network no longer offers this feed."
        : "Could not update the feed."
    );
  }
  revalidatePath("/merchants");
  return { ok: true };
}

/**
 * Ask the backend to re-read the network account.
 *
 * Queued rather than executed for the same reason "Sync Now" is: reading a
 * network account means an authenticated HTTP request with a secret this
 * process must never hold. The worker owns the credential; the console owns
 * the decision.
 */
export async function requestNetworkDiscovery(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_merchants");
  const parsed = networkDiscoverySchema.safeParse({ network: fd.get("network") ?? "awin" });
  if (!parsed.success) return FAIL("Unknown network.");
  const { error } = await getAdminClient().rpc("admin_request_network_discovery", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_network: parsed.data.network,
  });
  if (error) {
    return FAIL(
      error.message.includes("DISCOVERY_OFF")
        ? "Network discovery is switched off."
        : "Could not queue discovery."
    );
  }
  revalidatePath("/merchants");
  return { ok: true, message: "Discovery queued. New merchants appear here when it finishes." };
}
