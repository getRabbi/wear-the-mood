"use server";

import { revalidatePath } from "next/cache";

import { requirePermission } from "@/lib/auth/require-admin";
import { maybeUpload } from "@/lib/storage/upload";
import { getAdminClient } from "@/lib/supabase/admin";
import {
  flagToggleSchema,
  presetActiveSchema,
  presetUpdateSchema,
} from "@/lib/validation/ops";

export type ActionState = { ok: boolean; error?: string };
const FAIL = (error: string): ActionState => ({ ok: false, error });

// ── feature flags (audited kill-switch toggle) ───────────────────────────────
export async function setFeatureFlag(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_settings");
  const parsed = flagToggleSchema.safeParse({
    key: fd.get("key"),
    enabled: fd.get("enabled"),
  });
  if (!parsed.success) return FAIL("Invalid flag.");
  const { error } = await getAdminClient().rpc("admin_set_feature_flag", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_key: parsed.data.key,
    p_enabled: parsed.data.enabled === "true",
  });
  if (error) return FAIL("Could not update the flag.");
  revalidatePath("/settings");
  return { ok: true };
}

// ── try-on model presets ─────────────────────────────────────────────────────
export async function updateModelPreset(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_presets");
  const parsed = presetUpdateSchema.safeParse({
    presetId: fd.get("presetId"),
    name: fd.get("name"),
    imageUrl: fd.get("imageUrl") ?? "",
    sortOrder: fd.get("sortOrder"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");

  // A fresh upload wins over the pasted/existing URL.
  const upload = await maybeUpload(fd.get("imageFile"), "presets");
  if (upload.error) return FAIL(upload.error);
  const imageUrl = upload.url || parsed.data.imageUrl || "";

  const { error } = await getAdminClient().rpc("admin_update_model_preset", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_preset_id: parsed.data.presetId,
    p_name: parsed.data.name,
    p_image_url: imageUrl || null,
    p_sort_order: parsed.data.sortOrder,
  });
  if (error) return FAIL("Could not update the preset.");
  revalidatePath("/presets");
  return { ok: true };
}

export async function setPresetActive(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_presets");
  const parsed = presetActiveSchema.safeParse({
    presetId: fd.get("presetId"),
    active: fd.get("active"),
  });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_set_preset_active", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_preset_id: parsed.data.presetId,
    p_active: parsed.data.active === "true",
  });
  if (error) {
    return FAIL(
      error.message.includes("IMAGE_REQUIRED")
        ? "Upload a model image before activating this preset."
        : "Could not update the preset."
    );
  }
  revalidatePath("/presets");
  return { ok: true };
}
