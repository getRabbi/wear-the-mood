import "server-only";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";

export type CreditLedger = {
  credits: { balance: number; topup_balance: number; daily_free_used: number; total: number };
  subscription: {
    tier: string;
    status: string;
    current_period_start: string | null;
    current_period_end: string | null;
    store: string | null;
    product_id: string | null;
  } | null;
  ledger: Array<{
    id: string;
    delta: number;
    reason: string;
    balance_after: number | null;
    ref: string | null;
    created_at: string;
  }>;
};

export async function getCreditLedger(userId: string, limit = 30): Promise<CreditLedger> {
  await requirePermission("adjust_credits");
  const { data, error } = await getAdminClient().rpc("admin_credit_ledger", {
    p_user_id: userId,
    p_limit: limit,
  });
  if (error) throw new Error(`getCreditLedger failed: ${error.message}`);
  return data as CreditLedger;
}

export type SubscriptionRow = {
  user_id: string;
  display_name: string | null;
  username: string | null;
  email: string | null;
  tier: string;
  status: string;
  current_period_start: string | null;
  current_period_end: string | null;
  store: string | null;
  product_id: string | null;
};

export type SubscriptionList = { total: number; limit: number; offset: number; rows: SubscriptionRow[] };

export async function listSubscriptions(params: {
  tier?: string | null;
  status?: string | null;
  search?: string | null;
  limit?: number;
  offset?: number;
}): Promise<SubscriptionList> {
  await requirePermission("view_subscriptions");
  const { data, error } = await getAdminClient().rpc("admin_list_subscriptions", {
    p_tier: params.tier ?? null,
    p_status: params.status ?? null,
    p_search: params.search ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listSubscriptions failed: ${error.message}`);
  return data as SubscriptionList;
}

export type CampaignRow = {
  id: number;
  title: string;
  body: string;
  target_segment: string;
  status: string;
  scheduled_at: string | null;
  sent_at: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  created_by_email: string | null;
};

export type CampaignList = { total: number; limit: number; offset: number; rows: CampaignRow[] };

export async function listCampaigns(params: {
  status?: string | null;
  limit?: number;
  offset?: number;
}): Promise<CampaignList> {
  await requirePermission("send_push");
  const { data, error } = await getAdminClient().rpc("admin_list_notification_campaigns", {
    p_status: params.status ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listCampaigns failed: ${error.message}`);
  return data as CampaignList;
}
