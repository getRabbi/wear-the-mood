// GENERATED FILE — do not edit by hand.
// Regenerate: backend> .venv/Scripts/python.exe scripts/gen_admin_db_types.py
// Generated 2026-07-12 21:40 UTC from the dev schema.
//
// Row types for tables the console reads DIRECTLY via .from(). The DAL
// uses Pick<> on these, so a renamed column fails the build (Phase Z).

export type FeatureFlagsRow = {
  key: string;
  enabled: boolean;
  description: string | null;
  rollout: Record<string, unknown> | null;
  updated_at: string;
};

export type TryonModelPresetsRow = {
  id: string;
  kind: string;
  name: string;
  image_url: string | null;
  style: string | null;
  body_type: string | null;
  skin_tone: string | null;
  pose_type: string | null;
  is_active: boolean;
  is_pro_only: boolean;
  sort_order: number;
  created_at: string;
};

export type PlansRow = {
  tier: string;
  kind: string;
  price_usd: number;
  monthly_credits: number;
  hd_allowed: boolean;
  priority: boolean;
  play_product_id: string | null;
  app_product_id: string | null;
  active: boolean;
  updated_at: string;
};

export type AdminAuditLogRow = {
  id: number;
  admin_id: string | null;
  admin_email: string | null;
  action: string;
  target_type: string;
  target_id: string | null;
  reason: string | null;
  metadata: Record<string, unknown>;
  before_data: Record<string, unknown> | null;
  after_data: Record<string, unknown> | null;
  ip_address: string | null;
  user_agent: string | null;
  request_id: string | null;
  created_at: string;
};

export type AdminUsersRow = {
  id: string;
  user_id: string;
  email: string;
  role: string;
  status: string;
  created_by: string | null;
  created_at: string;
  updated_at: string;
};
