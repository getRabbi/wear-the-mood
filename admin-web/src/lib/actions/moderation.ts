"use server";

import { revalidatePath } from "next/cache";

import type { Permission } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import { bulkIdsSchema } from "@/lib/validation/reports";
import {
  commentActionSchema,
  postActionSchema,
  userActionSchema,
} from "@/lib/validation/moderation";

export type ActionState = { ok: boolean; error?: string };

const FAIL = (error: string): ActionState => ({ ok: false, error });

// ── user actions ─────────────────────────────────────────────────────────────
async function runUserAction(
  perm: Permission,
  rpc: string,
  formData: FormData,
  extra: Record<string, unknown> = {}
): Promise<ActionState> {
  const admin = await requirePermission(perm);
  const parsed = userActionSchema.safeParse({
    userId: formData.get("userId"),
    reason: formData.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");

  const { error } = await getAdminClient().rpc(rpc, {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_target_user_id: parsed.data.userId,
    p_reason: parsed.data.reason,
    ...extra,
  });
  if (error) return FAIL("Action failed.");

  revalidatePath(`/users/${parsed.data.userId}`);
  revalidatePath("/users");
  return { ok: true };
}

export const suspendUser = async (_p: ActionState | null, fd: FormData) =>
  runUserAction("suspend_user", "admin_suspend_user", fd, { p_banned_until: null });
export const banUser = async (_p: ActionState | null, fd: FormData) =>
  runUserAction("ban_user", "admin_ban_user", fd);
export const shadowbanUser = async (_p: ActionState | null, fd: FormData) =>
  runUserAction("shadowban_user", "admin_shadowban_user", fd);
export const restoreUser = async (_p: ActionState | null, fd: FormData) =>
  runUserAction("restore_user", "admin_restore_user", fd);
export const softDeleteUser = async (_p: ActionState | null, fd: FormData) =>
  runUserAction("soft_delete_user", "admin_soft_delete_user", fd);

// ── post actions ─────────────────────────────────────────────────────────────
async function runPostAction(
  perm: Permission,
  rpc: string,
  formData: FormData
): Promise<ActionState> {
  const admin = await requirePermission(perm);
  const parsed = postActionSchema.safeParse({
    postId: formData.get("postId"),
    reason: formData.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");

  const { error } = await getAdminClient().rpc(rpc, {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_post_id: parsed.data.postId,
    p_reason: parsed.data.reason,
  });
  if (error) return FAIL("Action failed.");

  revalidatePath("/posts");
  return { ok: true };
}

export const hidePost = async (_p: ActionState | null, fd: FormData) =>
  runPostAction("hide_post", "admin_hide_post", fd);
export const restorePost = async (_p: ActionState | null, fd: FormData) =>
  runPostAction("hide_post", "admin_restore_post", fd); // restore shares the hide capability
export const deletePost = async (_p: ActionState | null, fd: FormData) =>
  runPostAction("delete_post", "admin_delete_post", fd);

// Bulk hide (2.6) — plain <form action>; one audited RPC call per post.
export async function bulkHidePosts(fd: FormData): Promise<void> {
  const admin = await requirePermission("hide_post");
  const parsed = bulkIdsSchema.safeParse({
    ids: fd.getAll("ids").map(String),
    reason: fd.get("reason"),
  });
  if (!parsed.success) return;
  const client = getAdminClient();
  for (const id of parsed.data.ids) {
    await client.rpc("admin_hide_post", {
      p_admin_id: admin.userId,
      p_admin_email: admin.email,
      p_post_id: id,
      p_reason: parsed.data.reason,
    });
  }
  revalidatePath("/posts");
}

// ── comment actions ──────────────────────────────────────────────────────────
async function runCommentAction(
  perm: Permission,
  rpc: string,
  formData: FormData
): Promise<ActionState> {
  const admin = await requirePermission(perm);
  const parsed = commentActionSchema.safeParse({
    commentId: formData.get("commentId"),
    reason: formData.get("reason"),
  });
  if (!parsed.success) return FAIL(parsed.error.issues[0]?.message ?? "Invalid input.");

  const { error } = await getAdminClient().rpc(rpc, {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_comment_id: parsed.data.commentId,
    p_reason: parsed.data.reason,
  });
  if (error) return FAIL("Action failed.");

  revalidatePath("/comments");
  return { ok: true };
}

export const hideComment = async (_p: ActionState | null, fd: FormData) =>
  runCommentAction("hide_comment", "admin_hide_comment", fd);
export const restoreComment = async (_p: ActionState | null, fd: FormData) =>
  runCommentAction("hide_comment", "admin_restore_comment", fd);
export const deleteComment = async (_p: ActionState | null, fd: FormData) =>
  runCommentAction("delete_comment", "admin_delete_comment", fd);
