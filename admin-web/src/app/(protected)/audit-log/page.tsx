import Link from "next/link";

import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { listAuditLog } from "@/lib/dal/admin";
import { fmtDate } from "@/lib/format";

const PAGE_SIZE = 50;

type SP = {
  action?: string;
  targetType?: string;
  targetId?: string;
  adminEmail?: string;
  from?: string;
  to?: string;
  page?: string;
};

function qs(base: SP, o: Partial<SP>) {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...base, ...o })) if (v) p.set(k, String(v));
  return p.toString();
}

const inp = "rounded-md border border-neutral-300 px-2 py-1.5 text-sm";

export default async function AuditLogPage({ searchParams }: { searchParams: Promise<SP> }) {
  const admin = await requirePermission("view_audit");
  const sp = await searchParams;
  const page = Math.max(1, parseInt(sp.page ?? "1", 10) || 1);

  const { rows, total } = await listAuditLog({
    action: sp.action ?? null,
    targetType: sp.targetType ?? null,
    targetId: sp.targetId ?? null,
    adminEmail: sp.adminEmail ?? null,
    from: sp.from ?? null,
    to: sp.to ?? null,
    limit: PAGE_SIZE,
    offset: (page - 1) * PAGE_SIZE,
  });
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const canExport = can(admin.role, "manage_settings"); // owner/admin

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold">Audit Log</h1>
        {canExport ? (
          <a
            href={`audit-log/export?${qs(sp, {})}`}
            className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm hover:bg-neutral-100"
          >
            Export CSV
          </a>
        ) : null}
      </div>

      <form method="get" className="flex flex-wrap items-end gap-2">
        <input name="action" defaultValue={sp.action ?? ""} placeholder="action" className={inp} />
        <input name="targetType" defaultValue={sp.targetType ?? ""} placeholder="target type" className={inp} />
        <input name="targetId" defaultValue={sp.targetId ?? ""} placeholder="target id" className={inp} />
        <input name="adminEmail" defaultValue={sp.adminEmail ?? ""} placeholder="admin email" className={inp} />
        <input name="from" type="date" defaultValue={sp.from ?? ""} className={inp} />
        <input name="to" type="date" defaultValue={sp.to ?? ""} className={inp} />
        <button type="submit" className="rounded-md bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-800">
          Filter
        </button>
        <Link href="/audit-log" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm hover:bg-neutral-100">
          Reset
        </Link>
      </form>

      <div className="overflow-hidden rounded-lg border border-neutral-200 bg-white">
        {rows.length === 0 ? (
          <div className="p-8 text-center text-sm text-neutral-500">No audit entries.</div>
        ) : (
          <ul className="divide-y divide-neutral-100">
            {rows.map((e) => (
              <li key={e.id} className="px-4 py-2 text-sm">
                <details>
                  <summary className="cursor-pointer list-none">
                    <span className="font-medium">{e.action}</span>{" "}
                    <span className="text-neutral-500">
                      {e.target_type}
                      {e.target_id ? `:${e.target_id.slice(0, 12)}` : ""}
                    </span>
                    <span className="float-right text-xs text-neutral-500">
                      {e.admin_email} · {fmtDate(e.created_at)}
                    </span>
                  </summary>
                  <div className="mt-2 space-y-1 text-xs">
                    {e.reason ? <div className="text-neutral-600">reason: {e.reason}</div> : null}
                    <pre className="overflow-x-auto rounded bg-neutral-50 p-2 text-[11px]">
                      {JSON.stringify(
                        {
                          metadata: e.metadata,
                          before: e.before_data,
                          after: e.after_data,
                          request_id: e.request_id,
                        },
                        null,
                        2
                      )}
                    </pre>
                  </div>
                </details>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="flex items-center justify-between text-sm">
        <div className="text-neutral-500">
          Page {page} of {totalPages} · {total} entries
        </div>
        <div className="flex gap-2">
          {page > 1 ? (
            <Link href={`/audit-log?${qs(sp, { page: String(page - 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Previous
            </Link>
          ) : null}
          {page < totalPages ? (
            <Link href={`/audit-log?${qs(sp, { page: String(page + 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Next
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
