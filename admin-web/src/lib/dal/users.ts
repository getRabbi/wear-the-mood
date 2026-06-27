import "server-only";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";

// Shapes mirror the jsonb returned by admin_list_users / admin_user_detail
// (migration 0025). Every DAL function re-verifies admin auth + permission (§9.3).

export type UserListRow = {
  user_id: string;
  display_name: string | null;
  username: string | null;
  email: string | null;
  avatar_url: string | null;
  account_status: string;
  is_seed: boolean;
  is_official: boolean;
  public_label: string | null;
  tier: string;
  created_at: string;
  credits_total: number;
  post_count: number;
  report_count: number;
};

export type UserListResult = {
  total: number;
  limit: number;
  offset: number;
  rows: UserListRow[];
};

export type UserListParams = {
  search?: string | null;
  status?: string | null;
  seed?: boolean | null;
  tier?: string | null;
  sort?: string | null;
  limit?: number;
  offset?: number;
};

export async function listUsers(params: UserListParams): Promise<UserListResult> {
  await requirePermission("view_users");
  const { data, error } = await getAdminClient().rpc("admin_list_users", {
    p_search: params.search ?? null,
    p_status: params.status ?? null,
    p_seed: params.seed ?? null,
    p_tier: params.tier ?? null,
    p_sort: params.sort ?? "joined_desc",
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listUsers failed: ${error.message}`);
  return data as UserListResult;
}

export type UserDetail = {
  profile: {
    user_id: string;
    display_name: string | null;
    username: string | null;
    email: string | null;
    avatar_url: string | null;
    bio: string | null;
    account_status: string;
    ban_reason: string | null;
    banned_at: string | null;
    banned_until: string | null;
    deleted_at: string | null;
    is_seed: boolean;
    is_official: boolean;
    public_label: string | null;
    timezone: string | null;
    created_at: string;
  } | null;
  subscription: {
    tier: string;
    status: string;
    current_period_start: string | null;
    current_period_end: string | null;
    store: string | null;
    product_id: string | null;
  } | null;
  credits: {
    balance: number;
    topup_balance: number;
    daily_free_used: number;
    total: number;
  } | null;
  counts: {
    post_count: number;
    comment_count: number;
    follower_count: number;
    following_count: number;
    reports_against: number;
    reports_by: number;
  };
  recent_posts: Array<{
    id: string;
    caption: string | null;
    status: string;
    like_count: number;
    comment_count: number;
    created_at: string;
  }>;
  recent_comments: Array<{
    id: string;
    post_id: string;
    body: string;
    status: string;
    created_at: string;
  }>;
  reports_against_list: Array<{
    id: number;
    subject_type: string;
    subject_id: string;
    reason: string | null;
    status: string;
    created_at: string;
  }>;
  notes: Array<{
    id: number;
    note: string;
    created_at: string;
    created_by_email: string | null;
  }>;
  audit: Array<{
    id: number;
    action: string;
    admin_email: string | null;
    reason: string | null;
    created_at: string;
  }>;
};

/** Returns the user's full moderation profile, or null if not found. */
export async function getUserDetail(userId: string): Promise<UserDetail | null> {
  await requirePermission("view_users");
  const { data, error } = await getAdminClient().rpc("admin_user_detail", {
    p_user_id: userId,
  });
  if (error) {
    // admin_user_detail raises P0002 for an unknown user → treat as not-found.
    if (error.message?.includes("USER_NOT_FOUND")) return null;
    throw new Error(`getUserDetail failed: ${error.message}`);
  }
  return data as UserDetail;
}
