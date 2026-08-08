import "server-only";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";

/**
 * Catalog + automation reads.
 *
 * Every function goes through an `admin_*` RPC rather than selecting tables
 * directly, for the same reason the rest of the console does: the RPC decides
 * which columns exist at all. That is what keeps a feed URL's query string and
 * an affiliate tag out of a page — `admin_list_merchants` returns the feed
 * HOST and the affiliate STATUS, and there is no shape of this code that can
 * accidentally return the secret, because it never arrives.
 *
 * Reads re-check permission here too. The page already gated, but a DAL
 * function is callable from anywhere and "the caller checked" is not a
 * guarantee (§9.3).
 */

export type ProductRow = {
  id: string;
  external_id: string;
  title: string;
  brand: string | null;
  category: string | null;
  price_minor: number;
  currency: string;
  stock_status: string;
  try_on_status: string;
  image_rights_status: string;
  active: boolean;
  sponsored: boolean;
  merchant_id: string;
  merchant_name: string;
  merchant_approved: boolean;
  servable: boolean;
  manual_override: boolean;
  manual_override_fields: string[];
  tryon_image_url: string | null;
  tryon_image_source: string | null;
  image_urls: string[];
  last_synced_at: string | null;
  last_seen_in_feed_at: string | null;
  missing_run_count: number;
  deactivated_by_sync_at: string | null;
  total_count: number;
};

export type MerchantRow = {
  id: string;
  slug: string;
  name: string;
  approved: boolean;
  feed_health: string;
  allowed_domains: string[];
  supported_countries: string[];
  shipping_countries: string[];
  last_synced_at: string | null;
  product_count: number;
  active_product_count: number;
  /** HOST ONLY — never the full feed URL, which can carry an API key. */
  feed_url_host: string | null;
  feed_enabled: boolean;
  feed_format: string | null;
  consecutive_failures: number;
  retry_after: string | null;
  locked_at: string | null;
  image_rights_default: string | null;
  /** STATUS ONLY — the affiliate tag identifies who gets paid (§40). */
  affiliate_status: string | null;
  affiliate_configured: boolean;
};

export type SyncRunRow = {
  id: string;
  merchant_id: string;
  merchant_name: string;
  status: string;
  trigger_source: string;
  triggered_by: string | null;
  dry_run: boolean;
  fetched: number;
  created: number;
  updated: number;
  unchanged: number;
  deactivated: number;
  reactivated: number;
  skipped: number;
  errors: { external_id?: string; error?: string }[];
  error_message: string | null;
  started_at: string;
  finished_at: string | null;
  duration_ms: number | null;
};

export async function listProducts(params: {
  search?: string;
  merchantId?: string;
  status?: string;
  tryOn?: string;
  limit?: number;
  offset?: number;
}): Promise<ProductRow[]> {
  await requirePermission("view_catalog");
  const { data, error } = await getAdminClient().rpc("admin_list_products", {
    p_search: params.search || null,
    p_merchant_id: params.merchantId || null,
    p_status: params.status || null,
    p_try_on: params.tryOn || null,
    p_limit: params.limit ?? 50,
    p_offset: params.offset ?? 0,
  });
  if (error) return [];
  return (data ?? []) as ProductRow[];
}

export async function listMerchants(): Promise<MerchantRow[]> {
  await requirePermission("view_catalog");
  const { data, error } = await getAdminClient().rpc("admin_list_merchants", {});
  if (error) return [];
  return (data ?? []) as MerchantRow[];
}

export async function listSyncRuns(merchantId?: string, limit = 25): Promise<SyncRunRow[]> {
  await requirePermission("view_catalog");
  const { data, error } = await getAdminClient().rpc("admin_list_product_sync_runs", {
    p_merchant_id: merchantId || null,
    p_limit: limit,
  });
  if (error) return [];
  return (data ?? []) as SyncRunRow[];
}

/** Whether product automation is currently allowed to run at all. */
export async function getAutomationFlag(key: string): Promise<boolean> {
  await requirePermission("view_catalog");
  const { data } = await getAdminClient()
    .from("feature_flags")
    .select("enabled")
    .eq("key", key)
    .maybeSingle();
  return !!data?.enabled;
}
