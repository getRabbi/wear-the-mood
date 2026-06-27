import "server-only";

import { requireAdmin, requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";

export type AuditEntry = {
  id: number;
  admin_id: string | null;
  admin_email: string | null;
  action: string;
  target_type: string;
  target_id: string | null;
  reason: string | null;
  metadata: Record<string, unknown> | null;
  before_data: Record<string, unknown> | null;
  after_data: Record<string, unknown> | null;
  ip_address: string | null;
  request_id: string | null;
  created_at: string;
};

export type AuditFilters = {
  action?: string | null;
  targetType?: string | null;
  targetId?: string | null;
  adminEmail?: string | null;
  from?: string | null;
  to?: string | null;
  limit?: number;
  offset?: number;
};

function buildQuery(filters: AuditFilters) {
  let q = getAdminClient()
    .from("admin_audit_log")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false });
  if (filters.action) q = q.eq("action", filters.action);
  if (filters.targetType) q = q.eq("target_type", filters.targetType);
  if (filters.targetId) q = q.eq("target_id", filters.targetId);
  if (filters.adminEmail) q = q.ilike("admin_email", `%${filters.adminEmail}%`);
  if (filters.from) q = q.gte("created_at", filters.from);
  if (filters.to) q = q.lte("created_at", filters.to);
  return q;
}

export async function listAuditLog(
  filters: AuditFilters
): Promise<{ rows: AuditEntry[]; total: number }> {
  await requirePermission("view_audit");
  const limit = filters.limit ?? 50;
  const offset = filters.offset ?? 0;
  const { data, count, error } = await buildQuery(filters).range(offset, offset + limit - 1);
  if (error) throw new Error(`listAuditLog failed: ${error.message}`);
  return { rows: (data ?? []) as AuditEntry[], total: count ?? 0 };
}

/** For the export route: a larger pull (capped) with the same filters. */
export async function exportAuditLog(filters: AuditFilters): Promise<AuditEntry[]> {
  await requirePermission("view_audit");
  const { data, error } = await buildQuery(filters).range(0, 4999);
  if (error) throw new Error(`exportAuditLog failed: ${error.message}`);
  return (data ?? []) as AuditEntry[];
}

export type AdminUserRow = {
  id: string;
  user_id: string;
  email: string;
  role: string;
  status: string;
  created_at: string;
};

export async function listAdmins(): Promise<AdminUserRow[]> {
  await requirePermission("manage_settings");
  const { data, error } = await getAdminClient()
    .from("admin_users")
    .select("id, user_id, email, role, status, created_at")
    .order("created_at", { ascending: true });
  if (error) throw new Error(`listAdmins failed: ${error.message}`);
  return (data ?? []) as AdminUserRow[];
}

export async function getAppConfig(): Promise<Record<string, boolean>> {
  await requireAdmin();
  const { data, error } = await getAdminClient()
    .from("app_config")
    .select("key, value")
    .in("key", ["seed_accounts_enabled", "public_official_badges_enabled", "maintenance_mode"]);
  if (error) throw new Error(`getAppConfig failed: ${error.message}`);
  const out: Record<string, boolean> = {};
  for (const r of data ?? []) out[r.key as string] = r.value === true;
  return out;
}
