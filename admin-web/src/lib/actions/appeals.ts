"use server";

import { revalidatePath } from "next/cache";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import { appealResolveSchema } from "@/lib/validation/reports";

export type ActionState = { ok: boolean; error?: string };
const FAIL = (error: string): ActionState => ({ ok: false, error });

async function resolve(decision: "approved" | "denied", fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_appeals");
  const parsed = appealResolveSchema.safeParse({
    appealId: fd.get("appealId"),
    reason: fd.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { error } = await getAdminClient().rpc("admin_resolve_appeal", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_appeal_id: Number(parsed.data.appealId),
    p_decision: decision,
    p_note: parsed.data.reason,
  });
  if (error) return FAIL("Could not resolve the appeal.");
  revalidatePath("/appeals");
  return { ok: true };
}

export async function approveAppeal(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  return resolve("approved", fd);
}

export async function denyAppeal(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  return resolve("denied", fd);
}
