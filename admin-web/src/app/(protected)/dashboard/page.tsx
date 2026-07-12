import Link from "next/link";

import { StatusBadge } from "@/components/StatusBadge";
import { can } from "@/lib/auth/permissions";
import { requireAdmin } from "@/lib/auth/require-admin";
import {
  getDashboardStats,
  getRecentAudit,
  getRecentUsers,
  type DashboardStats,
} from "@/lib/dal/dashboard";
import { getAiCostDaily } from "@/lib/dal/ops";
import { fmtDate, fmtNum } from "@/lib/format";

const CARDS: Array<{ key: keyof DashboardStats; label: string }> = [
  { key: "total_users", label: "Total users" },
  { key: "new_users_today", label: "New users today" },
  { key: "active_users_7d", label: "Active users 7d" },
  { key: "total_posts", label: "Total posts" },
  { key: "posts_today", label: "Posts today" },
  { key: "pending_reports", label: "Pending reports" },
  { key: "pending_appeals", label: "Pending appeals" },
  { key: "reports_today", label: "Reports today" },
  { key: "active_subscribers", label: "Active subscribers" },
  { key: "banned_users", label: "Banned users" },
  { key: "suspended_users", label: "Suspended users" },
  { key: "shadowbanned_users", label: "Shadowbanned" },
  { key: "active_seed_accounts", label: "Active seed accounts" },
  { key: "credits_issued_today", label: "Credits issued today" },
  { key: "failed_tryons_today", label: "Failed try-ons today" },
];

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: Promise<{ forbidden?: string }>;
}) {
  const admin = await requireAdmin();
  const { forbidden } = await searchParams;
  const stats = await getDashboardStats();
  const recentUsers = await getRecentUsers(8);
  const showAudit = can(admin.role, "view_audit");
  const audit = showAudit ? await getRecentAudit(10) : [];
  const showCosts = can(admin.role, "view_costs");
  const cost = showCosts ? await getAiCostDaily(7) : null;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-lg font-semibold">Dashboard</h1>
        <p className="mt-1 text-sm text-neutral-500">
          Signed in as {admin.email} ({admin.role}).
        </p>
      </div>

      {forbidden === "1" ? (
        <div className="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-800">
          You don&apos;t have permission to access that section.
        </div>
      ) : null}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {CARDS.map((c) => (
          <div key={c.key} className="rounded-lg border border-neutral-200 bg-white p-4">
            <div className="text-xs text-neutral-500">{c.label}</div>
            <div className="mt-2 text-2xl font-semibold">{fmtNum(stats[c.key])}</div>
          </div>
        ))}
        {cost ? (
          <Link href="/costs" className="rounded-lg border border-neutral-200 bg-white p-4 hover:border-neutral-400">
            <div className="text-xs text-neutral-500">AI spend today / 7d (§14)</div>
            <div className="mt-2 text-2xl font-semibold">
              ${Number(cost.today_usd).toFixed(2)}
              <span className="text-sm text-neutral-500"> / ${Number(cost.last7_usd).toFixed(2)}</span>
            </div>
          </Link>
        ) : null}
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <section className="rounded-lg border border-neutral-200 bg-white">
          <div className="flex items-center justify-between border-b border-neutral-200 px-4 py-3">
            <h2 className="text-sm font-semibold">Latest new users</h2>
            <Link href="/users" className="text-xs text-neutral-500 hover:underline">
              View all
            </Link>
          </div>
          <table className="w-full text-sm">
            <tbody>
              {recentUsers.length === 0 ? (
                <tr>
                  <td className="px-4 py-3 text-neutral-500">No users yet.</td>
                </tr>
              ) : (
                recentUsers.map((u) => (
                  <tr key={u.user_id} className="border-t border-neutral-100">
                    <td className="px-4 py-2">
                      <Link href={`/users/${u.user_id}`} className="font-medium hover:underline">
                        {u.display_name || u.username || u.email || u.user_id.slice(0, 8)}
                      </Link>
                      <div className="text-xs text-neutral-500">{u.email}</div>
                    </td>
                    <td className="px-4 py-2">
                      <StatusBadge status={u.account_status} />
                    </td>
                    <td className="px-4 py-2 text-right text-xs text-neutral-500">
                      {fmtDate(u.created_at)}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </section>

        {showAudit ? (
          <section className="rounded-lg border border-neutral-200 bg-white">
            <div className="flex items-center justify-between border-b border-neutral-200 px-4 py-3">
              <h2 className="text-sm font-semibold">Latest admin actions</h2>
            </div>
            <table className="w-full text-sm">
              <tbody>
                {audit.length === 0 ? (
                  <tr>
                    <td className="px-4 py-3 text-neutral-500">No admin actions yet.</td>
                  </tr>
                ) : (
                  audit.map((a) => (
                    <tr key={a.id} className="border-t border-neutral-100">
                      <td className="px-4 py-2">
                        <span className="font-medium">{a.action}</span>
                        <div className="text-xs text-neutral-500">
                          {a.target_type}
                          {a.target_id ? `:${a.target_id.slice(0, 8)}` : ""} · {a.admin_email}
                        </div>
                      </td>
                      <td className="px-4 py-2 text-right text-xs text-neutral-500">
                        {fmtDate(a.created_at)}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </section>
        ) : null}
      </div>
    </div>
  );
}
