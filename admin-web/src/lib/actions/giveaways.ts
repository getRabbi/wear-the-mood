"use server";

import { revalidatePath } from "next/cache";

import type { Permission } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import {
  chatReviewSchema,
  giveawayActionSchema,
  giveawayFromReportSchema,
} from "@/lib/validation/giveaways";

export type ActionState = { ok: boolean; error?: string };
const FAIL = (error: string): ActionState => ({ ok: false, error });

// ── giveaway listing actions ─────────────────────────────────────────────────
async function runGiveawayAction(
  perm: Permission,
  rpc: string,
  formData: FormData
): Promise<ActionState> {
  const admin = await requirePermission(perm);
  const parsed = giveawayActionSchema.safeParse({
    giveawayId: formData.get("giveawayId"),
    reason: formData.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");

  const { error } = await getAdminClient().rpc(rpc, {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_giveaway_id: parsed.data.giveawayId,
    p_reason: parsed.data.reason,
  });
  if (error) return FAIL("Action failed.");

  revalidatePath("/giveaways");
  revalidatePath(`/giveaways/${parsed.data.giveawayId}`);
  return { ok: true };
}

export const hideGiveaway = async (_p: ActionState | null, fd: FormData) =>
  runGiveawayAction("moderate_giveaways", "admin_hide_giveaway", fd);
export const restoreGiveaway = async (_p: ActionState | null, fd: FormData) =>
  runGiveawayAction("moderate_giveaways", "admin_restore_giveaway", fd);
export const closeGiveaway = async (_p: ActionState | null, fd: FormData) =>
  runGiveawayAction("moderate_giveaways", "admin_close_giveaway", fd);
export const deleteGiveaway = async (_p: ActionState | null, fd: FormData) =>
  runGiveawayAction("moderate_giveaways", "admin_delete_giveaway", fd);

// Hide the reported listing, then mark the report actioned (both audited) —
// mirrors hideReportTarget for posts/comments.
export async function hideGiveawayFromReport(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("moderate_giveaways");
  const parsed = giveawayFromReportSchema.safeParse({
    reportId: fd.get("reportId"),
    giveawayId: fd.get("giveawayId"),
    reason: fd.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");

  const client = getAdminClient();
  const hideRes = await client.rpc("admin_hide_giveaway", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_giveaway_id: parsed.data.giveawayId,
    p_reason: parsed.data.reason,
  });
  if (hideRes.error) return FAIL("Could not hide the listing.");

  await client.rpc("admin_set_report_status", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_report_id: parsed.data.reportId,
    p_status: "actioned",
    p_note: parsed.data.reason,
  });
  revalidatePath("/reports");
  revalidatePath("/giveaways");
  return { ok: true };
}

// ── pickup-chat report review ─────────────────────────────────────────────────
// 'clear' → drop report_flag (retention cron redacts on its normal pass) and,
// when a report is linked, dismiss it. 'keep_frozen' → transcript stays
// preserved for escalation and the linked report is marked actioned.
export async function reviewPickupChat(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("review_chats");
  const parsed = chatReviewSchema.safeParse({
    chatId: fd.get("chatId"),
    decision: fd.get("decision"),
    reportId: fd.get("reportId") ?? "",
    reason: fd.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { chatId, decision, reportId, reason } = parsed.data;

  const client = getAdminClient();
  const { error } = await client.rpc("admin_review_pickup_chat", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_chat_id: chatId,
    p_decision: decision,
    p_reason: reason,
  });
  if (error) return FAIL("Could not record the review.");

  if (reportId) {
    await client.rpc("admin_set_report_status", {
      p_admin_id: admin.userId,
      p_admin_email: admin.email,
      p_report_id: reportId,
      p_status: decision === "clear" ? "dismissed" : "actioned",
      p_note: reason,
    });
  }
  revalidatePath("/reports");
  revalidatePath(`/giveaways/chats/${chatId}`);
  return { ok: true };
}
