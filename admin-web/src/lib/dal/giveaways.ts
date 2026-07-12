import "server-only";

import { requireAdmin, requirePermission } from "@/lib/auth/require-admin";
import { getAdminClient } from "@/lib/supabase/admin";

// Shapes mirror the jsonb returned by the 0038 RPCs. Every DAL function
// re-verifies admin auth + permission (§9.3), same as users/content.

export type GiveawayRow = {
  id: string;
  owner_id: string;
  title: string;
  description: string | null;
  image_url: string | null;
  size: string | null;
  category: string | null;
  condition: string | null;
  area_label: string | null;
  status: string;
  hidden_at: string | null;
  deleted_at: string | null;
  moderation_reason: string | null;
  is_seed: boolean;
  moderation_state: "live" | "hidden" | "deleted";
  created_at: string;
  owner_name: string | null;
  owner_username: string | null;
  owner_email: string | null;
  claim_count: number;
  report_count: number;
};

export type GiveawayListResult = {
  total: number;
  limit: number;
  offset: number;
  rows: GiveawayRow[];
};

export async function listGiveaways(params: {
  search?: string | null;
  status?: string | null;
  state?: string | null;
  limit?: number;
  offset?: number;
}): Promise<GiveawayListResult> {
  await requirePermission("view_content");
  const { data, error } = await getAdminClient().rpc("admin_list_giveaways", {
    p_search: params.search ?? null,
    p_status: params.status ?? null,
    p_state: params.state ?? null,
    p_limit: params.limit ?? 25,
    p_offset: params.offset ?? 0,
  });
  if (error) throw new Error(`listGiveaways failed: ${error.message}`);
  return data as GiveawayListResult;
}

export type GiveawayDetail = {
  giveaway: {
    id: string;
    owner_id: string;
    title: string;
    description: string | null;
    images: string[];
    size: string | null;
    category: string | null;
    condition: string | null;
    area_label: string | null;
    status: string;
    hidden_at: string | null;
    deleted_at: string | null;
    moderation_reason: string | null;
    is_seed: boolean;
    created_at: string;
    owner_name: string | null;
    owner_email: string | null;
    owner_status: string;
  };
  claims: Array<{
    id: string;
    claimer_id: string;
    claimer_name: string | null;
    message: string | null;
    status: string;
    created_at: string;
  }>;
  chats: Array<{
    id: string;
    status: string;
    report_flag: boolean;
    requester_id: string;
    requester_name: string | null;
    approved_at: string;
    expires_at: string;
  }>;
  reports: Array<{ id: string; reason: string | null; status: string; created_at: string }>;
};

export async function getGiveawayDetail(giveawayId: string): Promise<GiveawayDetail | null> {
  await requirePermission("view_content");
  const { data, error } = await getAdminClient().rpc("admin_giveaway_detail", {
    p_giveaway_id: giveawayId,
  });
  if (error) {
    if (error.message?.includes("GIVEAWAY_NOT_FOUND")) return null;
    throw new Error(`getGiveawayDetail failed: ${error.message}`);
  }
  return data as GiveawayDetail;
}

export type ChatTranscript = {
  chat: {
    id: string;
    giveaway_id: string;
    status: string;
    report_flag: boolean;
    report_cleared_at: string | null;
    pickup_plan: Record<string, unknown>;
    approved_at: string;
    expires_at: string;
    created_at: string;
    giveaway_title: string;
  };
  owner: { id: string; name: string | null; email: string | null; account_status: string };
  requester: { id: string; name: string | null; email: string | null; account_status: string };
  messages: Array<{
    id: string;
    sender_id: string;
    body: string | null;
    body_deleted: boolean;
    created_at: string;
  }>;
  reports: Array<{
    id: string;
    reason: string | null;
    status: string;
    reporter_id: string;
    created_at: string;
  }>;
};

/** Reads a private pickup-chat transcript. The RPC itself writes an audit row
 *  for every read (§10 — transcript access always leaves a trace), which is why
 *  this passes the admin identity through. */
export async function getChatTranscript(chatId: string): Promise<ChatTranscript | null> {
  const admin = await requireAdmin();
  await requirePermission("review_chats");
  const { data, error } = await getAdminClient().rpc("admin_get_pickup_chat_transcript", {
    p_admin_id: admin.userId,
    p_admin_email: admin.email,
    p_chat_id: chatId,
  });
  if (error) {
    if (error.message?.includes("CHAT_NOT_FOUND")) return null;
    throw new Error(`getChatTranscript failed: ${error.message}`);
  }
  return data as ChatTranscript;
}
