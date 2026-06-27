"use server";

import { revalidatePath } from "next/cache";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import { campaignSchema } from "@/lib/validation/billing";

export type ActionState = { ok: boolean; error?: string };
const FAIL = (error: string): ActionState => ({ ok: false, error });

export async function createCampaign(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("send_push");
  const parsed = campaignSchema.safeParse({
    title: fd.get("title"),
    body: fd.get("body"),
    segment: fd.get("segment"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { error } = await getAdminClient().rpc("admin_create_notification_campaign", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_title: parsed.data.title,
    p_body: parsed.data.body,
    p_segment: parsed.data.segment,
  });
  if (error) return FAIL("Could not create the campaign.");
  revalidatePath("/notifications");
  return { ok: true };
}

export async function sendCampaign(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("send_push");
  const id = Number(fd.get("campaignId"));
  if (!Number.isInteger(id)) return FAIL("Bad campaign id.");
  const { error } = await getAdminClient().rpc("admin_send_notification_campaign", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_campaign_id: id,
  });
  if (error) return FAIL("Could not send the campaign.");
  revalidatePath("/notifications");
  return { ok: true };
}

export async function cancelCampaign(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("send_push");
  const id = Number(fd.get("campaignId"));
  if (!Number.isInteger(id)) return FAIL("Bad campaign id.");
  const { error } = await getAdminClient().rpc("admin_cancel_campaign", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_campaign_id: id,
  });
  if (error) return FAIL("Could not cancel the campaign.");
  revalidatePath("/notifications");
  return { ok: true };
}
