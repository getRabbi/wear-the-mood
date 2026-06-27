"use server";

import { revalidatePath } from "next/cache";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import { creditAdjustSchema } from "@/lib/validation/billing";

export type ActionState = { ok: boolean; error?: string };
const FAIL = (error: string): ActionState => ({ ok: false, error });

export async function adjustCredits(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("adjust_credits");
  const parsed = creditAdjustSchema.safeParse({
    userId: fd.get("userId"),
    amount: fd.get("amount"),
    reason: fd.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");

  const { error } = await getAdminClient().rpc("admin_adjust_credits", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_target_user_id: parsed.data.userId,
    p_amount: parsed.data.amount,
    p_reason: parsed.data.reason,
  });
  if (error) {
    return FAIL(
      error.message.includes("INSUFFICIENT_BALANCE")
        ? "Not enough plan balance to deduct that much."
        : "Adjustment failed."
    );
  }
  revalidatePath(`/credits`);
  revalidatePath(`/users/${parsed.data.userId}`);
  return { ok: true };
}
