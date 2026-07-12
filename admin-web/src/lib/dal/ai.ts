import "server-only";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";

// AI Studio (0033/0039). Shapes mirror the jsonb from the 0039 RPCs.

// Generated outputs are PRIVATE: the DB stores a Supabase storage path (legacy
// mode) or an R2 object key. Sign legacy paths with the service client; pass an
// absolute http url through. R2-private keys can't be signed from the console
// yet (no R2 creds here, by design) — they resolve to null and the UI shows a
// placeholder; that rides the R2 cutover work (gap report 4.1 note).
const GENERATED_BUCKET = "tryon-results";

export async function resolveOutputRef(ref: string | null): Promise<string | null> {
  if (!ref) return null;
  if (ref.startsWith("http")) return ref;
  const { data } = await getAdminClient()
    .storage.from(GENERATED_BUCKET)
    .createSignedUrl(ref, 600);
  return data?.signedUrl ?? null;
}

export type AiJobRow = {
  id: string;
  user_id: string;
  job_type: string;
  status: string;
  quality: string;
  hd: boolean;
  credits_reserved: number;
  credits_charged: number;
  error_message: string | null;
  source_item_id: string | null;
  style: string | null;
  created_at: string;
  completed_at: string | null;
  user_name: string | null;
  user_username: string | null;
  user_email: string | null;
};

export type AiJobListResult = { total: number; limit: number; offset: number; rows: AiJobRow[] };

export async function listAiJobs(params: {
  search?: string | null;
  type?: string | null;
  status?: string | null;
  limit?: number;
  offset?: number;
}): Promise<AiJobListResult> {
  await requirePermission("view_content");
  const { data, error } = await getAdminClient().rpc("admin_list_ai_jobs", {
    p_search: params.search ?? null,
    p_type: params.type ?? null,
    p_status: params.status ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listAiJobs failed: ${error.message}`);
  return data as AiJobListResult;
}

export type GeneratedImageRow = {
  id: string;
  user_id: string;
  type: string;
  output_url: string | null; // raw stored ref
  view_url: string | null; // resolved/signed for display (added client-side of the RPC)
  status: string;
  report_count: number;
  moderation_reason: string | null;
  source_item_id: string | null;
  job_id: string | null;
  created_at: string;
  user_name: string | null;
  user_username: string | null;
  user_email: string | null;
};

export type GeneratedImageListResult = {
  total: number;
  limit: number;
  offset: number;
  rows: GeneratedImageRow[];
};

export async function listGeneratedImages(params: {
  reported?: boolean | null;
  status?: string | null;
  search?: string | null;
  limit?: number;
  offset?: number;
}): Promise<GeneratedImageListResult> {
  await requirePermission("view_content");
  const { data, error } = await getAdminClient().rpc("admin_list_generated_images", {
    p_reported: params.reported ?? null,
    p_status: params.status ?? null,
    p_search: params.search ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listGeneratedImages failed: ${error.message}`);
  const result = data as GeneratedImageListResult;
  result.rows = await Promise.all(
    result.rows.map(async (r) => ({ ...r, view_url: await resolveOutputRef(r.output_url) }))
  );
  return result;
}
