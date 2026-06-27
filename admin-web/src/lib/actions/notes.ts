"use server";

import { revalidatePath } from "next/cache";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import { addNoteSchema } from "@/lib/validation/notes";

export type ActionState = { ok: boolean; error?: string };

// Server Action — treated as a public entrypoint (§9.3): re-verify admin + the
// exact permission, validate with Zod, then mutate via the audited RPC (note +
// audit row written in one transaction by admin_add_note).
export async function addUserNote(
  _prev: ActionState | null,
  formData: FormData
): Promise<ActionState> {
  const admin = await requirePermission("add_note");

  const parsed = addNoteSchema.safeParse({
    targetType: formData.get("targetType"),
    targetId: formData.get("targetId"),
    note: formData.get("note"),
  });
  if (!parsed.success) {
    return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid input." };
  }

  const { targetType, targetId, note } = parsed.data;
  const { error } = await getAdminClient().rpc("admin_add_note", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_target_type: targetType,
    p_target_id: targetId,
    p_note: note,
  });
  if (error) {
    return { ok: false, error: "Could not save the note." };
  }

  if (targetType === "user") revalidatePath(`/users/${targetId}`);
  return { ok: true };
}
