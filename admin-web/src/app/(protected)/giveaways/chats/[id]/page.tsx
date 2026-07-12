import Link from "next/link";
import { notFound } from "next/navigation";

import { ModerationActionButton } from "@/components/ModerationActionButton";
import { StatusBadge } from "@/components/StatusBadge";
import { reviewPickupChat } from "@/lib/actions/giveaways";
import { requirePermission } from "@/lib/auth/require-admin";
import { getChatTranscript } from "@/lib/dal/giveaways";
import { fmtDate } from "@/lib/format";

// Pickup-chat transcript review (§10/§19). Reachable only for review_chats
// roles; every open of this page is audit-logged by the transcript RPC itself.
export default async function ChatTranscriptPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ report?: string }>;
}) {
  await requirePermission("review_chats");
  const { id } = await params;
  const { report } = await searchParams;
  const t = await getChatTranscript(id);
  if (!t) notFound();

  const plan = t.chat.pickup_plan ?? {};
  const planBits = ["area", "landmark", "time_slot"]
    .map((k) => plan[k])
    .filter((v): v is string => typeof v === "string" && v !== "");

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="text-xs text-neutral-500">
            <Link href="/reports" className="hover:underline">
              Reports
            </Link>{" "}
            /{" "}
            <Link href={`/giveaways/${t.chat.giveaway_id}`} className="hover:underline">
              {t.chat.giveaway_title}
            </Link>{" "}
            / pickup chat
          </div>
          <h1 className="mt-1 text-lg font-semibold">Pickup chat transcript</h1>
          <div className="mt-1 flex items-center gap-2">
            <StatusBadge status={t.chat.status} />
            {t.chat.report_flag ? (
              <span className="rounded bg-red-50 px-1.5 py-0.5 text-[10px] text-red-700">
                transcript frozen (reported)
              </span>
            ) : t.chat.report_cleared_at ? (
              <span className="rounded bg-green-50 px-1.5 py-0.5 text-[10px] text-green-700">
                cleared {fmtDate(t.chat.report_cleared_at)}
              </span>
            ) : null}
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <ModerationActionButton
            action={reviewPickupChat}
            payload={{ chatId: t.chat.id, decision: "clear", reportId: report ?? "" }}
            label="Clear flag"
            title="No violation — unfreeze; the retention cron redacts the transcript on its normal pass. Dismisses the linked report."
            defaultReason="Reviewed — no violation found."
          />
          <ModerationActionButton
            action={reviewPickupChat}
            payload={{ chatId: t.chat.id, decision: "keep_frozen", reportId: report ?? "" }}
            label="Keep frozen"
            title="Violation / escalation — keep the transcript preserved. Marks the linked report actioned."
            danger
            withPresets
          />
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <section className="rounded-lg border border-neutral-200 bg-white p-4 lg:col-span-1">
          <h2 className="text-sm font-semibold">Participants</h2>
          <dl className="mt-2 space-y-2 text-sm">
            {(
              [
                ["Owner", t.owner],
                ["Requester", t.requester],
              ] as const
            ).map(([label, p]) => (
              <div key={label}>
                <div className="text-xs text-neutral-500">{label}</div>
                <Link href={`/users/${p.id}`} className="hover:underline">
                  {p.name || p.email || p.id}
                </Link>{" "}
                <span className="text-xs text-neutral-400">({p.account_status})</span>
              </div>
            ))}
          </dl>

          <h2 className="mt-4 text-sm font-semibold">Window</h2>
          <div className="mt-1 text-sm text-neutral-600">
            approved {fmtDate(t.chat.approved_at)} · expires {fmtDate(t.chat.expires_at)}
          </div>

          <h2 className="mt-4 text-sm font-semibold">Pickup plan</h2>
          <div className="mt-1 text-sm text-neutral-600">
            {planBits.length > 0 ? planBits.join(" · ") : "—"}
            {plan.confirmed === true ? " · confirmed" : ""}
          </div>

          <h2 className="mt-4 text-sm font-semibold">Reports ({t.reports.length})</h2>
          {t.reports.length === 0 ? (
            <p className="mt-1 text-sm text-neutral-500">None.</p>
          ) : (
            <ul className="mt-1 space-y-1 text-sm">
              {t.reports.map((r) => (
                <li key={r.id} className="flex items-center justify-between gap-2">
                  <span className="min-w-0 truncate">{r.reason || "—"}</span>
                  <StatusBadge status={r.status} />
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="rounded-lg border border-neutral-200 bg-white p-4 lg:col-span-2">
          <h2 className="text-sm font-semibold">Messages ({t.messages.length})</h2>
          {t.messages.length === 0 ? (
            <p className="mt-2 text-sm text-neutral-500">No messages.</p>
          ) : (
            <ol className="mt-3 space-y-2">
              {t.messages.map((m) => {
                const fromOwner = m.sender_id === t.owner.id;
                return (
                  <li key={m.id} className={`flex ${fromOwner ? "" : "justify-end"}`}>
                    <div
                      className={`max-w-[80%] rounded-lg px-3 py-2 text-sm ${
                        fromOwner ? "bg-neutral-100" : "bg-blue-50"
                      }`}
                    >
                      <div className="text-[10px] text-neutral-500">
                        {fromOwner ? t.owner.name || "owner" : t.requester.name || "requester"} ·{" "}
                        {fmtDate(m.created_at)}
                      </div>
                      {m.body_deleted ? (
                        <div className="italic text-neutral-400">(redacted)</div>
                      ) : (
                        <div className="whitespace-pre-wrap break-words">{m.body || "—"}</div>
                      )}
                    </div>
                  </li>
                );
              })}
            </ol>
          )}
        </section>
      </div>
    </div>
  );
}
