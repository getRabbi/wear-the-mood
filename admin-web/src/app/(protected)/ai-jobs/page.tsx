import Link from "next/link";

import { StatusBadge } from "@/components/StatusBadge";
import { requirePermission } from "@/lib/auth/require-admin";
import { listAiJobs } from "@/lib/dal/ai";
import { fmtDate, fmtNum } from "@/lib/format";

const PAGE_SIZE = 25;
const TYPES = ["enhance_item", "catalog_model", "tryon_own_photo", "tryon_studio_model"];
const STATUSES = ["queued", "processing", "completed", "failed"];

type SP = { q?: string; type?: string; status?: string; page?: string };

function qs(base: SP, overrides: Partial<SP>): string {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...base, ...overrides })) {
    if (v != null && v !== "") p.set(k, String(v));
  }
  const s = p.toString();
  return s ? `?${s}` : "";
}

// AI Studio jobs (0033) — read-only credit-dispute / failure triage view.
// Credits are adjusted from the Credits page; this shows what was reserved
// and charged per job.
export default async function AiJobsPage({ searchParams }: { searchParams: Promise<SP> }) {
  await requirePermission("view_content");
  const sp = await searchParams;
  const page = Math.max(1, parseInt(sp.page ?? "1", 10) || 1);

  const result = await listAiJobs({
    search: sp.q ?? null,
    type: sp.type ?? null,
    status: sp.status ?? null,
    limit: PAGE_SIZE,
    offset: (page - 1) * PAGE_SIZE,
  });
  const totalPages = Math.max(1, Math.ceil(result.total / PAGE_SIZE));

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold">AI Jobs</h1>
        <div className="text-sm text-neutral-500">{fmtNum(result.total)} total</div>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-2">
        <input
          type="text"
          name="q"
          defaultValue={sp.q ?? ""}
          placeholder="Search user / job id"
          className="min-w-64 grow rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
        <select name="type" defaultValue={sp.type ?? ""} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="">All types</option>
          {TYPES.map((t) => (
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
        <Link href="/ai-jobs" className="rounded-md border border-neutral-300 px-3 py-2 text-sm hover:bg-neutral-100">
          Reset
        </Link>
      </form>

      <div className="overflow-x-auto rounded-lg border border-neutral-200 bg-white">
        <table className="w-full text-left text-sm">
          <thead className="text-xs text-neutral-500">
            <tr className="border-b border-neutral-200">
              <th className="px-3 py-2 font-medium">Job</th>
              <th className="px-3 py-2 font-medium">User</th>
              <th className="px-3 py-2 font-medium">Type</th>
              <th className="px-3 py-2 font-medium">Status</th>
              <th className="px-3 py-2 font-medium">Credits (res/chg)</th>
              <th className="px-3 py-2 font-medium">Created</th>
              <th className="px-3 py-2 font-medium">Error</th>
            </tr>
          </thead>
          <tbody>
            {result.rows.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-3 py-8 text-center text-neutral-500">
                  No jobs match these filters.
                </td>
              </tr>
            ) : (
              result.rows.map((j) => (
                <tr key={j.id} className="border-b border-neutral-100 last:border-0">
                  <td className="px-3 py-2 font-mono text-xs">{j.id.slice(0, 8)}…</td>
                  <td className="px-3 py-2">
                    <Link href={`/users/${j.user_id}`} className="hover:underline">
                      {j.user_name || j.user_username || j.user_email}
                    </Link>
                  </td>
                  <td className="px-3 py-2">
                    {j.job_type}
                    {j.hd ? <span className="ml-1 rounded bg-neutral-100 px-1 text-[10px]">HD</span> : null}
                  </td>
                  <td className="px-3 py-2">
                    <StatusBadge status={j.status} />
                  </td>
                  <td className="px-3 py-2">
                    {j.credits_reserved}/{j.credits_charged}
                  </td>
                  <td className="px-3 py-2 text-xs text-neutral-500">{fmtDate(j.created_at)}</td>
                  <td className="max-w-56 truncate px-3 py-2 text-xs text-red-700">
                    {j.error_message || ""}
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
            <Link href={`/ai-jobs${qs(sp, { page: String(page - 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Previous
            </Link>
          ) : null}
          {page < totalPages ? (
            <Link href={`/ai-jobs${qs(sp, { page: String(page + 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Next
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
