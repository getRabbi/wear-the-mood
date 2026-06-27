import "server-only";

import { createServerClient, type SetAllCookies } from "@supabase/ssr";
import { cookies } from "next/headers";

import { requireEnv, SUPABASE_BROWSER_KEY, SUPABASE_URL } from "@/lib/env";

// SSR client bound to the request cookies (§9.1). Uses the publishable/anon key
// + the logged-in admin's session cookie, so it reads as THAT user (RLS applies).
// Use it to identify who is logged in; use the admin client (service-role) to
// actually read admin/moderation data.
export async function createSupabaseServer() {
  const cookieStore = await cookies();
  return createServerClient(
    requireEnv("NEXT_PUBLIC_SUPABASE_URL", SUPABASE_URL),
    requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY / PUBLISHABLE_KEY", SUPABASE_BROWSER_KEY),
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet: Parameters<SetAllCookies>[0]) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // Called from a Server Component render where cookies are read-only —
            // the middleware refreshes the session, so this is safe to ignore.
          }
        },
      },
    }
  );
}
