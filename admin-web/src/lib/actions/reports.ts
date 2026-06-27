"use server";

import { revalidatePath } from "next/cache";

import { can } from "@/lib/auth/permissions";
import { requireAdmin, requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import {
  banFromReportSchema,
  hideTargetSchema,
  reportActionSchema,
  strikeFromReportSchema,
} from "@/lib/validation/reports";

export type ActionState = { ok: boolean; error?: string };
const FAIL = (error: string): ActionState => ({ ok: false, error });

async function setStatus(
  adminId: string,
  adminEmail: string,
  reportId: string,
  status: string,
  note: string
) {
  return getAdminClient().rpc("admin_set_report_status", {
    p_admin_id: adminId,
    p_admin_email: adminEmail,
    p_report_id: reportId,
    p_status: status,
    p_note: note,
  });
}

export async function markReportReviewing(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_reports");
  const parsed = reportActionSchema.safeParse({ reportId: fd.get("reportId"), reason: fd.get("reason") });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { error } = await setStatus(admin.userId, admin.email, parsed.data.reportId, "reviewing", parsed.data.reason);
  if (error) return FAIL("Action failed.");
  revalidatePath("/reports");
  return { ok: true };
}

export async function dismissReport(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_reports");
  const parsed = reportActionSchema.safeParse({ reportId: fd.get("reportId"), reason: fd.get("reason") });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { error } = await setStatus(admin.userId, admin.email, parsed.data.reportId, "dismissed", parsed.data.reason);
  if (error) return FAIL("Action failed.");
  revalidatePath("/reports");
  return { ok: true };
}

export async function addReportNote(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_reports");
  const parsed = reportActionSchema.safeParse({ reportId: fd.get("reportId"), reason: fd.get("reason") });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { error } = await getAdminClient().rpc("admin_add_note", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_target_type: "report",
    p_target_id: parsed.data.reportId,
    p_note: parsed.data.reason,
  });
  if (error) return FAIL("Could not save note.");
  revalidatePath("/reports");
  return { ok: true };
}

// Hide the reported post/comment, then mark the report actioned (both audited).
export async function hideReportTarget(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const parsed = hideTargetSchema.safeParse({
    reportId: fd.get("reportId"),
    subjectType: fd.get("subjectType"),
    subjectId: fd.get("subjectId"),
    reason: fd.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { subjectType, subjectId, reportId, reason } = parsed.data;

  const perm = subjectType === "post" ? "hide_post" : "hide_comment";
  if (!can(admin.role, perm)) return FAIL("You don't have permission for that.");

  const rpc = subjectType === "post" ? "admin_hide_post" : "admin_hide_comment";
  const key = subjectType === "post" ? "p_post_id" : "p_comment_id";
  const hideRes = await getAdminClient().rpc(rpc, {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    [key]: subjectId,
    p_reason: reason,
  });
  if (hideRes.error) return FAIL("Could not hide the target.");
  await setStatus(admin.userId, admin.email, reportId, "actioned", reason);
  revalidatePath("/reports");
  return { ok: true };
}

// Ban the reported user, then mark the report actioned.
export async function banReportedUser(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("ban_user");
  const parsed = banFromReportSchema.safeParse({
    reportId: fd.get("reportId"),
    reportedUserId: fd.get("reportedUserId"),
    reason: fd.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { error } = await getAdminClient().rpc("admin_ban_user", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_target_user_id: parsed.data.reportedUserId,
    p_reason: parsed.data.reason,
  });
  if (error) return FAIL("Could not ban the user.");
  await setStatus(admin.userId, admin.email, parsed.data.reportId, "actioned", parsed.data.reason);
  revalidatePath("/reports");
  revalidatePath(`/users/${parsed.data.reportedUserId}`);
  return { ok: true };
}

// Add a (medium) strike to the reported user.
export async function addReportStrike(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_reports");
  const parsed = strikeFromReportSchema.safeParse({
    reportId: fd.get("reportId"),
    userId: fd.get("userId"),
    reason: fd.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { error } = await getAdminClient().rpc("admin_add_strike", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_user_id: parsed.data.userId,
    p_severity: "medium",
    p_reason: parsed.data.reason,
    p_report_id: parsed.data.reportId,
  });
  if (error) return FAIL("Could not add strike.");
  revalidatePath("/reports");
  return { ok: true };
}
