import "server-only";

import { redirect } from "next/navigation";
import { cache } from "react";

import type { Permission, Role } from "@/lib/auth/permissions";
import { can } from "@/lib/auth/permissions";
import { getAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServer } from "@/lib/supabase/server";

export type AdminIdentity = {
  userId: string;
  email: string;
  role: Role;
};

/**
 * The server-side authorization boundary (§4.1, §9.3). Re-run inside EVERY
 * protected layout / Server Action / Route Handler — middleware is only a
 * first-pass redirect and must never be the sole gate.
 *
 * Flow:
 *   1. Resolve the logged-in user from the verified session cookie.
 *   2. If not logged in → redirect to /login.
 *   3. Look the user up in admin_users via the SERVICE-ROLE client (admin_users
 *      is service-role-only by RLS), requiring status='active'.
 *   4. If authenticated but NOT an active admin → bounce to /login?denied=1,
 *      where the client signs the session out and shows "access denied" (§12.1).
 */
export const requireAdmin = cache(async (): Promise<AdminIdentity> => {
  const supabase = await createSupabaseServer();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: admin } = await getAdminClient()
    .from("admin_users")
    .select("role, status, email")
    .eq("user_id", user.id)
    .eq("status", "active")
    .maybeSingle();

  if (!admin) {
    redirect("/login?denied=1");
  }

  return {
    userId: user.id,
    email: (admin.email as string) || user.email || "",
    role: admin.role as Role,
  };
});

/**
 * Like requireAdmin, but also enforces a specific capability. Use at the top of
 * any Server Action / Route Handler that mutates. Renders a hard 403 (via
 * Next's notFound-style redirect) when the role lacks the permission.
 */
export async function requirePermission(permission: Permission): Promise<AdminIdentity> {
  const identity = await requireAdmin();
  if (!can(identity.role, permission)) {
    redirect("/dashboard?forbidden=1");
  }
  return identity;
}
