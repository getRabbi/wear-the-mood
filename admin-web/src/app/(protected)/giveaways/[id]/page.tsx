import Link from "next/link";
import { notFound } from "next/navigation";

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
import { getGiveawayDetail } from "@/lib/dal/giveaways";
import { fmtDate } from "@/lib/format";

export default async function GiveawayDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const admin = await requirePermission("view_content");
  const { id } = await params;
  const detail = await getGiveawayDetail(id);
  if (!detail?.giveaway) notFound();

  const g = detail.giveaway;
  const state = g.deleted_at ? "deleted" : g.hidden_at ? "hidden" : "live";
  const canModerate = can(admin.role, "moderate_giveaways");
  const canReviewChats = can(admin.role, "review_chats");

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="text-xs text-neutral-500">
            <Link href="/giveaways" className="hover:underline">
              Giveaways
            </Link>{" "}
            / {g.id}
          </div>
          <h1 className="mt-1 text-lg font-semibold">{g.title}</h1>
          <div className="mt-1 flex items-center gap-2">
            <StatusBadge status={g.status} />
            {state !== "live" ? (
              <span className="rounded bg-amber-50 px-1.5 py-0.5 text-[10px] text-amber-700">
                {state}
              </span>
            ) : null}
            {g.is_seed ? (
              <span className="rounded bg-blue-50 px-1.5 py-0.5 text-[10px] text-blue-700">seed</span>
            ) : null}
          </div>
        </div>
        {canModerate ? (
          <div className="flex flex-wrap gap-2">
            {state === "live" ? (
              <ModerationActionButton
                action={hideGiveaway}
                payload={{ giveawayId: g.id }}
                label="Hide"
                title="Hide giveaway listing"
                withPresets
              />
            ) : (
              <ModerationActionButton
                action={restoreGiveaway}
                payload={{ giveawayId: g.id }}
                label="Restore"
                title="Restore giveaway listing"
                defaultReason="Restored after review."
              />
            )}
            {g.status !== "closed" && state !== "deleted" ? (
              <ModerationActionButton
                action={closeGiveaway}
                payload={{ giveawayId: g.id }}
                label="Close"
                title="Close giveaway (no new requests)"
                defaultReason="Closed by moderation."
              />
            ) : null}
            {state !== "deleted" ? (
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
        ) : null}
      </div>

      {g.moderation_reason ? (
        <div className="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-800">
          moderation reason: {g.moderation_reason}
        </div>
      ) : null}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <section className="rounded-lg border border-neutral-200 bg-white p-4">
          <h2 className="text-sm font-semibold">Listing</h2>
          {g.images.length > 0 ? (
            <div className="mt-3 flex flex-wrap gap-2">
              {g.images.map((url) => (
                <img key={url} src={url} alt="" className="h-28 w-28 rounded-md object-cover" />
              ))}
            </div>
          ) : null}
          <dl className="mt-3 space-y-1 text-sm">
            <div>
              <span className="text-neutral-500">Owner:</span>{" "}
              <Link href={`/users/${g.owner_id}`} className="hover:underline">
                {g.owner_name || g.owner_email}
              </Link>{" "}
              <span className="text-xs text-neutral-400">({g.owner_status})</span>
            </div>
            <div>
              <span className="text-neutral-500">Description:</span> {g.description || "—"}
            </div>
            <div>
              <span className="text-neutral-500">Size / category / condition:</span>{" "}
              {[g.size, g.category, g.condition].filter(Boolean).join(" · ") || "—"}
            </div>
            <div>
              <span className="text-neutral-500">Area:</span> {g.area_label || "—"}
            </div>
            <div>
              <span className="text-neutral-500">Created:</span> {fmtDate(g.created_at)}
            </div>
          </dl>
        </section>

        <section className="rounded-lg border border-neutral-200 bg-white p-4">
          <h2 className="text-sm font-semibold">Reports ({detail.reports.length})</h2>
          {detail.reports.length === 0 ? (
            <p className="mt-2 text-sm text-neutral-500">No reports on this listing.</p>
          ) : (
            <ul className="mt-2 space-y-1.5 text-sm">
              {detail.reports.map((r) => (
                <li key={r.id} className="flex items-center justify-between gap-2">
                  <span className="min-w-0 truncate">{r.reason || "—"}</span>
                  <span className="flex shrink-0 items-center gap-2 text-xs text-neutral-500">
                    <StatusBadge status={r.status} /> {fmtDate(r.created_at)}
                  </span>
                </li>
              ))}
            </ul>
          )}

          <h2 className="mt-5 text-sm font-semibold">Pickup chats ({detail.chats.length})</h2>
          {detail.chats.length === 0 ? (
            <p className="mt-2 text-sm text-neutral-500">No pickup chats yet.</p>
          ) : (
            <ul className="mt-2 space-y-1.5 text-sm">
              {detail.chats.map((c) => (
                <li key={c.id} className="flex items-center justify-between gap-2">
                  <span className="min-w-0 truncate">
                    with {c.requester_name || c.requester_id}
                    {c.report_flag ? (
                      <span className="ml-2 rounded bg-red-50 px-1.5 py-0.5 text-[10px] text-red-700">
                        reported
                      </span>
                    ) : null}
                  </span>
                  <span className="flex shrink-0 items-center gap-2 text-xs text-neutral-500">
                    <StatusBadge status={c.status} />
                    {canReviewChats ? (
                      <Link href={`/giveaways/chats/${c.id}`} className="hover:underline">
                        transcript
                      </Link>
                    ) : null}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>

      <section className="rounded-lg border border-neutral-200 bg-white p-4">
        <h2 className="text-sm font-semibold">Requests ({detail.claims.length})</h2>
        {detail.claims.length === 0 ? (
          <p className="mt-2 text-sm text-neutral-500">No requests yet.</p>
        ) : (
          <div className="mt-2 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-xs text-neutral-500">
                <tr>
                  <th className="py-1.5 pr-3 font-medium">Requester</th>
                  <th className="py-1.5 pr-3 font-medium">Message</th>
                  <th className="py-1.5 pr-3 font-medium">Status</th>
                  <th className="py-1.5 font-medium">When</th>
                </tr>
              </thead>
              <tbody>
                {detail.claims.map((c) => (
                  <tr key={c.id} className="border-t border-neutral-100">
                    <td className="py-1.5 pr-3">
                      <Link href={`/users/${c.claimer_id}`} className="hover:underline">
                        {c.claimer_name || c.claimer_id}
                      </Link>
                    </td>
                    <td className="max-w-xs truncate py-1.5 pr-3">{c.message || "—"}</td>
                    <td className="py-1.5 pr-3">
                      <StatusBadge status={c.status} />
                    </td>
                    <td className="py-1.5 text-xs text-neutral-500">{fmtDate(c.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
