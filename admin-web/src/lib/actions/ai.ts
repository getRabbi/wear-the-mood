"use server";

import { revalidatePath } from "next/cache";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import {
  generatedImageActionSchema,
  generatedImageFromReportSchema,
} from "@/lib/validation/ai";

export type ActionState = { ok: boolean; error?: string };
const FAIL = (error: string): ActionState => ({ ok: false, error });

async function runImageAction(rpc: string, formData: FormData): Promise<ActionState> {
  const admin = await requirePermission("moderate_ai_images");
  const parsed = generatedImageActionSchema.safeParse({
    imageId: formData.get("imageId"),
    reason: formData.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");

  const { error } = await getAdminClient().rpc(rpc, {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_image_id: parsed.data.imageId,
    p_reason: parsed.data.reason,
  });
  if (error) return FAIL("Action failed.");

  revalidatePath("/ai-images");
  return { ok: true };
}

export const removeGeneratedImage = async (_p: ActionState | null, fd: FormData) =>
  runImageAction("admin_remove_generated_image", fd);
export const restoreGeneratedImage = async (_p: ActionState | null, fd: FormData) =>
  runImageAction("admin_restore_generated_image", fd);

// Remove the reported AI output, then mark the report actioned (both audited) —
// mirrors hideGiveawayFromReport.
export async function removeGeneratedFromReport(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("moderate_ai_images");
  const parsed = generatedImageFromReportSchema.safeParse({
    reportId: fd.get("reportId"),
    imageId: fd.get("imageId"),
    reason: fd.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");

  const client = getAdminClient();
  const removeRes = await client.rpc("admin_remove_generated_image", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_image_id: parsed.data.imageId,
    p_reason: parsed.data.reason,
  });
  if (removeRes.error) return FAIL("Could not remove the output.");

  await client.rpc("admin_set_report_status", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_report_id: parsed.data.reportId,
    p_status: "actioned",
    p_note: parsed.data.reason,
  });
  revalidatePath("/reports");
  revalidatePath("/ai-images");
  return { ok: true };
}
