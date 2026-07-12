import Link from "next/link";

import { CreditAdjustForm } from "@/components/billing/CreditAdjustForm";
import { requirePermission } from "@/lib/auth/require-admin";
import { getCreditLedger } from "@/lib/dal/billing";
import { listCreditTransactions } from "@/lib/dal/ops";
import { listUsers } from "@/lib/dal/users";
import { fmtDate, fmtNum } from "@/lib/format";

const REASONS = ["grant", "spend", "topup", "trial", "admin_adjust", "refund"];

export default async function CreditsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; user?: string; reason?: string; gpage?: string }>;
}) {
  await requirePermission("adjust_credits");
  const sp = await searchParams;

  const matches = sp.q ? (await listUsers({ search: sp.q, limit: 10 })).rows : [];
  const ledger = sp.user ? await getCreditLedger(sp.user) : null;
  const gpage = Math.max(1, parseInt(sp.gpage ?? "1", 10) || 1);
  const global = await listCreditTransactions({
    reason: sp.reason ?? null,
    limit: 25,
    offset: (gpage - 1) * 25,
  });
  const gTotalPages = Math.max(1, Math.ceil(global.total / 25));

  return (
    <div className="space-y-5">
      <h1 className="text-lg font-semibold">Credits</h1>

      <form method="get" className="flex gap-2">
        <input
          name="q"
          defaultValue={sp.q ?? ""}
          placeholder="Find user by email / username / id"
          className="min-w-72 grow rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
        <button type="submit" className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800">
          Search
        </button>
      </form>

      {sp.q ? (
        <div className="rounded-lg border border-neutral-200 bg-white">
          {matches.length === 0 ? (
            <div className="p-4 text-sm text-neutral-500">No users found.</div>
          ) : (
            <ul className="divide-y divide-neutral-100">
              {matches.map((u) => (
                <li key={u.user_id} className="flex items-center justify-between px-4 py-2 text-sm">
                  <span>
                    {u.display_name || u.username || "—"}{" "}
                    <span className="text-neutral-500">{u.email}</span>
                  </span>
                  <Link
                    href={`/credits?user=${u.user_id}`}
                    className="text-xs text-neutral-600 hover:underline"
                  >
                    Select
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </div>
      ) : null}

      {ledger ? (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
            {[
              ["Total", ledger.credits.total],
              ["Plan balance", ledger.credits.balance],
              ["Top-up", ledger.credits.topup_balance],
              ["Free trial used", ledger.credits.daily_free_used],
            ].map(([label, val]) => (
              <div key={label as string} className="rounded-lg border border-neutral-200 bg-white p-3">
                <div className="text-xs text-neutral-500">{label}</div>
                <div className="mt-1 text-xl font-semibold">{fmtNum(val as number)}</div>
              </div>
            ))}
          </div>

          <div className="rounded-lg border border-neutral-200 bg-white p-4">
            <div className="mb-1 text-sm font-semibold">Adjust credits</div>
            <p className="mb-3 text-xs text-neutral-500">
              Positive grants, negative deducts (from plan balance). A reason is required and the
              change is audited. Subscription: {ledger.subscription?.tier ?? "free"} (
              {ledger.subscription?.status ?? "—"}).
            </p>
            <CreditAdjustForm userId={sp.user!} />
          </div>

          <div className="rounded-lg border border-neutral-200 bg-white">
            <div className="border-b border-neutral-200 px-4 py-2 text-sm font-semibold">Ledger</div>
            <table className="w-full text-sm">
              <tbody>
                {ledger.ledger.length === 0 ? (
                  <tr>
                    <td className="px-4 py-3 text-neutral-500">No transactions.</td>
                  </tr>
                ) : (
                  ledger.ledger.map((t) => (
                    <tr key={t.id} className="border-t border-neutral-100">
                      <td className="px-4 py-2">{t.reason}</td>
                      <td className={`px-4 py-2 text-right font-medium ${t.delta < 0 ? "text-red-700" : "text-green-700"}`}>
                        {t.delta > 0 ? "+" : ""}
                        {fmtNum(t.delta)}
                      </td>
                      <td className="px-4 py-2 text-right text-xs text-neutral-500">
                        {fmtDate(t.created_at)}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}

      <div className="rounded-lg border border-neutral-200 bg-white">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-neutral-200 px-4 py-2">
          <span className="text-sm font-semibold">
            Recent activity (all users) · {fmtNum(global.total)}
          </span>
          <form method="get" className="flex items-center gap-2">
            {sp.user ? <input type="hidden" name="user" value={sp.user} /> : null}
            <select name="reason" defaultValue={sp.reason ?? ""} className="rounded-md border border-neutral-300 px-2 py-1 text-xs">
              <option value="">All reasons</option>
              {REASONS.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </select>
            <button type="submit" className="rounded-md border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100">
              Filter
            </button>
          </form>
        </div>
        <table className="w-full text-sm">
          <tbody>
            {global.rows.length === 0 ? (
              <tr>
                <td className="px-4 py-3 text-neutral-500">No transactions.</td>
              </tr>
            ) : (
              global.rows.map((t) => (
                <tr key={t.id} className="border-t border-neutral-100">
                  <td className="px-4 py-2">
                    <Link href={`/credits?user=${t.user_id}`} className="hover:underline">
                      {t.user_name || t.user_username || t.user_email}
                    </Link>
                  </td>
                  <td className="px-4 py-2">{t.reason}</td>
                  <td className={`px-4 py-2 text-right font-medium ${t.delta < 0 ? "text-red-700" : "text-green-700"}`}>
                    {t.delta > 0 ? "+" : ""}
                    {fmtNum(t.delta)}
                  </td>
                  <td className="px-4 py-2 text-right text-xs text-neutral-500">
                    {fmtDate(t.created_at)}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        <div className="flex items-center justify-end gap-2 border-t border-neutral-100 px-4 py-2 text-xs">
          <span className="text-neutral-500">
            Page {gpage} of {gTotalPages}
          </span>
          {gpage > 1 ? (
            <Link href={`/credits?${new URLSearchParams({ ...(sp.user ? { user: sp.user } : {}), ...(sp.reason ? { reason: sp.reason } : {}), gpage: String(gpage - 1) })}`} className="rounded-md border border-neutral-300 px-2 py-1 hover:bg-neutral-100">
              Previous
            </Link>
          ) : null}
          {gpage < gTotalPages ? (
            <Link href={`/credits?${new URLSearchParams({ ...(sp.user ? { user: sp.user } : {}), ...(sp.reason ? { reason: sp.reason } : {}), gpage: String(gpage + 1) })}`} className="rounded-md border border-neutral-300 px-2 py-1 hover:bg-neutral-100">
              Next
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
