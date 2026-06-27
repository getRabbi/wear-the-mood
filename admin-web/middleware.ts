import { NextResponse, type NextRequest } from "next/server";

import { updateSession } from "@/lib/supabase/middleware";

// Optional IP allowlist (defense-in-depth, NOT the boundary). Empty → no
// restriction. Behind Caddy the client IP is the first X-Forwarded-For hop.
const IP_ALLOWLIST = (process.env.ADMIN_IP_ALLOWLIST ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

export async function middleware(request: NextRequest) {
  if (IP_ALLOWLIST.length > 0) {
    const ip = (
      request.headers.get("x-forwarded-for")?.split(",")[0] ??
      request.headers.get("x-real-ip") ??
      ""
    ).trim();
    if (!IP_ALLOWLIST.includes(ip)) {
      return new NextResponse("Forbidden", { status: 403 });
    }
  }

  const response = await updateSession(request);
  // Defense-in-depth noindex on every admin response.
  response.headers.set("X-Robots-Tag", "noindex, nofollow");
  return response;
}

export const config = {
  // Run on everything except static assets + image optimizer + favicon.
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
