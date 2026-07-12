import Link from "next/link";

import { ModerationActionButton } from "@/components/ModerationActionButton";
import { StatusBadge } from "@/components/StatusBadge";
import { removeGeneratedImage, restoreGeneratedImage } from "@/lib/actions/ai";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { listGeneratedImages } from "@/lib/dal/ai";
import { fmtDate, fmtNum } from "@/lib/format";

const PAGE_SIZE = 25;

type SP = { q?: string; status?: string; reported?: string; page?: string };

function qs(base: SP, overrides: Partial<SP>): string {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...base, ...overrides })) {
    if (v != null && v !== "") p.set(k, String(v));
  }
  const s = p.toString();
  return s ? `?${s}` : "";
}

// AI Studio outputs (0033) — reported ones first. Removed outputs stay listed
// (soft delete) so takedowns are reviewable and reversible.
export default async function AiImagesPage({ searchParams }: { searchParams: Promise<SP> }) {
  const admin = await requirePermission("view_content");
  const sp = await searchParams;
  const page = Math.max(1, parseInt(sp.page ?? "1", 10) || 1);
  const reported = sp.reported === "true" ? true : null;

  const result = await listGeneratedImages({
    search: sp.q ?? null,
    status: sp.status ?? null,
    reported,
    limit: PAGE_SIZE,
    offset: (page - 1) * PAGE_SIZE,
  });
  const totalPages = Math.max(1, Math.ceil(result.total / PAGE_SIZE));
  const canModerate = can(admin.role, "moderate_ai_images");

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold">AI Images</h1>
        <div className="text-sm text-neutral-500">{fmtNum(result.total)} total</div>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-2">
        <input
          type="text"
          name="q"
          defaultValue={sp.q ?? ""}
          placeholder="Search owner / image id"
          className="min-w-64 grow rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
        <select name="status" defaultValue={sp.status ?? ""} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="">All statuses</option>
          <option value="active">active</option>
          <option value="removed">removed</option>
        </select>
        <select name="reported" defaultValue={sp.reported ?? ""} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="">All images</option>
          <option value="true">Reported only</option>
        </select>
        <button type="submit" className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800">
          Filter
        </button>
        <Link href="/ai-images" className="rounded-md border border-neutral-300 px-3 py-2 text-sm hover:bg-neutral-100">
          Reset
        </Link>
      </form>

      <div className="space-y-3">
        {result.rows.length === 0 ? (
          <div className="rounded-lg border border-neutral-200 bg-white p-8 text-center text-sm text-neutral-500">
            No AI images match these filters.
          </div>
        ) : (
          result.rows.map((img) => (
            <div key={img.id} className="flex gap-4 rounded-lg border border-neutral-200 bg-white p-3">
              {img.view_url ? (
                <img src={img.view_url} alt="" className="h-20 w-20 shrink-0 rounded-md object-cover" />
              ) : (
                <div className="flex h-20 w-20 shrink-0 items-center justify-center rounded-md bg-neutral-100 text-center text-[10px] text-neutral-400">
                  {img.output_url ? "unsigned ref" : "no image"}
                </div>
              )}

              <div className="min-w-0 grow">
                <div className="flex items-center gap-2">
                  <StatusBadge status={img.status} />
                  <span className="rounded bg-neutral-100 px-1.5 py-0.5 text-[10px] text-neutral-600">
                    {img.type}
                  </span>
                  {img.report_count > 0 ? (
                    <span className="rounded bg-red-50 px-1.5 py-0.5 text-[10px] text-red-700">
                      {img.report_count} reports
                    </span>
                  ) : null}
                </div>
                <div className="mt-1 text-xs text-neutral-500">
                  by{" "}
                  <Link href={`/users/${img.user_id}`} className="hover:underline">
                    {img.user_name || img.user_username || img.user_email}
                  </Link>{" "}
                  · {fmtDate(img.created_at)}
                </div>
                {img.moderation_reason ? (
                  <div className="mt-0.5 text-xs text-amber-700">reason: {img.moderation_reason}</div>
                ) : null}
              </div>

              <div className="flex shrink-0 flex-col items-end gap-1.5">
                {canModerate && img.status === "active" ? (
                  <ModerationActionButton
                    action={removeGeneratedImage}
                    payload={{ imageId: img.id }}
                    label="Remove"
                    title="Remove AI output (soft)"
                    danger
                    withPresets
                  />
                ) : null}
                {canModerate && img.status === "removed" ? (
                  <ModerationActionButton
                    action={restoreGeneratedImage}
                    payload={{ imageId: img.id }}
                    label="Restore"
                    title="Restore AI output"
                    defaultReason="Restored after review."
                  />
                ) : null}
              </div>
            </div>
          ))
        )}
      </div>

      <div className="flex items-center justify-between text-sm">
        <div className="text-neutral-500">
          Page {page} of {totalPages}
        </div>
        <div className="flex gap-2">
          {page > 1 ? (
            <Link href={`/ai-images${qs(sp, { page: String(page - 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Previous
            </Link>
          ) : null}
          {page < totalPages ? (
            <Link href={`/ai-images${qs(sp, { page: String(page + 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Next
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
