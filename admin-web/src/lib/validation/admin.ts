import { z } from "zod";

import { ROLES } from "@/lib/auth/permissions";

export const upsertAdminSchema = z.object({
  email: z.string().trim().email("A valid email is required."),
  role: z.enum(ROLES),
});

export const CONFIG_KEYS = [
  "seed_accounts_enabled",
  "public_official_badges_enabled",
  "maintenance_mode",
] as const;

export const setConfigSchema = z.object({
  key: z.enum(CONFIG_KEYS),
  value: z.enum(["true", "false"]),
});

// Mirrors the domain admin_set_admin_status enforces server-side (0030).
export const adminStatusSchema = z.object({
  userId: z.string().uuid(),
  status: z.enum(["active", "disabled", "revoked"]),
});
