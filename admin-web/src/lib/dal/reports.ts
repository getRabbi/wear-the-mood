import "server-only";

import { requireAdmin, requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";

type PartyRef = {
  id: string;
  name: string | null;
  email: string | null;
  account_status?: string | null;
} | null;

// Keep in sync with what the app/backend actually file (drift guard, Phase Z):
// the app sends post/user/giveaway, the backend adds comment + giveaway_chat.
export type ReportSubjectType = "post" | "comment" | "user" | "giveaway" | "giveaway_chat";

export type ReportRow = {
  id: string;
  subject_type: ReportSubjectType | (string & {});
  subject_id: string;
  reason: string | null;
  details: string | null;
  status: string;
  created_at: string;
  reviewed_at: string | null;
  admin_note: string | null;
  reporter: PartyRef;
  reported_user: PartyRef;
  target_preview: Record<string, unknown> | null;
};

export type ReportListResult = { total: number; limit: number; offset: number; rows: ReportRow[] };

export async function listReports(params: {
  status?: string | null;
  targetType?: string | null;
  limit?: number;
  offset?: number;
}): Promise<ReportListResult> {
  await requirePermission("manage_reports");
  const { data, error } = await getAdminClient().rpc("admin_list_reports", {
    p_status: params.status ?? null,
    p_target_type: params.targetType ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listReports failed: ${error.message}`);
  return data as ReportListResult;
}

export type AppealRow = {
  id: number;
  user: PartyRef;
  target_type: string;
  target_id: string | null;
  action_log_id: number | null;
  message: string;
  status: string;
  admin_note: string | null;
  reviewed_at: string | null;
  created_at: string;
};

export type AppealListResult = { total: number; limit: number; offset: number; rows: AppealRow[] };

export async function listAppeals(params: {
  status?: string | null;
  limit?: number;
  offset?: number;
}): Promise<AppealListResult> {
  await requirePermission("manage_appeals");
  const { data, error } = await getAdminClient().rpc("admin_list_appeals", {
    p_status: params.status ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listAppeals failed: ${error.message}`);
  return data as AppealListResult;
}

export type ModerationBadges = { reports: number; appeals: number };

/** Pending counts for the sidebar badges (cheap head counts). */
export async function getModerationBadges(): Promise<ModerationBadges> {
  await requireAdmin();
  const client = getAdminClient();
  const [reports, appeals] = await Promise.all([
    client
      .from("reports")
      .select("*", { count: "exact", head: true })
      .in("status", ["open", "pending", "reviewing"]),
    client
      .from("moderation_appeals")
      .select("*", { count: "exact", head: true })
      .in("status", ["pending", "reviewing"]),
  ]);
  return { reports: reports.count ?? 0, appeals: appeals.count ?? 0 };
}
