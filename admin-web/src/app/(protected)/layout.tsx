import { AppShell } from "@/components/AppShell";
import { requireAdmin } from "@/lib/auth/require-admin";
import { getModerationBadges } from "@/lib/dal/reports";

// Every route under this group is admin-gated. requireAdmin() is the real
// security boundary (re-verified here on every request), independent of the
// first-pass middleware redirect.
export default async function ProtectedLayout({ children }: { children: React.ReactNode }) {
  const admin = await requireAdmin();
  const badges = await getModerationBadges();
  return (
    <AppShell admin={admin} badges={badges}>
      {children}
    </AppShell>
  );
}
