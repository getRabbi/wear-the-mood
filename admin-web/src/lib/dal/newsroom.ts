import "server-only";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";

/** Newsroom reads. Same posture as the catalog DAL: RPC-only, re-gated here. */

export type NewsSourceRow = {
  id: string;
  slug: string;
  name: string;
  publisher: string | null;
  feed_url: string;
  feed_kind: string;
  enabled: boolean;
  priority: number;
  category: string | null;
  auto_publish: boolean;
  health: string;
  consecutive_failures: number;
  retry_after: string | null;
  last_success_at: string | null;
  item_count: number;
  pending_review_count: number;
};

export type NewsItemRow = {
  id: string;
  title: string;
  summary: string | null;
  source: string | null;
  url: string | null;
  canonical_url: string | null;
  image_url: string | null;
  published_at: string | null;
  status: string;
  source_id: string | null;
  source_name: string | null;
  author: string | null;
  attribution: string | null;
  created_at: string;
  total_count: number;
};

export type NewsRunRow = {
  id: string;
  source_id: string | null;
  source_name: string | null;
  status: string;
  trigger_source: string;
  triggered_by: string | null;
  dry_run: boolean;
  fetched: number;
  created: number;
  updated: number;
  duplicates: number;
  skipped: number;
  errors: { source?: string; error?: string }[];
  error_message: string | null;
  started_at: string;
  finished_at: string | null;
  duration_ms: number | null;
};

export async function listNewsSources(): Promise<NewsSourceRow[]> {
  await requirePermission("view_newsroom");
  const { data, error } = await getAdminClient().rpc("admin_list_news_sources", {});
  if (error) return [];
  return (data ?? []) as NewsSourceRow[];
}

export async function listNewsItems(params: {
  status?: string;
  sourceId?: string;
  search?: string;
  limit?: number;
  offset?: number;
}): Promise<NewsItemRow[]> {
  await requirePermission("view_newsroom");
  const { data, error } = await getAdminClient().rpc("admin_list_news_items", {
    p_status: params.status || null,
    p_source_id: params.sourceId || null,
    p_search: params.search || null,
    p_limit: params.limit ?? 50,
    p_offset: params.offset ?? 0,
  });
  if (error) return [];
  return (data ?? []) as NewsItemRow[];
}

export async function listNewsRuns(limit = 25): Promise<NewsRunRow[]> {
  await requirePermission("view_newsroom");
  const { data, error } = await getAdminClient().rpc("admin_list_news_sync_runs", {
    p_limit: limit,
  });
  if (error) return [];
  return (data ?? []) as NewsRunRow[];
}
