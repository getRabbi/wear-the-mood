import Link from "next/link";

import { ModerationActionButton } from "@/components/ModerationActionButton";
import { StatusBadge } from "@/components/StatusBadge";
import { deleteComment, hideComment, restoreComment } from "@/lib/actions/moderation";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { listComments } from "@/lib/dal/content";
import { fmtDate, fmtNum } from "@/lib/format";

const PAGE_SIZE = 25;
const STATUSES = ["published", "hidden", "deleted"];

type SP = { q?: string; status?: string; page?: string };

function qs(base: SP, overrides: Partial<SP>): string {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...base, ...overrides })) {
    if (v != null && v !== "") p.set(k, String(v));
  }
  const s = p.toString();
  return s ? `?${s}` : "";
}

export default async function CommentsPage({ searchParams }: { searchParams: Promise<SP> }) {
  const admin = await requirePermission("view_content");
  const sp = await searchParams;
  const page = Math.max(1, parseInt(sp.page ?? "1", 10) || 1);

  const result = await listComments({
    search: sp.q ?? null,
    status: sp.status ?? null,
    limit: PAGE_SIZE,
    offset: (page - 1) * PAGE_SIZE,
  });
  const totalPages = Math.max(1, Math.ceil(result.total / PAGE_SIZE));
  const canHide = can(admin.role, "hide_comment");
  const canDelete = can(admin.role, "delete_comment");

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold">Comments</h1>
        <div className="text-sm text-neutral-500">{fmtNum(result.total)} total</div>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-2">
        <input
          type="text"
          name="q"
          defaultValue={sp.q ?? ""}
          placeholder="Search comment / author / comment id"
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
        <button type="submit" className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800">
          Filter
        </button>
        <Link href="/comments" className="rounded-md border border-neutral-300 px-3 py-2 text-sm hover:bg-neutral-100">
          Reset
        </Link>
      </form>

      <div className="overflow-x-auto rounded-lg border border-neutral-200 bg-white">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-neutral-200 text-left text-xs uppercase tracking-wide text-neutral-500">
              <th className="px-4 py-2">Comment</th>
              <th className="px-4 py-2">Status</th>
              <th className="px-4 py-2 text-right">Reports</th>
              <th className="px-4 py-2 text-right">Created</th>
              <th className="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody>
            {result.rows.length === 0 ? (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-neutral-500">
                  No comments match these filters.
                </td>
              </tr>
            ) : (
              result.rows.map((cm) => (
                <tr key={cm.id} className="border-t border-neutral-100 align-top">
                  <td className="px-4 py-2">
                    <div className="max-w-md">{cm.body}</div>
                    <div className="mt-0.5 text-xs text-neutral-500">
                      by{" "}
                      <Link href={`/users/${cm.user_id}`} className="hover:underline">
                        {cm.author_name || cm.author_username || cm.author_email}
                      </Link>{" "}
                      · on{" "}
                      <Link href={`/posts?q=${cm.post_id}`} className="hover:underline">
                        post
                      </Link>
                    </div>
                    {cm.moderation_reason ? (
                      <div className="mt-0.5 text-xs text-amber-700">reason: {cm.moderation_reason}</div>
                    ) : null}
                  </td>
                  <td className="px-4 py-2">
                    <StatusBadge status={cm.status} />
                  </td>
                  <td className="px-4 py-2 text-right">{fmtNum(cm.report_count)}</td>
                  <td className="px-4 py-2 text-right text-xs text-neutral-500">
                    {fmtDate(cm.created_at)}
                  </td>
                  <td className="px-4 py-2">
                    <div className="flex flex-col items-end gap-1.5">
                      {canHide && cm.status === "published" ? (
                        <ModerationActionButton
                          action={hideComment}
                          payload={{ commentId: cm.id }}
                          label="Hide"
                          title="Hide comment"
                          withPresets
                        />
                      ) : null}
                      {canHide && cm.status !== "published" ? (
                        <ModerationActionButton
                          action={restoreComment}
                          payload={{ commentId: cm.id }}
                          label="Restore"
                          title="Restore comment"
                          defaultReason="Restored after review."
                        />
                      ) : null}
                      {canDelete && cm.status !== "deleted" ? (
                        <ModerationActionButton
                          action={deleteComment}
                          payload={{ commentId: cm.id }}
                          label="Delete"
                          title="Delete comment"
                          danger
                          withPresets
                        />
                      ) : null}
                    </div>
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
            <Link href={`/comments${qs(sp, { page: String(page - 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Previous
            </Link>
          ) : null}
          {page < totalPages ? (
            <Link href={`/comments${qs(sp, { page: String(page + 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Next
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
