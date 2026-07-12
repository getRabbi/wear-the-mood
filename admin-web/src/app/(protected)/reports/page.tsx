import Link from "next/link";

import { ModerationActionButton } from "@/components/ModerationActionButton";
import { StatusBadge } from "@/components/StatusBadge";
import { removeGeneratedFromReport } from "@/lib/actions/ai";
import { hideGiveawayFromReport } from "@/lib/actions/giveaways";
import { resolveOutputRef } from "@/lib/dal/ai";
import {
  addReportNote,
  addReportStrike,
  banReportedUser,
  bulkDismissReports,
  dismissReport,
  hideReportTarget,
  markReportReviewing,
} from "@/lib/actions/reports";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { listReports, type ReportRow } from "@/lib/dal/reports";
import { fmtDate } from "@/lib/format";

const PAGE_SIZE = 25;
const TABS: { key: string; label: string }[] = [
  { key: "pending", label: "Pending" },
  { key: "reviewing", label: "Reviewing" },
  { key: "actioned", label: "Actioned" },
  { key: "dismissed", label: "Dismissed" },
];

function preview(r: ReportRow) {
  const p = r.target_preview ?? {};
  if (r.subject_type === "post") {
    return (
      <div className="flex gap-3">
        {typeof p.image_url === "string" ? (
          <img src={p.image_url} alt="" className="h-16 w-16 rounded object-cover" />
        ) : null}
        <div className="min-w-0">
          <div className="text-xs text-neutral-500">post</div>
          <div className="truncate text-sm">{(p.caption as string) || "(no caption)"}</div>
          <StatusBadge status={(p.status as string) ?? "unknown"} />
        </div>
      </div>
    );
  }
  if (r.subject_type === "comment") {
    return (
      <div>
        <div className="text-xs text-neutral-500">comment</div>
        <div className="text-sm">{(p.body as string) || "—"}</div>
        <StatusBadge status={(p.status as string) ?? "unknown"} />
      </div>
    );
  }
  if (r.subject_type === "giveaway") {
    const state = p.deleted_at ? "deleted" : p.hidden_at ? "hidden" : (p.status as string);
    return (
      <div className="flex gap-3">
        {typeof p.image_url === "string" ? (
          <img src={p.image_url} alt="" className="h-16 w-16 rounded object-cover" />
        ) : null}
        <div className="min-w-0">
          <div className="text-xs text-neutral-500">giveaway</div>
          <Link
            href={`/giveaways/${r.subject_id}`}
            className="block truncate text-sm hover:underline"
          >
            {(p.title as string) || "(untitled listing)"}
          </Link>
          <StatusBadge status={state ?? "unknown"} />
        </div>
      </div>
    );
  }
  if (r.subject_type === "giveaway_chat") {
    const owner = p.owner as { id?: string; name?: string } | undefined;
    const requester = p.requester as { id?: string; name?: string } | undefined;
    return (
      <div>
        <div className="text-xs text-neutral-500">pickup chat</div>
        <div className="truncate text-sm">
          {(p.giveaway_title as string) || "(giveaway)"} — {owner?.name || "owner"} ↔{" "}
          {requester?.name || "requester"}
        </div>
        <div className="mt-0.5 flex items-center gap-2">
          <StatusBadge status={(p.chat_status as string) ?? "unknown"} />
          {p.report_flag ? (
            <span className="rounded bg-red-50 px-1.5 py-0.5 text-[10px] text-red-700">
              transcript frozen
            </span>
          ) : null}
        </div>
      </div>
    );
  }
  if (r.subject_type === "generated_image") {
    return (
      <div className="flex gap-3">
        {typeof p.view_url === "string" ? (
          <img src={p.view_url} alt="" className="h-16 w-16 rounded object-cover" />
        ) : null}
        <div className="min-w-0">
          <div className="text-xs text-neutral-500">AI output ({(p.type as string) || "?"})</div>
          <div className="text-sm">self-reported · {(p.report_count as number) ?? 0} reports</div>
          <StatusBadge status={(p.status as string) ?? "unknown"} />
        </div>
      </div>
    );
  }
  if (r.subject_type === "user") {
    return (
      <div>
        <div className="text-xs text-neutral-500">user</div>
        <div className="text-sm">{(p.display_name as string) || (p.username as string) || "—"}</div>
        <StatusBadge status={(p.account_status as string) ?? "unknown"} />
      </div>
    );
  }
  // Unknown subject type — render it visibly instead of guessing (drift guard).
  return (
    <div>
      <div className="text-xs text-amber-700">unhandled report type: {r.subject_type}</div>
      <div className="text-sm text-neutral-500">target {r.subject_id}</div>
    </div>
  );
}

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; page?: string }>;
}) {
  const admin = await requirePermission("manage_reports");
  const sp = await searchParams;
  const status = sp.status ?? "pending";
  const page = Math.max(1, parseInt(sp.page ?? "1", 10) || 1);

  const result = await listReports({
    status,
    limit: PAGE_SIZE,
    offset: (page - 1) * PAGE_SIZE,
  });
  // Generated outputs are private refs — sign them for the preview (0039).
  for (const r of result.rows) {
    if (r.subject_type === "generated_image" && r.target_preview) {
      r.target_preview.view_url = await resolveOutputRef(
        (r.target_preview.output_url as string | null) ?? null
      );
    }
  }
  const totalPages = Math.max(1, Math.ceil(result.total / PAGE_SIZE));
  const canHidePost = can(admin.role, "hide_post");
  const canHideComment = can(admin.role, "hide_comment");
  const canBan = can(admin.role, "ban_user");
  const canModerateGiveaways = can(admin.role, "moderate_giveaways");
  const canReviewChats = can(admin.role, "review_chats");
  const canModerateAiImages = can(admin.role, "moderate_ai_images");

  return (
    <div className="space-y-4">
      <h1 className="text-lg font-semibold">Reports</h1>

      <div className="flex gap-1 border-b border-neutral-200">
        {TABS.map((t) => (
          <Link
            key={t.key}
            href={`/reports?status=${t.key}`}
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
          No reports in this tab.
        </div>
      ) : (
        <form action={bulkDismissReports} className="space-y-3">
          {result.rows.map((r) => {
            const canHide =
              (r.subject_type === "post" && canHidePost) ||
              (r.subject_type === "comment" && canHideComment);
            return (
              <div key={r.id} className="rounded-lg border border-neutral-200 bg-white p-4">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div className="flex min-w-0 grow gap-3">
                    <input
                      type="checkbox"
                      name="ids"
                      value={r.id}
                      className="mt-1 h-4 w-4 shrink-0"
                      aria-label="Select report"
                    />
                    <div className="min-w-0 grow">{preview(r)}</div>
                  </div>
                  <div className="text-right text-xs text-neutral-500">
                    <StatusBadge status={r.status} />
                    <div className="mt-1">{fmtDate(r.created_at)}</div>
                  </div>
                </div>

                <div className="mt-3 grid grid-cols-1 gap-1 text-sm sm:grid-cols-2">
                  <div>
                    <span className="text-neutral-500">Reason:</span> {r.reason || "—"}
                    {r.details ? <div className="text-neutral-600">{r.details}</div> : null}
                  </div>
                  <div className="text-neutral-600">
                    <div>Reporter: {r.reporter?.email || r.reporter?.name || "—"}</div>
                    <div>
                      Reported user:{" "}
                      {r.reported_user ? (
                        <Link href={`/users/${r.reported_user.id}`} className="hover:underline">
                          {r.reported_user.email || r.reported_user.name}
                        </Link>
                      ) : (
                        "—"
                      )}
                    </div>
                  </div>
                </div>

                {r.admin_note ? (
                  <div className="mt-2 text-xs text-neutral-500">note: {r.admin_note}</div>
                ) : null}

                <div className="mt-3 flex flex-wrap gap-2">
                  <ModerationActionButton
                    action={markReportReviewing}
                    payload={{ reportId: r.id }}
                    label="Reviewing"
                    title="Mark report reviewing"
                    defaultReason="Under review."
                  />
                  {canHide ? (
                    <ModerationActionButton
                      action={hideReportTarget}
                      payload={{
                        reportId: r.id,
                        subjectType: r.subject_type,
                        subjectId: r.subject_id,
                      }}
                      label="Hide target"
                      title="Hide reported content + action report"
                      withPresets
                    />
                  ) : null}
                  {r.subject_type === "giveaway" && canModerateGiveaways ? (
                    <ModerationActionButton
                      action={hideGiveawayFromReport}
                      payload={{ reportId: r.id, giveawayId: r.subject_id }}
                      label="Hide listing"
                      title="Hide reported giveaway + action report"
                      withPresets
                    />
                  ) : null}
                  {r.subject_type === "generated_image" && canModerateAiImages ? (
                    <ModerationActionButton
                      action={removeGeneratedFromReport}
                      payload={{ reportId: r.id, imageId: r.subject_id }}
                      label="Remove output"
                      title="Remove reported AI output + action report"
                      danger
                      withPresets
                    />
                  ) : null}
                  {r.subject_type === "giveaway_chat" && canReviewChats ? (
                    <Link
                      href={`/giveaways/chats/${r.subject_id}?report=${r.id}`}
                      className="rounded-md border border-neutral-300 px-2.5 py-1 text-xs font-medium text-neutral-700 hover:bg-neutral-100"
                    >
                      Review transcript
                    </Link>
                  ) : null}
                  {canBan && r.reported_user ? (
                    <ModerationActionButton
                      action={banReportedUser}
                      payload={{ reportId: r.id, reportedUserId: r.reported_user.id }}
                      label="Ban user"
                      title="Ban reported user + action report"
                      danger
                      withPresets
                    />
                  ) : null}
                  {r.reported_user ? (
                    <ModerationActionButton
                      action={addReportStrike}
                      payload={{ reportId: r.id, userId: r.reported_user.id }}
                      label="Add strike"
                      title="Add a strike to the reported user"
                      withPresets
                    />
                  ) : null}
                  <ModerationActionButton
                    action={dismissReport}
                    payload={{ reportId: r.id }}
                    label="Dismiss"
                    title="Dismiss report"
                    defaultReason="No violation found."
                  />
                  <ModerationActionButton
                    action={addReportNote}
                    payload={{ reportId: r.id }}
                    label="Add note"
                    title="Add an internal note"
                  />
                </div>
              </div>
            );
          })}

          <div className="flex flex-wrap items-center gap-2 rounded-lg border border-neutral-200 bg-white p-3">
            <span className="text-xs text-neutral-500">Bulk (checked rows):</span>
            <input
              type="text"
              name="reason"
              required
              placeholder="Shared reason (required)"
              className="min-w-56 grow rounded-md border border-neutral-300 px-3 py-1.5 text-sm"
            />
            <button
              type="submit"
              className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-100"
            >
              Dismiss selected
            </button>
          </div>
        </form>
      )}

      <div className="flex items-center justify-between text-sm">
        <div className="text-neutral-500">
          Page {page} of {totalPages}
        </div>
        <div className="flex gap-2">
          {page > 1 ? (
            <Link href={`/reports?status=${status}&page=${page - 1}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Previous
            </Link>
          ) : null}
          {page < totalPages ? (
            <Link href={`/reports?status=${status}&page=${page + 1}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Next
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
