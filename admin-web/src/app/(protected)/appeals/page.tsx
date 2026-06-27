import Link from "next/link";

import { ModerationActionButton } from "@/components/ModerationActionButton";
import { StatusBadge } from "@/components/StatusBadge";
import { approveAppeal, denyAppeal } from "@/lib/actions/appeals";
import { requirePermission } from "@/lib/auth/require-admin";
import { listAppeals } from "@/lib/dal/reports";
import { fmtDate } from "@/lib/format";

const PAGE_SIZE = 25;
const TABS = [
  { key: "pending", label: "Pending" },
  { key: "reviewing", label: "Reviewing" },
  { key: "approved", label: "Approved" },
  { key: "denied", label: "Denied" },
];

export default async function AppealsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; page?: string }>;
}) {
  await requirePermission("manage_appeals");
  const sp = await searchParams;
  const status = sp.status ?? "pending";
  const page = Math.max(1, parseInt(sp.page ?? "1", 10) || 1);

  const result = await listAppeals({ status, limit: PAGE_SIZE, offset: (page - 1) * PAGE_SIZE });
  const totalPages = Math.max(1, Math.ceil(result.total / PAGE_SIZE));

  return (
    <div className="space-y-4">
      <h1 className="text-lg font-semibold">Appeals</h1>

      <div className="flex gap-1 border-b border-neutral-200">
        {TABS.map((t) => (
          <Link
            key={t.key}
            href={`/appeals?status=${t.key}`}
            className={`px-3 py-2 text-sm ${
              status === t.key
                ? "border-b-2 border-neutral-900 font-medium text-neutral-900"
                : "text-neutral-500 hover:text-neutral-800"
            }`}
          >
            {t.label}
          </Link>
        ))}
      </div>

      {result.rows.length === 0 ? (
        <div className="rounded-lg border border-neutral-200 bg-white p-8 text-center text-sm text-neutral-500">
          No appeals in this tab.
        </div>
      ) : (
        <div className="space-y-3">
          {result.rows.map((a) => (
            <div key={a.id} className="rounded-lg border border-neutral-200 bg-white p-4">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <div className="text-sm">
                    <span className="text-neutral-500">From:</span>{" "}
                    {a.user ? (
                      <Link href={`/users/${a.user.id}`} className="hover:underline">
                        {a.user.email || a.user.name}
                      </Link>
                    ) : (
                      "—"
                    )}
                  </div>
                  <div className="text-xs text-neutral-500">
                    appealing {a.target_type}
                    {a.target_id ? `:${a.target_id.slice(0, 8)}` : ""}
                  </div>
                </div>
                <div className="text-right text-xs text-neutral-500">
                  <StatusBadge status={a.status} />
                  <div className="mt-1">{fmtDate(a.created_at)}</div>
                </div>
              </div>

              <p className="mt-2 text-sm text-neutral-700">{a.message}</p>
              {a.admin_note ? (
                <div className="mt-1 text-xs text-neutral-500">note: {a.admin_note}</div>
              ) : null}

              {a.status === "pending" || a.status === "reviewing" ? (
                <div className="mt-3 flex gap-2">
                  <ModerationActionButton
                    action={approveAppeal}
                    payload={{ appealId: String(a.id) }}
                    label="Approve"
                    title="Approve appeal (restores the target)"
                    defaultReason="Appeal granted."
                  />
                  <ModerationActionButton
                    action={denyAppeal}
                    payload={{ appealId: String(a.id) }}
                    label="Deny"
                    title="Deny appeal"
                    danger
                    defaultReason="Appeal denied — original action upheld."
                  />
                </div>
              ) : null}
            </div>
          ))}
        </div>
      )}

      <div className="flex items-center justify-between text-sm">
        <div className="text-neutral-500">
          Page {page} of {totalPages}
        </div>
        <div className="flex gap-2">
          {page > 1 ? (
            <Link href={`/appeals?status=${status}&page=${page - 1}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Previous
            </Link>
          ) : null}
          {page < totalPages ? (
            <Link href={`/appeals?status=${status}&page=${page + 1}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Next
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
