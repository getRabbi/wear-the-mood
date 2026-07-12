import Link from "next/link";

import { ModerationActionButton } from "@/components/ModerationActionButton";
import { StatusBadge } from "@/components/StatusBadge";
import {
  closeGiveaway,
  deleteGiveaway,
  hideGiveaway,
  restoreGiveaway,
} from "@/lib/actions/giveaways";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { listGiveaways } from "@/lib/dal/giveaways";
import { fmtDate, fmtNum } from "@/lib/format";

const PAGE_SIZE = 25;
const STATUSES = ["available", "reserved", "claimed", "closed"];
const STATES = ["live", "hidden", "deleted"];

type SP = { q?: string; status?: string; state?: string; page?: string };

function qs(base: SP, overrides: Partial<SP>): string {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...base, ...overrides })) {
    if (v != null && v !== "") p.set(k, String(v));
  }
  const s = p.toString();
  return s ? `?${s}` : "";
}

export default async function GiveawaysPage({ searchParams }: { searchParams: Promise<SP> }) {
  const admin = await requirePermission("view_content");
  const sp = await searchParams;
  const page = Math.max(1, parseInt(sp.page ?? "1", 10) || 1);

  const result = await listGiveaways({
    search: sp.q ?? null,
    status: sp.status ?? null,
    state: sp.state ?? null,
    limit: PAGE_SIZE,
    offset: (page - 1) * PAGE_SIZE,
  });
  const totalPages = Math.max(1, Math.ceil(result.total / PAGE_SIZE));
  const canModerate = can(admin.role, "moderate_giveaways");

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold">Giveaways</h1>
        <div className="text-sm text-neutral-500">{fmtNum(result.total)} total</div>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-2">
        <input
          type="text"
          name="q"
          defaultValue={sp.q ?? ""}
          placeholder="Search title / owner / listing id"
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
        <select name="state" defaultValue={sp.state ?? ""} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="">All moderation states</option>
          {STATES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
        <button type="submit" className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800">
          Filter
        </button>
        <Link href="/giveaways" className="rounded-md border border-neutral-300 px-3 py-2 text-sm hover:bg-neutral-100">
          Reset
        </Link>
      </form>

      <div className="space-y-3">
        {result.rows.length === 0 ? (
          <div className="rounded-lg border border-neutral-200 bg-white p-8 text-center text-sm text-neutral-500">
            No giveaways match these filters.
          </div>
        ) : (
          result.rows.map((g) => (
            <div key={g.id} className="flex gap-4 rounded-lg border border-neutral-200 bg-white p-3">
              {g.image_url ? (
                <img src={g.image_url} alt="" className="h-20 w-20 shrink-0 rounded-md object-cover" />
              ) : (
                <div className="flex h-20 w-20 shrink-0 items-center justify-center rounded-md bg-neutral-100 text-xs text-neutral-400">
                  no image
                </div>
              )}

              <div className="min-w-0 grow">
                <div className="flex items-center gap-2">
                  <StatusBadge status={g.status} />
                  {g.moderation_state !== "live" ? (
                    <span className="rounded bg-amber-50 px-1.5 py-0.5 text-[10px] text-amber-700">
                      {g.moderation_state}
                    </span>
                  ) : null}
                  {g.report_count > 0 ? (
                    <span className="rounded bg-red-50 px-1.5 py-0.5 text-[10px] text-red-700">
                      {g.report_count} reports
                    </span>
                  ) : null}
                </div>
                <Link href={`/giveaways/${g.id}`} className="mt-1 block truncate text-sm hover:underline">
                  {g.title}
                </Link>
                <div className="mt-0.5 text-xs text-neutral-500">
                  by{" "}
                  <Link href={`/users/${g.owner_id}`} className="hover:underline">
                    {g.owner_name || g.owner_username || g.owner_email}
                  </Link>{" "}
                  · {fmtNum(g.claim_count)} requests · {g.area_label || "no area"} ·{" "}
                  {fmtDate(g.created_at)}
                </div>
                {g.moderation_reason ? (
                  <div className="mt-0.5 text-xs text-amber-700">reason: {g.moderation_reason}</div>
                ) : null}
              </div>

              <div className="flex shrink-0 flex-col items-end gap-1.5">
                {canModerate && g.moderation_state === "live" ? (
                  <ModerationActionButton
                    action={hideGiveaway}
                    payload={{ giveawayId: g.id }}
                    label="Hide"
                    title="Hide giveaway listing"
                    withPresets
                  />
                ) : null}
                {canModerate && g.moderation_state !== "live" ? (
                  <ModerationActionButton
                    action={restoreGiveaway}
                    payload={{ giveawayId: g.id }}
                    label="Restore"
                    title="Restore giveaway listing"
                    defaultReason="Restored after review."
                  />
                ) : null}
                {canModerate && g.status !== "closed" && g.moderation_state !== "deleted" ? (
                  <ModerationActionButton
                    action={closeGiveaway}
                    payload={{ giveawayId: g.id }}
                    label="Close"
                    title="Close giveaway (no new requests)"
                    defaultReason="Closed by moderation."
                  />
                ) : null}
                {canModerate && g.moderation_state !== "deleted" ? (
                  <ModerationActionButton
                    action={deleteGiveaway}
                    payload={{ giveawayId: g.id }}
                    label="Delete"
                    title="Soft-delete giveaway (also ends a live pickup chat)"
                    danger
                    withPresets
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
            <Link href={`/giveaways${qs(sp, { page: String(page - 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Previous
            </Link>
          ) : null}
          {page < totalPages ? (
            <Link href={`/giveaways${qs(sp, { page: String(page + 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Next
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
