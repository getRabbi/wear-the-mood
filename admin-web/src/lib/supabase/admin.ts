import "server-only";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import { requireEnv, SUPABASE_URL } from "@/lib/env";

// Server-only secret: prefer the new secret key, fall back to legacy service_role
// (decision (d)). Resolved HERE (not in the shared env module) so the secret env
// names never reach a client bundle.
const SUPABASE_SECRET_KEY =
  process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

// SERVER-ONLY admin client (§9.2). Holds the Supabase SECRET / service_role key,
// which bypasses RLS — so it is the ONLY way the console reads admin/moderation
// tables (they are service-role-only by RLS, migration 0024). The `server-only`
// import makes the build FAIL if this module is ever pulled into a client bundle,
// so the secret can never leak to the browser.
//
// Built lazily (not at module load) so importing it doesn't throw during
// `next build` when env isn't present; it throws only when actually used.
let _client: SupabaseClient | null = null;

export function getAdminClient(): SupabaseClient {
  if (_client) return _client;
  _client = createClient(
    requireEnv("NEXT_PUBLIC_SUPABASE_URL", SUPABASE_URL),
    requireEnv("SUPABASE_SECRET_KEY / SERVICE_ROLE_KEY", SUPABASE_SECRET_KEY),
    { auth: { persistSession: false, autoRefreshToken: false } }
  );
  return _client;
}
