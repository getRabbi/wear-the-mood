import "server-only";

import { requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";

export type PostRow = {
  id: string;
  user_id: string;
  caption: string | null;
  image_url: string | null;
  status: string;
  visibility: string;
  is_seed: boolean;
  is_official: boolean;
  featured_at: string | null;
  pinned_until: string | null;
  moderation_reason: string | null;
  like_count: number;
  comment_count: number;
  created_at: string;
  author_name: string | null;
  author_username: string | null;
  author_email: string | null;
  report_count: number;
};

export type PostListResult = { total: number; limit: number; offset: number; rows: PostRow[] };

export type PostListParams = {
  search?: string | null;
  status?: string | null;
  seed?: boolean | null;
  featured?: boolean | null;
  limit?: number;
  offset?: number;
};

export async function listPosts(params: PostListParams): Promise<PostListResult> {
  await requirePermission("view_content");
  const { data, error } = await getAdminClient().rpc("admin_list_posts", {
    p_search: params.search ?? null,
    p_status: params.status ?? null,
    p_seed: params.seed ?? null,
    p_featured: params.featured ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listPosts failed: ${error.message}`);
  return data as PostListResult;
}

export type CommentRow = {
  id: string;
  post_id: string;
  user_id: string;
  body: string;
  status: string;
  moderation_reason: string | null;
  created_at: string;
  author_name: string | null;
  author_username: string | null;
  author_email: string | null;
  report_count: number;
};

export type CommentListResult = {
  total: number;
  limit: number;
  offset: number;
  rows: CommentRow[];
};

export type CommentListParams = {
  search?: string | null;
  status?: string | null;
  limit?: number;
  offset?: number;
};

export async function listComments(params: CommentListParams): Promise<CommentListResult> {
  await requirePermission("view_content");
  const { data, error } = await getAdminClient().rpc("admin_list_comments", {
    p_search: params.search ?? null,
    p_status: params.status ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listComments failed: ${error.message}`);
  return data as CommentListResult;
}
