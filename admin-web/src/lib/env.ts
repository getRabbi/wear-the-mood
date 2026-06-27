// Centralised env access. Reading helpers throw a clear error at first use rather
// than letting an undefined silently become "undefined" in a URL/key.

export function requireEnv(name: string, value: string | undefined): string {
  if (!value || !value.trim()) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

// Browser/login key: prefer the new publishable key, fall back to legacy anon
// (decision (d) — the project is still on legacy keys for now).
export const SUPABASE_BROWSER_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

// NOTE: the server-only SECRET / service_role key is intentionally NOT read here.
// This module is imported by the browser client, so any `process.env.<secret>`
// reference would land (as a dead `undefined` reference) in the client bundle.
// The secret is resolved inside src/lib/supabase/admin.ts (`server-only`) only.
