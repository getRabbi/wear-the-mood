import { CampaignActions } from "@/components/billing/CampaignActions";
import { CampaignForm } from "@/components/billing/CampaignForm";
import { StatusBadge } from "@/components/StatusBadge";
import { requirePermission } from "@/lib/auth/require-admin";
import { listCampaigns } from "@/lib/dal/billing";
import { fmtDate, fmtNum } from "@/lib/format";

export default async function NotificationsPage() {
  await requirePermission("send_push");
  const list = await listCampaigns({ limit: 50 });

  return (
    <div className="space-y-6">
      <h1 className="text-lg font-semibold">Notifications</h1>

      <section className="rounded-lg border border-neutral-200 bg-white">
        <div className="border-b border-neutral-200 px-4 py-3 text-sm font-semibold">
          New campaign
        </div>
        <div className="p-4">
          <CampaignForm />
        </div>
      </section>

      <section className="rounded-lg border border-neutral-200 bg-white">
        <div className="border-b border-neutral-200 px-4 py-3 text-sm font-semibold">
          Campaigns ({fmtNum(list.total)})
        </div>
        {list.rows.length === 0 ? (
          <div className="p-4 text-sm text-neutral-500">No campaigns yet.</div>
        ) : (
          <ul className="divide-y divide-neutral-100">
            {list.rows.map((c) => (
              <li key={c.id} className="flex flex-wrap items-start justify-between gap-3 p-4">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{c.title}</span>
                    <StatusBadge status={c.status} />
                    <span className="rounded bg-neutral-100 px-1.5 py-0.5 text-[10px] text-neutral-500">
                      {c.target_segment}
                    </span>
                  </div>
                  <p className="mt-1 text-sm text-neutral-600">{c.body}</p>
                  <div className="mt-1 text-xs text-neutral-500">
                    {c.created_by_email} · created {fmtDate(c.created_at)}
                    {c.sent_at ? ` · sent ${fmtDate(c.sent_at)}` : ""}
                    {typeof c.metadata?.recipients === "number"
                      ? ` · ${c.metadata.recipients} recipients`
                      : ""}
                  </div>
                </div>
                <CampaignActions id={c.id} status={c.status} />
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
