"use server";

import { randomUUID } from "node:crypto";

import { revalidatePath } from "next/cache";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import { maybeUpload } from "@/lib/storage/upload";
import {
  createSeedAccountSchema,
  createSeedPostSchema,
  featurePostSchema,
  seedCommentSchema,
  seedStatusSchema,
  updateSeedProfileSchema,
} from "@/lib/validation/seed";

export type ActionState = { ok: boolean; error?: string };
const FAIL = (error: string): ActionState => ({ ok: false, error });

// Create the official seed account: make a confirmed auth user (Auth Admin API),
// then flag the profile + register the seed_accounts row via the audited RPC. If
// the RPC fails (e.g. username taken) the just-created auth user is rolled back.
export async function createSeedAccount(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_seed");
  const parsed = createSeedAccountSchema.safeParse({
    displayName: fd.get("displayName"),
    username: fd.get("username"),
    bio: fd.get("bio"),
    seedType: fd.get("seedType"),
    publicLabel: fd.get("publicLabel"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { displayName, username, bio, seedType, publicLabel } = parsed.data;

  // Upload the optional profile picture first, so a bad image fails before we
  // create the auth account.
  const avatar = await maybeUpload(fd.get("avatar"), "avatars");
  if (avatar.error) return FAIL(avatar.error);

  const client = getAdminClient();
  const email = `${username}@seed.wearthemood.com`;
  const created = await client.auth.admin.createUser({
    email,
    password: `${randomUUID()}Aa1!`,
    email_confirm: true,
  });
  if (created.error || !created.data.user) {
    return FAIL("Could not create the account (username may be taken).");
  }
  const userId = created.data.user.id;

  const { error } = await client.rpc("admin_register_seed_account", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_user_id: userId,
    p_display_name: displayName,
    p_username: username,
    p_bio: bio || null,
    p_seed_type: seedType,
    p_public_label: publicLabel,
  });
  if (error) {
    await client.auth.admin.deleteUser(userId); // roll back the orphaned auth user
    return FAIL(
      error.message.includes("SEED_DISABLED")
        ? "Seed creation is disabled."
        : "Could not register the seed account (username may be taken)."
    );
  }

  if (avatar.url) {
    await client.rpc("admin_set_seed_avatar", {
      p_admin_id: admin.userId,
      p_admin_email: admin.email,
      p_user_id: userId,
      p_url: avatar.url,
    });
  }

  revalidatePath("/seed");
  return { ok: true };
}

// Set / update an existing seed account's profile picture.
export async function setSeedAvatar(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_seed");
  const userId = String(fd.get("userId") ?? "");
  const upload = await maybeUpload(fd.get("avatar"), "avatars");
  if (upload.error) return FAIL(upload.error);
  if (!upload.url) return FAIL("Select an image.");
  const { error } = await getAdminClient().rpc("admin_set_seed_avatar", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_user_id: userId,
    p_url: upload.url,
  });
  if (error) return FAIL("Could not set the picture.");
  revalidatePath("/seed");
  return { ok: true };
}

export async function createSeedPost(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("create_seed_posts");
  const parsed = createSeedPostSchema.safeParse({
    seedUserId: fd.get("seedUserId"),
    caption: fd.get("caption"),
    imageUrl: fd.get("imageUrl"),
    tags: fd.get("tags"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");

  // The look image is either an upload or the URL field; at least one is required.
  const upload = await maybeUpload(fd.get("imageFile"), "looks");
  if (upload.error) return FAIL(upload.error);
  const imageUrl = upload.url || parsed.data.imageUrl || "";
  if (!imageUrl) return FAIL("Add a look image — upload a photo or paste a URL.");

  const tags = (parsed.data.tags || "")
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean)
    .slice(0, 10);

  const { error } = await getAdminClient().rpc("admin_create_seed_post", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_seed_user_id: parsed.data.seedUserId,
    p_caption: parsed.data.caption || null,
    p_image_url: imageUrl,
    p_tags: tags,
  });
  if (error) return FAIL("Could not create the seed post.");
  revalidatePath("/seed");
  return { ok: true };
}

export async function setSeedStatus(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_seed");
  const parsed = seedStatusSchema.safeParse({ seedId: fd.get("seedId"), status: fd.get("status") });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_set_seed_account_status", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_seed_id: Number(parsed.data.seedId),
    p_status: parsed.data.status,
  });
  if (error) return FAIL("Action failed.");
  revalidatePath("/seed");
  return { ok: true };
}

export async function featurePost(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_seed");
  const parsed = featurePostSchema.safeParse({ postId: fd.get("postId"), featured: fd.get("featured") });
  if (!parsed.success) return FAIL("Invalid input.");
  const { error } = await getAdminClient().rpc("admin_feature_post", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_post_id: parsed.data.postId,
    p_featured: parsed.data.featured === "true",
  });
  if (error) return FAIL("Action failed.");
  revalidatePath("/seed");
  return { ok: true };
}

// ── operate a seed account like a real profile ───────────────────────────────
export async function updateSeedProfile(
  _p: ActionState | null,
  fd: FormData
): Promise<ActionState> {
  const admin = await requirePermission("manage_seed");
  const parsed = updateSeedProfileSchema.safeParse({
    userId: fd.get("userId"),
    displayName: fd.get("displayName"),
    username: fd.get("username"),
    bio: fd.get("bio"),
    publicLabel: fd.get("publicLabel"),
    styleTags: fd.get("styleTags"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const tags = (parsed.data.styleTags || "")
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean)
    .slice(0, 12);
  const { error } = await getAdminClient().rpc("admin_update_seed_profile", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_user_id: parsed.data.userId,
    p_display_name: parsed.data.displayName,
    p_username: parsed.data.username,
    p_bio: parsed.data.bio || null,
    p_public_label: parsed.data.publicLabel,
    p_style_tags: tags,
  });
  if (error) {
    return FAIL(
      error.message.includes("duplicate") || error.message.includes("unique")
        ? "That username is already taken."
        : "Could not update the profile."
    );
  }
  revalidatePath("/seed");
  return { ok: true };
}

// Like/unlike a SEED post AS a seed account (the RPC rejects non-seed targets).
export async function seedLike(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_seed");
  const seedUserId = String(fd.get("seedUserId") ?? "");
  const postId = String(fd.get("postId") ?? "");
  const like = fd.get("like") !== "false";
  const { error } = await getAdminClient().rpc("admin_seed_like", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_seed_user_id: seedUserId,
    p_post_id: postId,
    p_like: like,
  });
  if (error) {
    return FAIL(
      error.message.includes("SEED_POST")
        ? "Seed accounts can only engage other seed posts."
        : "Action failed."
    );
  }
  revalidatePath("/seed");
  return { ok: true };
}

// Comment on a SEED post AS a seed account.
export async function seedComment(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_seed");
  const parsed = seedCommentSchema.safeParse({
    seedUserId: fd.get("seedUserId"),
    postId: fd.get("postId"),
    body: fd.get("body"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");
  const { error } = await getAdminClient().rpc("admin_seed_comment", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_seed_user_id: parsed.data.seedUserId,
    p_post_id: parsed.data.postId,
    p_body: parsed.data.body,
  });
  if (error) {
    return FAIL(
      error.message.includes("SEED_POST")
        ? "Seed accounts can only engage other seed posts."
        : "Could not post the comment."
    );
  }
  revalidatePath("/seed");
  return { ok: true };
}

export async function toggleSeedEnabled(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("manage_seed");
  const enabled = fd.get("enabled") === "true";
  const { error } = await getAdminClient().rpc("admin_set_app_config", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_key: "seed_accounts_enabled",
    p_value: enabled,
  });
  if (error) return FAIL("Could not update the setting.");
  revalidatePath("/seed");
  return { ok: true };
}

// ── winddown ─────────────────────────────────────────────────────────────────
export async function archiveAllSeed(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("archive_all_seed");
  const reason = String(fd.get("reason") ?? "").trim();
  if (!reason) return FAIL("A reason is required.");
  const { error } = await getAdminClient().rpc("admin_archive_all_seed_content", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_reason: reason,
  });
  if (error) return FAIL("Action failed.");
  revalidatePath("/seed");
  return { ok: true };
}

export async function pauseAllSeed(): Promise<ActionState> {
  const admin = await requirePermission("archive_all_seed");
  const { error } = await getAdminClient().rpc("admin_pause_all_seed_accounts", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
  });
  if (error) return FAIL("Action failed.");
  revalidatePath("/seed");
  return { ok: true };
}

// Owner-only + double-confirmed in the UI (type the confirm phrase).
export async function deleteAllSeed(_p: ActionState | null, fd: FormData): Promise<ActionState> {
  const admin = await requirePermission("delete_seed");
  if (String(fd.get("confirm") ?? "") !== "DELETE ALL SEED") {
    return FAIL('Type "DELETE ALL SEED" to confirm.');
  }
  const { error } = await getAdminClient().rpc("admin_delete_all_seed_accounts", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
  });
  if (error) return FAIL("Action failed.");
  revalidatePath("/seed");
  return { ok: true };
}
