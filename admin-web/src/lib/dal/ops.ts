import "server-only";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";
import type {
  FeatureFlagsRow,
  PlansRow,
  TryonModelPresetsRow,
} from "@/lib/types/db.generated";

// Ops tooling (0040): feature flags, try-on model presets, AI cost, global
// billing views, per-user try-on jobs. Reads that are a plain single-table
// select go straight through the service client; aggregates/joins use RPCs.
// Direct-read row types derive from db.generated.ts (Phase Z) so a schema
// rename fails this build instead of erroring at runtime.

export type FeatureFlagRow = Pick<
  FeatureFlagsRow,
  "key" | "enabled" | "description" | "updated_at"
>;

export async function listFeatureFlags(): Promise<FeatureFlagRow[]> {
  await requirePermission("manage_settings");
  const { data, error } = await getAdminClient()
    .from("feature_flags")
    .select("key, enabled, description, updated_at")
    .order("key");
  if (error) throw new Error(`listFeatureFlags failed: ${error.message}`);
  return (data ?? []) as FeatureFlagRow[];
}

export type ModelPresetRow = TryonModelPresetsRow;

export async function listModelPresets(): Promise<ModelPresetRow[]> {
  await requirePermission("manage_presets");
  const { data, error } = await getAdminClient()
    .from("tryon_model_presets")
    .select("*")
    .order("kind")
    .order("sort_order");
  if (error) throw new Error(`listModelPresets failed: ${error.message}`);
  return (data ?? []) as ModelPresetRow[];
}

export type AiCostDay = {
  day: string;
  provider: string | null;
  calls: number;
  input_tokens: number;
  output_tokens: number;
  images: number;
  est_usd: number;
  failures: number;
};

export type AiCostSummary = {
  days: AiCostDay[];
  today_usd: number;
  last7_usd: number;
  total_usd: number;
};

export async function getAiCostDaily(days = 30): Promise<AiCostSummary> {
  await requirePermission("view_costs");
  const { data, error } = await getAdminClient().rpc("admin_ai_cost_daily", {
    p_days: days,
  });
  if (error) throw new Error(`getAiCostDaily failed: ${error.message}`);
  return data as AiCostSummary;
}

export type CreditTransactionRow = {
  id: string;
  user_id: string;
  delta: number;
  reason: string;
  balance_after: number | null;
  ref: string | null;
  created_at: string;
  user_name: string | null;
  user_username: string | null;
  user_email: string | null;
};

export type CreditTransactionList = {
  total: number;
  limit: number;
  offset: number;
  rows: CreditTransactionRow[];
};

export async function listCreditTransactions(params: {
  search?: string | null;
  reason?: string | null;
  limit?: number;
  offset?: number;
}): Promise<CreditTransactionList> {
  await requirePermission("adjust_credits");
  const { data, error } = await getAdminClient().rpc("admin_list_credit_transactions", {
    p_search: params.search ?? null,
    p_reason: params.reason ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listCreditTransactions failed: ${error.message}`);
  return data as CreditTransactionList;
}

export type TopUpRow = {
  id: string;
  user_id: string;
  sku: string;
  credits: number;
  price_usd: number | null;
  store: string | null;
  store_txn_id: string | null;
  created_at: string;
  user_name: string | null;
  user_email: string | null;
};

export type TopUpList = { total: number; limit: number; offset: number; rows: TopUpRow[] };

export async function listTopUpPurchases(params: {
  limit?: number;
  offset?: number;
}): Promise<TopUpList> {
  await requirePermission("view_subscriptions");
  const { data, error } = await getAdminClient().rpc("admin_list_top_up_purchases", {
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listTopUpPurchases failed: ${error.message}`);
  return data as TopUpList;
}

export type PlanRow = Pick<
  PlansRow,
  "tier" | "kind" | "price_usd" | "monthly_credits" | "hd_allowed" | "priority" | "active"
  | "updated_at"
>;

export async function listPlans(): Promise<PlanRow[]> {
  await requirePermission("view_subscriptions");
  const { data, error } = await getAdminClient()
    .from("plans")
    .select("tier, kind, price_usd, monthly_credits, hd_allowed, priority, active, updated_at")
    .order("price_usd");
  if (error) throw new Error(`listPlans failed: ${error.message}`);
  return (data ?? []) as PlanRow[];
}

export type UserTryonJob = {
  id: string;
  status: string;
  hd: boolean;
  model_source: string;
  provider: string | null;
  error: string | null;
  created_at: string;
};

export async function listUserTryonJobs(userId: string, limit = 10): Promise<UserTryonJob[]> {
  await requirePermission("view_users");
  const { data, error } = await getAdminClient().rpc("admin_list_tryon_jobs", {
    p_user_id: userId,
    p_limit: limit,
  });
  if (error) throw new Error(`listUserTryonJobs failed: ${error.message}`);
  return (data ?? []) as UserTryonJob[];
}
