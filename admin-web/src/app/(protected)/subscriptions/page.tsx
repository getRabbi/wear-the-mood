import Link from "next/link";

import { StatusBadge } from "@/components/StatusBadge";
import { requirePermission } from "@/lib/auth/require-admin";
import { listSubscriptions } from "@/lib/dal/billing";
import { fmtDate, fmtNum } from "@/lib/format";

const PAGE_SIZE = 25;
const TIERS = ["pro", "pro_max", "free"];
const STATUSES = ["active", "canceled", "grace", "expired"];

type SP = { q?: string; tier?: string; status?: string; page?: string };

function qs(base: SP, o: Partial<SP>) {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...base, ...o })) if (v) p.set(k, String(v));
  const s = p.toString();
  return s ? `?${s}` : "";
}

export default async function SubscriptionsPage({ searchParams }: { searchParams: Promise<SP> }) {
  await requirePermission("view_subscriptions");
  const sp = await searchParams;
  const page = Math.max(1, parseInt(sp.page ?? "1", 10) || 1);

  const result = await listSubscriptions({
    tier: sp.tier ?? null,
    status: sp.status ?? null,
    search: sp.q ?? null,
    limit: PAGE_SIZE,
    offset: (page - 1) * PAGE_SIZE,
  });
  const totalPages = Math.max(1, Math.ceil(result.total / PAGE_SIZE));

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold">Subscriptions</h1>
        <div className="text-sm text-neutral-500">{fmtNum(result.total)} total</div>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-2">
        <input name="q" defaultValue={sp.q ?? ""} placeholder="Search user" className="min-w-56 grow rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <select name="tier" defaultValue={sp.tier ?? ""} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="">All tiers</option>
          {TIERS.map((t) => (
            <option key={t} value={t}>
              {t}
            </option>
          ))}
        </select>
        <select name="status" defaultValue={sp.status ?? ""} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="">All statuses</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
        <button type="submit" className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800">
          Filter
        </button>
        <Link href="/subscriptions" className="rounded-md border border-neutral-300 px-3 py-2 text-sm hover:bg-neutral-100">
          Reset
        </Link>
      </form>

      <div className="overflow-x-auto rounded-lg border border-neutral-200 bg-white">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-neutral-200 text-left text-xs uppercase text-neutral-500">
              <th className="px-4 py-2">User</th>
              <th className="px-4 py-2">Tier</th>
              <th className="px-4 py-2">Status</th>
              <th className="px-4 py-2">Store</th>
              <th className="px-4 py-2 text-right">Period end</th>
            </tr>
          </thead>
          <tbody>
            {result.rows.length === 0 ? (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-neutral-500">
                  No subscriptions.
                </td>
              </tr>
            ) : (
              result.rows.map((s) => (
                <tr key={s.user_id} className="border-t border-neutral-100">
                  <td className="px-4 py-2">
                    <Link href={`/users/${s.user_id}`} className="font-medium hover:underline">
                      {s.display_name || s.username || "—"}
                    </Link>
                    <div className="text-xs text-neutral-500">{s.email}</div>
                  </td>
                  <td className="px-4 py-2 font-medium">{s.tier}</td>
                  <td className="px-4 py-2">
                    <StatusBadge status={s.status} />
                  </td>
                  <td className="px-4 py-2 text-xs text-neutral-500">{s.store || "—"}</td>
                  <td className="px-4 py-2 text-right text-xs text-neutral-500">
                    {fmtDate(s.current_period_end)}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <div className="flex items-center justify-between text-sm">
        <div className="text-neutral-500">
          Page {page} of {totalPages}
        </div>
        <div className="flex gap-2">
          {page > 1 ? (
            <Link href={`/subscriptions${qs(sp, { page: String(page - 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Previous
            </Link>
          ) : null}
          {page < totalPages ? (
            <Link href={`/subscriptions${qs(sp, { page: String(page + 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Next
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
