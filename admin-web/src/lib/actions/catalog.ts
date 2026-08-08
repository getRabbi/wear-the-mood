"use server";

import { revalidatePath } from "next/cache";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import {
  merchantApprovedSchema,
  merchantFeedEnabledSchema,
  merchantIdSchema,
  productActiveSchema,
  productOverrideSchema,
  productTryOnImageSchema,
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

// ── merchants ───────────────────────────────────────────────────────────────

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
