import { createServerClient, type SetAllCookies } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { SUPABASE_BROWSER_KEY, SUPABASE_URL } from "@/lib/env";

// First-pass session refresh + redirect (§4.1). This keeps the auth cookie fresh
// and bounces obviously-unauthenticated requests to /login. It is NOT the
// security boundary — requireAdmin() re-verifies identity + role on every
// protected render/action. If env is missing we let the request through so the
// page-level guard handles it (never hard-crash the whole console in middleware).
export async function updateSession(request: NextRequest): Promise<NextResponse> {
  let response = NextResponse.next({ request });

  if (!SUPABASE_URL || !SUPABASE_BROWSER_KEY) {
    return response;
  }

  const supabase = createServerClient(SUPABASE_URL, SUPABASE_BROWSER_KEY, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet: Parameters<SetAllCookies>[0]) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options)
        );
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  // `pathname` here is already stripped of basePath by Next. Public routes that
  // don't require a session: the login page itself.
  const isLogin = request.nextUrl.pathname === "/login";
  if (!user && !isLogin) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "";
    return NextResponse.redirect(url);
  }

  return response;
}
