import {
  ClearLockButton,
  FeedEnabledToggle,
  MerchantApprovedToggle,
  SyncNowButton,
} from "@/components/catalog/CatalogControls";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { listMerchants } from "@/lib/dal/catalog";

export const dynamic = "force-dynamic";

const HEALTH_TONE: Record<string, string> = {
  ok: "bg-green-100 text-green-800",
  degraded: "bg-amber-100 text-amber-800",
  stale: "bg-amber-100 text-amber-800",
  failed: "bg-red-100 text-red-800",
};

export default async function MerchantsPage() {
  const admin = await requirePermission("view_catalog");
  const merchants = await listMerchants();
  const canManage = can(admin.role, "manage_merchants");
  const canSync = can(admin.role, "run_product_sync");

  return (
    <div className="space-y-4">
      <h1 className="text-lg font-semibold">Merchants</h1>
      <p className="text-xs text-neutral-500">
        A merchant imports only when it is <strong>approved</strong> and its feed is{" "}
        <strong>enabled</strong> — two separate decisions, both required. Feed URLs and affiliate
        tags are never shown here: only the host and the agreement status.
      </p>

      {merchants.length === 0 ? (
        <p className="rounded-lg border border-neutral-200 bg-white p-6 text-sm text-neutral-500">
          No merchants yet.
        </p>
      ) : (
        <div className="space-y-3">
          {merchants.map((m) => (
            <section key={m.id} className="rounded-lg border border-neutral-200 bg-white p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <div className="text-sm font-semibold">{m.name}</div>
                  <div className="font-mono text-xs text-neutral-500">{m.slug}</div>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <span
                    className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${
                      HEALTH_TONE[m.feed_health] ?? "bg-neutral-200 text-neutral-600"
                    }`}
                  >
                    feed: {m.feed_health}
                  </span>
                  <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-[11px] text-neutral-700">
                    {m.active_product_count}/{m.product_count} live
                  </span>
                  {m.locked_at && (
                    <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-semibold text-amber-800">
                      locked
                    </span>
                  )}
                </div>
              </div>

              <dl className="mt-3 grid grid-cols-2 gap-x-6 gap-y-1 text-xs text-neutral-600 sm:grid-cols-4">
                <div>
                  <dt className="text-neutral-400">Feed host</dt>
                  <dd className="font-mono">{m.feed_url_host ?? "not configured"}</dd>
                </div>
                <div>
                  <dt className="text-neutral-400">Format</dt>
                  <dd>{m.feed_format ?? "—"}</dd>
                </div>
                <div>
                  <dt className="text-neutral-400">Image rights default</dt>
                  <dd>{m.image_rights_default ?? "—"}</dd>
                </div>
                <div>
                  <dt className="text-neutral-400">Consecutive failures</dt>
                  <dd>{m.consecutive_failures}</dd>
                </div>
                <div>
                  <dt className="text-neutral-400">Affiliate</dt>
                  <dd>
                    {m.affiliate_configured ? (m.affiliate_status ?? "configured") : "not configured"}
                  </dd>
                </div>
                <div>
                  <dt className="text-neutral-400">Shipping countries</dt>
                  <dd>{m.shipping_countries?.join(", ") || "—"}</dd>
                </div>
                <div className="col-span-2">
                  <dt className="text-neutral-400">Approved redirect domains</dt>
                  <dd className="font-mono">{m.allowed_domains?.join(", ") || "none"}</dd>
                </div>
                <div>
                  <dt className="text-neutral-400">Last synced</dt>
                  <dd>{m.last_synced_at?.slice(0, 16).replace("T", " ") ?? "never"}</dd>
                </div>
                <div>
                  <dt className="text-neutral-400">Backoff until</dt>
                  <dd>{m.retry_after?.slice(0, 16).replace("T", " ") ?? "—"}</dd>
                </div>
              </dl>

              {(canManage || canSync) && (
                <div className="mt-3 flex flex-wrap items-center gap-3 border-t border-neutral-100 pt-3">
                  {canManage && <MerchantApprovedToggle id={m.id} approved={m.approved} />}
                  {canManage && <FeedEnabledToggle id={m.id} enabled={m.feed_enabled} />}
                  {canSync && m.feed_enabled && m.approved && (
                    <>
                      <SyncNowButton id={m.id} dryRun />
                      <SyncNowButton id={m.id} dryRun={false} />
                    </>
                  )}
                  {canManage && m.locked_at && <ClearLockButton id={m.id} />}
                </div>
              )}
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
