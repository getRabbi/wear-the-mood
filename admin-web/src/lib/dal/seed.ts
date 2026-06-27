import "server-only";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";

export type SeedAccountRow = {
  id: number;
  user_id: string;
  display_name: string | null;
  username: string | null;
  seed_type: string;
  status: string;
  public_label: string | null;
  created_at: string;
  profile_status: string;
  profile_picture_url: string | null;
  bio: string | null;
  style_tags: string[] | null;
  post_count: number;
};

export type SeedListResult = { total: number; limit: number; offset: number; rows: SeedAccountRow[] };

export async function listSeedAccounts(params: {
  status?: string | null;
  limit?: number;
  offset?: number;
}): Promise<SeedListResult> {
  await requirePermission("manage_seed");
  const { data, error } = await getAdminClient().rpc("admin_list_seed_accounts", {
    p_status: params.status ?? null,
    p_limit: params.limit ?? 50,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listSeedAccounts failed: ${error.message}`);
  return data as SeedListResult;
}

/** Whether seed account/post creation is currently enabled (app_config). */
export async function getSeedEnabled(): Promise<boolean> {
  await requirePermission("manage_seed");
  const { data, error } = await getAdminClient()
    .from("app_config")
    .select("value")
    .eq("key", "seed_accounts_enabled")
    .maybeSingle();
  if (error) throw new Error(`getSeedEnabled failed: ${error.message}`);
  return data?.value === true;
}
