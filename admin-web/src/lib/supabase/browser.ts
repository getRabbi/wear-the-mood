"use client";

import { createBrowserClient } from "@supabase/ssr";

import { requireEnv, SUPABASE_BROWSER_KEY, SUPABASE_URL } from "@/lib/env";

// Browser/login client ONLY (§9.1) — uses the publishable/anon key, which is
// safe in the browser. It is used for sign-in and to read the current session;
// it is RLS-bound (the logged-in user's JWT) and can NEVER read admin tables.
export function createSupabaseBrowser() {
  return createBrowserClient(
    requireEnv("NEXT_PUBLIC_SUPABASE_URL", SUPABASE_URL),
    requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY / PUBLISHABLE_KEY", SUPABASE_BROWSER_KEY)
  );
}
