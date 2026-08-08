import { FlagToggle } from "@/components/settings/FlagToggle";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { getAutomationFlag, listSyncRuns } from "@/lib/dal/catalog";
import { listNewsRuns } from "@/lib/dal/newsroom";

export const dynamic = "force-dynamic";

const STATUS_TONE: Record<string, string> = {
  success: "bg-green-100 text-green-800",
  partial: "bg-amber-100 text-amber-800",
  failed: "bg-red-100 text-red-800",
  skipped: "bg-neutral-200 text-neutral-600",
  queued: "bg-blue-100 text-blue-800",
  running: "bg-blue-100 text-blue-800",
};

function Status({ value }: { value: string }) {
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${
        STATUS_TONE[value] ?? "bg-neutral-200 text-neutral-600"
      }`}
    >
      {value}
    </span>
  );
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-neutral-200 bg-white">
      <div className="border-b border-neutral-200 px-4 py-3 text-sm font-semibold">{title}</div>
      <div className="p-4">{children}</div>
    </section>
  );
}

export default async function AutomationPage() {
  const admin = await requirePermission("view_catalog");
  const [productRuns, newsRuns, productOn, newsOn] = await Promise.all([
    listSyncRuns(undefined, 20),
    listNewsRuns(20),
    getAutomationFlag("feature_product_automation"),
    getAutomationFlag("feature_news_automation"),
  ]);
  const canToggle = can(admin.role, "manage_settings");

  return (
    <div className="space-y-6">
      <h1 className="text-lg font-semibold">Automation</h1>

      <Card title="Kill switches">
        <p className="mb-3 text-xs text-neutral-500">
          Checked server-side by the crons, not only here — switching one off actually stops the
          importer rather than hiding a button. These are the existing global feature flags; there
          is no separate rollout system.
        </p>
        {canToggle ? (
          <>
            <FlagToggle
              flagKey="feature_product_automation"
              description="Merchant product feed ingestion (cron + Sync Now)"
              value={productOn}
            />
            <FlagToggle
              flagKey="feature_news_automation"
              description="Newsroom RSS ingestion (cron + Sync Now)"
              value={newsOn}
            />
          </>
        ) : (
          <p className="text-sm text-neutral-600">
            Product automation: <strong>{productOn ? "ON" : "OFF"}</strong> · News automation:{" "}
            <strong>{newsOn ? "ON" : "OFF"}</strong>
          </p>
        )}
      </Card>

      <Card title="Latest product sync runs">
        {productRuns.length === 0 ? (
          <p className="text-sm text-neutral-500">No runs yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="text-neutral-400">
                <tr>
                  <th className="py-1 pr-3">Merchant</th>
                  <th className="py-1 pr-3">Status</th>
                  <th className="py-1 pr-3">Trigger</th>
                  <th className="py-1 pr-3">Fetched</th>
                  <th className="py-1 pr-3">New</th>
                  <th className="py-1 pr-3">Upd</th>
                  <th className="py-1 pr-3">Same</th>
                  <th className="py-1 pr-3">Off</th>
                  <th className="py-1 pr-3">Back</th>
                  <th className="py-1 pr-3">Skip</th>
                  <th className="py-1 pr-3">Started</th>
                  <th className="py-1">Error</th>
                </tr>
              </thead>
              <tbody>
                {productRuns.map((r) => (
                  <tr key={r.id} className="border-t border-neutral-100">
                    <td className="py-1 pr-3">{r.merchant_name}</td>
                    <td className="py-1 pr-3">
                      <Status value={r.status} />
                      {r.dry_run && <span className="ml-1 text-neutral-400">(dry)</span>}
                    </td>
                    <td className="py-1 pr-3">{r.trigger_source}</td>
                    <td className="py-1 pr-3">{r.fetched}</td>
                    <td className="py-1 pr-3">{r.created}</td>
                    <td className="py-1 pr-3">{r.updated}</td>
                    <td className="py-1 pr-3">{r.unchanged}</td>
                    <td className="py-1 pr-3">{r.deactivated}</td>
                    <td className="py-1 pr-3">{r.reactivated}</td>
                    <td className="py-1 pr-3">{r.skipped}</td>
                    <td className="py-1 pr-3">{r.started_at?.slice(0, 16).replace("T", " ")}</td>
                    <td className="py-1 text-red-700">
                      {r.error_message ?? (r.errors?.length ? `${r.errors.length} item error(s)` : "")}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card title="Latest news sync runs">
        {newsRuns.length === 0 ? (
          <p className="text-sm text-neutral-500">No runs yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="text-neutral-400">
                <tr>
                  <th className="py-1 pr-3">Source</th>
                  <th className="py-1 pr-3">Status</th>
                  <th className="py-1 pr-3">Trigger</th>
                  <th className="py-1 pr-3">Fetched</th>
                  <th className="py-1 pr-3">New</th>
                  <th className="py-1 pr-3">Upd</th>
                  <th className="py-1 pr-3">Dupe</th>
                  <th className="py-1 pr-3">Skip</th>
                  <th className="py-1 pr-3">Started</th>
                  <th className="py-1">Error</th>
                </tr>
              </thead>
              <tbody>
                {newsRuns.map((r) => (
                  <tr key={r.id} className="border-t border-neutral-100">
                    <td className="py-1 pr-3">{r.source_name ?? "all"}</td>
                    <td className="py-1 pr-3">
                      <Status value={r.status} />
                    </td>
                    <td className="py-1 pr-3">{r.trigger_source}</td>
                    <td className="py-1 pr-3">{r.fetched}</td>
                    <td className="py-1 pr-3">{r.created}</td>
                    <td className="py-1 pr-3">{r.updated}</td>
                    <td className="py-1 pr-3">{r.duplicates}</td>
                    <td className="py-1 pr-3">{r.skipped}</td>
                    <td className="py-1 pr-3">{r.started_at?.slice(0, 16).replace("T", " ")}</td>
                    <td className="py-1 text-red-700">{r.error_message ?? ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}
