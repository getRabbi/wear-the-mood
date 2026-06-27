import "server-only";

import { requireAdmin } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import type { UserListResult, UserListRow } from "@/lib/dal/users";

export type DashboardStats = {
  total_users: number;
  new_users_today: number;
  active_users_7d: number;
  total_posts: number;
  posts_today: number;
  pending_reports: number;
  reports_today: number;
  pending_appeals: number;
  banned_users: number;
  suspended_users: number;
  shadowbanned_users: number;
  active_seed_accounts: number;
  active_subscribers: number;
  credits_issued_today: number;
  failed_tryons_today: number;
};

export async function getDashboardStats(): Promise<DashboardStats> {
  await requireAdmin(); // view_dashboard is granted to all admin roles
  const { data, error } = await getAdminClient().rpc("admin_dashboard_stats");
  if (error) throw new Error(`dashboard stats failed: ${error.message}`);
  return data as DashboardStats;
}

/** Latest joined users for the dashboard table (reuses the list RPC). */
export async function getRecentUsers(limit = 8): Promise<UserListRow[]> {
  await requireAdmin();
  const { data, error } = await getAdminClient().rpc("admin_list_users", {
    p_search: null,
    p_status: null,
    p_seed: null,
    p_tier: null,
    p_sort: "joined_desc",
    p_limit: limit,
    p_offset: 0,
  });
  if (error) throw new Error(`recent users failed: ${error.message}`);
  return (data as UserListResult).rows;
}

export type AuditEntry = {
  id: number;
  action: string;
  admin_email: string | null;
  target_type: string;
  target_id: string | null;
  reason: string | null;
  created_at: string;
};

/** Latest admin actions (dashboard "audit snippets" + reused on user detail). */
export async function getRecentAudit(limit = 10): Promise<AuditEntry[]> {
  await requireAdmin();
  const { data, error } = await getAdminClient()
    .from("admin_audit_log")
    .select("id, action, admin_email, target_type, target_id, reason, created_at")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw new Error(`recent audit failed: ${error.message}`);
  return (data ?? []) as AuditEntry[];
}
