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
  subcategory: string | null;
  audience: string | null;
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
  /** The AI try-on gate, which is NOT the display gate (migration 0065). */
  tryon_ready: boolean;
  manual_override: boolean;
  manual_override_fields: string[];
  tryon_image_url: string | null;
  tryon_image_source: string | null;
  image_urls: string[];
  last_synced_at: string | null;
  last_seen_in_feed_at: string | null;
  missing_run_count: number;
  deactivated_by_sync_at: string | null;
  country_eligibility: string;
  /** HOST ONLY. The tracking parameters decide who gets paid and never leave
   *  the database — the host is enough to confirm a link points where it should. */
  affiliate_host: string | null;
  /** An EXPLICIT product-level rights decision. Null means inherit (0067). */
  image_rights_override: string | null;
  /** What actually governs: override where set, otherwise the product's status. */
  effective_image_rights: string;
  /** The merchant's default, shown beside the override so "inherit" has a value. */
  merchant_image_rights_default: string;
  /** `product_tryon_readiness()` — the server's own breakdown, not a re-derivation. */
  tryon_readiness: TryOnReadiness;
  /** The explicit ENABLEMENT decision. Null inherits the merchant mode (0068). */
  tryon_policy_override: "on" | "off" | null;
  merchant_tryon_mode: TryOnMode;
  /** What the mode and the override resolve to for this product. */
  effective_tryon_policy: "on" | "off";
  rights_basis: string | null;
  rights_reference: string | null;
  rights_verified_at: string | null;
  rights_verified_by: string | null;
  total_count: number;
};

/** Merchant try-on COVERAGE. Never a rights value — see `image_rights_*`. */
export type TryOnMode = "off" | "all" | "selected";

/**
 * Why a product is or is not try-on ready, straight from the database.
 *
 * The console must never re-implement this: `product_tryon_ready()` is the gate
 * the API and the RLS policy both read, and a second opinion rendered in a
 * browser is how an operator ends up trusting a screen that disagrees with what
 * users actually get.
 */
export type TryOnReadiness = {
  effective_rights: string;
  rights_ok: boolean;
  /** Coverage, reported alongside rights and never merged with it (0068). */
  merchant_mode: TryOnMode;
  policy_override: "on" | "off" | null;
  effective_policy: "on" | "off";
  policy_ok: boolean;
  status: string;
  status_ok: boolean;
  image: string | null;
  image_ok: boolean;
  active_ok: boolean;
  servable: boolean;
  ready: boolean;
  blocked_by:
    | "rights_restricted"
    | "rights_not_licensed"
    | "merchant_tryon_off"
    | "product_tryon_off"
    | "product_not_selected"
    | "no_image"
    | "status_pending"
    | "status_not_ready"
    | null;
};

/**
 * `admin_merchant_tryon_summary()` — the counts on a merchant card.
 *
 * Every one is computed in SQL from the same functions the app and the RLS
 * policy read. The console renders them; it never adds them up itself, because a
 * count derived in a browser is a count that can quietly disagree with what
 * users actually get.
 */
export type MerchantTryOnSummary = {
  merchant_id: string;
  merchant_name: string;
  image_rights_default: string;
  tryon_mode: TryOnMode;
  has_feed_config: boolean;
  total_products: number;
  tryon_ready: number;
  rights_licensed: number;
  blocked_rights: number;
  blocked_no_image: number;
  blocked_status: number;
  explicitly_enabled: number;
  explicitly_disabled: number;
  awaiting_selection: number;
  /** What switching to `all` would expose — the number the dialog quotes. */
  eligible_if_all: number;
  eligible_if_selected: number;
};

/** What a merchant-level rights change would actually touch. */
export type MerchantRightsPreview = {
  merchant_id: string;
  merchant_name: string;
  current_default: string;
  inheriting_products: number;
  overridden_products: number;
  would_become_ready: number;
  currently_ready: number;
  has_feed_config: boolean;
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
  /** Coverage (0068). Independent of `image_rights_default` by design. */
  tryon_mode: TryOnMode;
  rights_basis: string | null;
  rights_reference: string | null;
  rights_verified_at: string | null;
  rights_verified_by: string | null;
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

/**
 * The numbers behind the licensing confirmation.
 *
 * Read BEFORE the dialog opens so the warning quotes the real count of affected
 * products rather than an estimate — "this will affect some products" is not a
 * thing anyone can weigh.
 */
export async function getMerchantRightsPreview(
  merchantId: string
): Promise<MerchantRightsPreview | null> {
  await requirePermission("view_catalog");
  const { data, error } = await getAdminClient().rpc("admin_merchant_rights_preview", {
    p_merchant_id: merchantId,
  });
  if (error) return null;
  const rows = (data ?? []) as MerchantRightsPreview[];
  return rows[0] ?? null;
}

/**
 * The coverage diagnostics for one merchant.
 *
 * Read with the page so a mode-change dialog can quote a real number the moment
 * it opens, and so the card can say what is actually standing in the way —
 * "92 missing compatible images" is a queue of work, "some products are not
 * ready" is not.
 */
export async function getMerchantTryOnSummary(
  merchantId: string
): Promise<MerchantTryOnSummary | null> {
  await requirePermission("view_catalog");
  const { data, error } = await getAdminClient().rpc("admin_merchant_tryon_summary", {
    p_merchant_id: merchantId,
  });
  if (error) return null;
  const rows = (data ?? []) as MerchantTryOnSummary[];
  return rows[0] ?? null;
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

// ── affiliate networks (Awin) ───────────────────────────────────────────────
//
// Note what is NOT in these types: any feed URL, and anything a credential
// could be reconstructed from. The authenticated download URL is built in the
// backend at download time and is never persisted, so there is no admin read
// that could return it.

export type NetworkMerchantRow = {
  merchant_id: string;
  name: string;
  slug: string;
  approved: boolean;
  network: string;
  network_advertiser_id: string;
  network_metadata: Record<string, unknown>;
  network_last_seen_at: string | null;
  feed_health: string;
  last_synced_at: string | null;
  sync_enabled: boolean;
  source_kind: string | null;
  image_rights_default: string | null;
  feed_count: number;
  enabled_feed_count: number;
  removed_feed_count: number;
  needs_review_count: number;
  declared_products: number;
  product_count: number;
  active_product_count: number;
  // Products whose feed said nothing about shipping. They are answered by the
  // merchant's verified list, so this is the number waiting on that list.
  unknown_shipping_count: number;
  shipping_countries: string[] | null;
  last_run_status: string | null;
  last_run_complete: boolean | null;
  last_run_at: string | null;
};

export type MerchantFeedRow = {
  id: string;
  network: string;
  network_feed_id: string;
  name: string | null;
  language: string | null;
  region: string | null;
  vertical: string | null;
  product_count: number | null;
  source_updated_at: string | null;
  enabled: boolean;
  needs_review: boolean;
  review_reason: string | null;
  last_seen_at: string | null;
  removed_at: string | null;
};

export type DiscoveryRunRow = {
  id: string;
  network: string;
  status: string;
  trigger_source: string;
  triggered_by: string | null;
  advertisers_seen: number;
  advertisers_added: number;
  feeds_seen: number;
  feeds_added: number;
  feeds_updated: number;
  feeds_removed: number;
  errors: unknown[];
  error_message: string | null;
  started_at: string;
  finished_at: string | null;
  duration_ms: number | null;
};

export async function listNetworkMerchants(network?: string): Promise<NetworkMerchantRow[]> {
  await requirePermission("view_catalog");
  const { data, error } = await getAdminClient().rpc("admin_list_network_merchants", {
    p_network: network || null,
  });
  if (error) return [];
  return (data ?? []) as NetworkMerchantRow[];
}

export async function listMerchantFeeds(merchantId: string): Promise<MerchantFeedRow[]> {
  await requirePermission("view_catalog");
  const { data, error } = await getAdminClient().rpc("admin_list_merchant_feeds", {
    p_merchant_id: merchantId,
  });
  if (error) return [];
  return (data ?? []) as MerchantFeedRow[];
}

export async function listDiscoveryRuns(limit = 10): Promise<DiscoveryRunRow[]> {
  await requirePermission("view_catalog");
  const { data, error } = await getAdminClient().rpc("admin_list_discovery_runs", {
    p_limit: limit,
  });
  if (error) return [];
  return (data ?? []) as DiscoveryRunRow[];
}

/**
 * Whether the network connector can reach the account — without this process
 * ever holding the credential that proves it.
 *
 * The console deliberately does NOT read the API key. Reading it would mean
 * provisioning the secret to a second deployment just to render a boolean, and
 * every place a secret lives is a place it can leak. The backend is the only
 * holder; what the console reads instead is the run history, which is the
 * better answer anyway: a key that is set but wrong looks "configured" to an
 * env check and is broken in reality.
 *
 * `skipped` is precisely what a discovery pass records when the credentials are
 * missing, so it is the signal rather than an inference.
 */
export async function getNetworkConnection(network = "awin"): Promise<{
  configured: boolean | null;
  publisherId: string | null;
}> {
  await requirePermission("view_catalog");
  // Publisher id is an account identifier, not a secret — Awin puts it in every
  // tracked link we already store in `products.affiliate_ref`.
  const publisherId = process.env.AWIN_PUBLISHER_ID?.trim() || null;
  const { data, error } = await getAdminClient().rpc("admin_list_discovery_runs", { p_limit: 5 });
  if (error) return { configured: null, publisherId };
  const runs = ((data ?? []) as DiscoveryRunRow[]).filter((r) => r.network === network);
  if (runs.length === 0) return { configured: null, publisherId };
  return { configured: runs[0].status !== "skipped", publisherId };
}
