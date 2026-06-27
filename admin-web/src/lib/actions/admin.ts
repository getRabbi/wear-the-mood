"use server";

import { revalidatePath } from "next/cache";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import { setConfigSchema, upsertAdminSchema } from "@/lib/validation/admin";

export type ActionState = { ok: boolean; error?: string };
const FAIL = (error: string): ActionState => ({ ok: false, error });

export async function setConfig(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_settings");
  const parsed = setConfigSchema.safeParse({ key: fd.get("key"), value: fd.get("value") });
  if (!parsed.success) return FAIL("Invalid setting.");
  const { error } = await getAdminClient().rpc("admin_set_app_config", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_key: parsed.data.key,
    p_value: parsed.data.value === "true",
  });
  if (error) return FAIL("Could not update the setting.");
  revalidatePath("/settings");
  return { ok: true };
}

export async function upsertAdmin(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_admin_users");
  const parsed = upsertAdminSchema.safeParse({ email: fd.get("email"), role: fd.get("role") });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { error } = await getAdminClient().rpc("admin_upsert_admin", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_target_email: parsed.data.email,
    p_role: parsed.data.role,
  });
  if (error) {
    return FAIL(
      error.message.includes("AUTH_USER_NOT_FOUND")
        ? "No account with that email — they must sign up first."
        : "Could not save the admin."
    );
  }
  revalidatePath("/settings");
  return { ok: true };
}

export async function setAdminStatus(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("change_admin_roles");
  const userId = String(fd.get("userId") ?? "");
  const status = String(fd.get("status") ?? "");
  const { error } = await getAdminClient().rpc("admin_set_admin_status", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_target_user_id: userId,
    p_status: status,
  });
  if (error) {
    return FAIL(
      error.message.includes("NO_SELF_LOCKOUT")
        ? "You can't disable your own account."
        : "Could not update the admin."
    );
  }
  revalidatePath("/settings");
  return { ok: true };
}
