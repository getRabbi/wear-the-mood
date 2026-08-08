"use server";

import { revalidatePath } from "next/cache";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import {
  newsItemStatusSchema,
  newsItemUpdateSchema,
  newsSourceEnabledSchema,
  newsSourceUpsertSchema,
  newsSyncNowSchema,
} from "@/lib/validation/catalog";

/**
 * Newsroom mutations. Same three-layer contract as the catalog actions:
 * permission, then zod, then an audited RPC that re-asserts the admin inside
 * the database.
 *
 * Note which permission guards which verb. Publishing an ITEM is editorial and
 * sits with content_manager; trusting a SOURCE to publish unreviewed is a
 * standing decision about what reaches the app without a human, and stays with
 * admin.
 */

export type ActionState = { ok: boolean; error?: string; message?: string };
const FAIL = (error: string): ActionState => ({ ok: false, error });

export async function upsertNewsSource(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_news_sources");
  const parsed = newsSourceUpsertSchema.safeParse({
    sourceId: (fd.get("sourceId") ?? "").toString(),
    slug: fd.get("slug"),
    name: fd.get("name"),
    feedUrl: fd.get("feedUrl"),
    publisher: fd.get("publisher") ?? "",
    category: fd.get("category") ?? "",
    priority: fd.get("priority") ?? 100,
    autoPublish: fd.get("autoPublish") ?? "false",
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");

  const { error } = await getAdminClient().rpc("admin_upsert_news_source", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_source_id: parsed.data.sourceId || null,
    p_slug: parsed.data.slug,
    p_name: parsed.data.name,
    p_feed_url: parsed.data.feedUrl,
    p_publisher: parsed.data.publisher || null,
    p_category: parsed.data.category || null,
    p_priority: parsed.data.priority,
    p_auto_publish: parsed.data.autoPublish === "true",
    p_reason: parsed.data.reason || null,
  });
  if (error) {
    return FAIL(
      error.message.includes("INVALID_FEED_URL")
        ? "The feed URL must be an absolute https URL."
        : error.message.includes("duplicate key")
          ? "That slug is already in use."
          : "Could not save the source."
    );
  }
  revalidatePath("/newsroom");
  // Stated plainly because it is a deliberate refusal to do what the form
  // appears to ask: a new source is created DISABLED and only ingests once
  // somebody switches it on.
  return { ok: true, message: "Saved. A new source starts disabled — enable it when reviewed." };
}

export async function setNewsSourceEnabled(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_news_sources");
  const parsed = newsSourceEnabledSchema.safeParse({
    sourceId: fd.get("sourceId"),
    enabled: fd.get("enabled"),
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_set_news_source_enabled", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_source_id: parsed.data.sourceId,
    p_enabled: parsed.data.enabled === "true",
    p_reason: parsed.data.reason || null,
  });
  if (error) return FAIL("Could not update the source.");
  revalidatePath("/newsroom");
  return { ok: true };
}

export async function setNewsItemStatus(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_news_items");
  const parsed = newsItemStatusSchema.safeParse({
    itemId: fd.get("itemId"),
    status: fd.get("status"),
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_set_news_item_status", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_item_id: parsed.data.itemId,
    p_status: parsed.data.status,
    p_reason: parsed.data.reason || null,
  });
  if (error) return FAIL("Could not update the item.");
  revalidatePath("/newsroom");
  return { ok: true };
}

export async function updateNewsItem(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_news_items");
  const parsed = newsItemUpdateSchema.safeParse({
    itemId: fd.get("itemId"),
    title: fd.get("title"),
    summary: fd.get("summary") ?? "",
    attribution: fd.get("attribution") ?? "",
    reason: fd.get("reason") ?? "",
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { error } = await getAdminClient().rpc("admin_update_news_item", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_item_id: parsed.data.itemId,
    p_title: parsed.data.title,
    p_summary: parsed.data.summary,
    p_attribution: parsed.data.attribution || null,
    p_reason: parsed.data.reason || null,
  });
  if (error) {
    return FAIL(
      error.message.includes("SUMMARY_TOO_LONG")
        ? "That is an article, not a summary."
        : "Could not save the item."
    );
  }
  revalidatePath("/newsroom");
  return { ok: true };
}

export async function requestNewsSync(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_news_sources");
  const parsed = newsSyncNowSchema.safeParse({
    sourceId: (fd.get("sourceId") ?? "").toString(),
    dryRun: fd.get("dryRun") ?? "true",
  });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_request_news_sync", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_source_id: parsed.data.sourceId || null,
    p_dry_run: parsed.data.dryRun === "true",
  });
  if (error) {
    return FAIL(
      error.message.includes("AUTOMATION_OFF")
        ? "News automation is switched off."
        : error.message.includes("SOURCE_DISABLED")
          ? "That source is disabled."
          : "Could not queue the sync."
    );
  }
  revalidatePath("/newsroom");
  return { ok: true, message: "Sync queued." };
}
