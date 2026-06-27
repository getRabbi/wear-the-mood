import Link from "next/link";

import { StatusBadge } from "@/components/StatusBadge";
import { requirePermission } from "@/lib/auth/require-admin";
import { listUsers } from "@/lib/dal/users";
import { fmtDate, fmtNum } from "@/lib/format";

const PAGE_SIZE = 25;
const STATUSES = ["active", "suspended", "banned", "shadowbanned", "deleted", "archived"];
const TIERS = ["free", "pro", "pro_max"];

type SP = {
  q?: string;
  status?: string;
  tier?: string;
  seed?: string;
  sort?: string;
  page?: string;
};

function qs(base: SP, overrides: Partial<SP>): string {
  const merged = { ...base, ...overrides };
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(merged)) {
    if (v != null && v !== "") p.set(k, String(v));
  }
  const s = p.toString();
  return s ? `?${s}` : "";
}

export default async function UsersPage({ searchParams }: { searchParams: Promise<SP> }) {
  await requirePermission("view_users");
  const sp = await searchParams;
  const page = Math.max(1, parseInt(sp.page ?? "1", 10) || 1);
  const seed = sp.seed === "true" ? true : sp.seed === "false" ? false : null;

  const result = await listUsers({
    search: sp.q ?? null,
    status: sp.status ?? null,
    seed,
    tier: sp.tier ?? null,
    sort: sp.sort ?? "joined_desc",
    limit: PAGE_SIZE,
    offset: (page - 1) * PAGE_SIZE,
  });

  const totalPages = Math.max(1, Math.ceil(result.total / PAGE_SIZE));

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold">Users</h1>
        <div className="text-sm text-neutral-500">{fmtNum(result.total)} total</div>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-2">
        <input
          type="text"
          name="q"
          defaultValue={sp.q ?? ""}
          placeholder="Search email / username / name / id"
          className="min-w-64 grow rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
        <select name="status" defaultValue={sp.status ?? ""} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="">All statuses</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
        <select name="tier" defaultValue={sp.tier ?? ""} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="">All tiers</option>
          {TIERS.map((t) => (
            <option key={t} value={t}>
              {t}
            </option>
          ))}
        </select>
        <select name="seed" defaultValue={sp.seed ?? ""} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="">All accounts</option>
          <option value="true">Seed only</option>
          <option value="false">Real only</option>
        </select>
        <select name="sort" defaultValue={sp.sort ?? "joined_desc"} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="joined_desc">Newest</option>
          <option value="joined_asc">Oldest</option>
          <option value="report_count">Most reported</option>
        </select>
        <button type="submit" className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800">
          Filter
        </button>
        <Link href="/users" className="rounded-md border border-neutral-300 px-3 py-2 text-sm hover:bg-neutral-100">
          Reset
        </Link>
      </form>

      <div className="overflow-x-auto rounded-lg border border-neutral-200 bg-white">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-neutral-200 text-left text-xs uppercase tracking-wide text-neutral-500">
              <th className="px-4 py-2">User</th>
              <th className="px-4 py-2">Status</th>
              <th className="px-4 py-2">Tier</th>
              <th className="px-4 py-2 text-right">Credits</th>
              <th className="px-4 py-2 text-right">Posts</th>
              <th className="px-4 py-2 text-right">Reports</th>
              <th className="px-4 py-2 text-right">Joined</th>
              <th className="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody>
            {result.rows.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-4 py-8 text-center text-neutral-500">
                  No users match these filters.
                </td>
              </tr>
            ) : (
              result.rows.map((u) => (
                <tr key={u.user_id} className="border-t border-neutral-100 hover:bg-neutral-50">
                  <td className="px-4 py-2">
                    <Link href={`/users/${u.user_id}`} className="font-medium hover:underline">
                      {u.display_name || u.username || "—"}
                    </Link>
                    <div className="text-xs text-neutral-500">{u.email}</div>
                    {u.is_seed ? (
                      <span className="mt-0.5 inline-block rounded bg-blue-50 px-1.5 py-0.5 text-[10px] text-blue-700">
                        {u.public_label || "Seed"}
                      </span>
                    ) : null}
                  </td>
                  <td className="px-4 py-2">
                    <StatusBadge status={u.account_status} />
                  </td>
                  <td className="px-4 py-2">{u.tier}</td>
                  <td className="px-4 py-2 text-right">{fmtNum(u.credits_total)}</td>
                  <td className="px-4 py-2 text-right">{fmtNum(u.post_count)}</td>
                  <td className="px-4 py-2 text-right">{fmtNum(u.report_count)}</td>
                  <td className="px-4 py-2 text-right text-xs text-neutral-500">
                    {fmtDate(u.created_at)}
                  </td>
                  <td className="px-4 py-2 text-right">
                    <Link href={`/users/${u.user_id}`} className="text-xs text-neutral-600 hover:underline">
                      View
                    </Link>
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
            <Link
              href={`/users${qs(sp, { page: String(page - 1) })}`}
              className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100"
            >
              Previous
            </Link>
          ) : null}
          {page < totalPages ? (
            <Link
              href={`/users${qs(sp, { page: String(page + 1) })}`}
              className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100"
            >
              Next
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
