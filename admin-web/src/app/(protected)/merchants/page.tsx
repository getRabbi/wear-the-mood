import {
  ClearLockButton,
  DiscoverNetworkButton,
  FeedEnabledToggle,
  FeedStateToggle,
  MerchantApprovedToggle,
  ShippingCountriesEditor,
  SyncNowButton,
} from "@/components/catalog/CatalogControls";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import {
  getNetworkConnection,
  listDiscoveryRuns,
  listMerchantFeeds,
  listMerchants,
  listNetworkMerchants,
  type MerchantFeedRow,
  type NetworkMerchantRow,
} from "@/lib/dal/catalog";

export const dynamic = "force-dynamic";

const HEALTH_TONE: Record<string, string> = {
  ok: "bg-green-100 text-green-800",
  degraded: "bg-amber-100 text-amber-800",
  stale: "bg-amber-100 text-amber-800",
  failed: "bg-red-100 text-red-800",
};

const when = (v: string | null | undefined) => v?.slice(0, 16).replace("T", " ") ?? "—";

/**
 * The feeds one network advertiser offers.
 *
 * Deliberately a list of names and numbers. There is no URL column on the table
 * behind it, so there is no URL to render — the authenticated address is built
 * in the backend at download time and lives nowhere a browser can reach.
 */
function FeedList({ feeds, canManage }: { feeds: MerchantFeedRow[]; canManage: boolean }) {
  if (feeds.length === 0) {
    return <p className="text-xs text-neutral-500">No feeds discovered yet.</p>;
  }
  return (
    <ul className="divide-y divide-neutral-100">
      {feeds.map((f) => (
        <li key={f.id} className="flex flex-wrap items-center justify-between gap-2 py-1.5">
          <div className="min-w-0">
            <div className="truncate text-xs font-medium text-neutral-800">
              {f.name || `feed ${f.network_feed_id}`}
              {f.needs_review && (
                <span className="ml-2 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-semibold text-amber-800">
                  review: {f.review_reason ?? "changed"}
                </span>
              )}
            </div>
            <div className="font-mono text-[11px] text-neutral-400">
              #{f.network_feed_id}
              {f.language ? ` · ${f.language}` : ""}
              {f.product_count != null ? ` · ${f.product_count.toLocaleString()} products` : ""}
              {` · seen ${when(f.last_seen_at)}`}
            </div>
          </div>
          {canManage ? (
            <FeedStateToggle id={f.id} enabled={f.enabled} removed={!!f.removed_at} />
          ) : (
            <span className="text-[11px] text-neutral-500">
              {f.removed_at ? "withdrawn" : f.enabled ? "importing" : "off"}
            </span>
          )}
        </li>
      ))}
    </ul>
  );
}

export default async function MerchantsPage() {
  const admin = await requirePermission("view_catalog");
  const canManage = can(admin.role, "manage_merchants");
  const canSync = can(admin.role, "run_product_sync");

  const [merchants, networkMerchants, discoveryRuns, connection] = await Promise.all([
    listMerchants(),
    listNetworkMerchants(),
    listDiscoveryRuns(3),
    getNetworkConnection(),
  ]);

  const feedEntries = await Promise.all(
    networkMerchants.map(
      async (n) => [n.merchant_id, await listMerchantFeeds(n.merchant_id)] as const
    )
  );
  const feedsByMerchant = new Map<string, MerchantFeedRow[]>(feedEntries);
  const networkByMerchant = new Map<string, NetworkMerchantRow>(
    networkMerchants.map((n) => [n.merchant_id, n])
  );
  const lastRun = discoveryRuns[0];

  return (
    <div className="space-y-4">
      <h1 className="text-lg font-semibold">Merchants</h1>
      <p className="text-xs text-neutral-500">
        A merchant imports only when it is <strong>approved</strong> and its feed is{" "}
        <strong>enabled</strong> — two separate decisions, both required. Feed URLs and affiliate
        tags are never shown here: only the host and the agreement status.
      </p>

      {/* ── affiliate network connection ───────────────────────────────────── */}
      <section className="rounded-lg border border-neutral-200 bg-white p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <div className="text-sm font-semibold">Awin</div>
            <div className="text-xs text-neutral-500">
              {connection.configured === true && (
                <>
                  Connected
                  {connection.publisherId && (
                    <>
                      {" "}
                      as publisher <span className="font-mono">{connection.publisherId}</span>
                    </>
                  )}
                  . The API key lives in the backend only — this console never holds it.
                </>
              )}
              {connection.configured === false &&
                "The last scan could not authenticate. Check AWIN_DATA_FEED_API_KEY on the backend."}
              {connection.configured === null &&
                "No scan has run yet. Enable feature_network_discovery and re-scan."}
            </div>
          </div>
          {canManage && <DiscoverNetworkButton network="awin" />}
        </div>

        <dl className="mt-3 grid grid-cols-2 gap-x-6 gap-y-1 text-xs text-neutral-600 sm:grid-cols-4">
          <div>
            <dt className="text-neutral-400">Advertisers</dt>
            <dd>{networkMerchants.length}</dd>
          </div>
          <div>
            <dt className="text-neutral-400">Last scan</dt>
            <dd>{lastRun ? `${when(lastRun.started_at)} · ${lastRun.status}` : "never"}</dd>
          </div>
          <div>
            <dt className="text-neutral-400">Feeds seen</dt>
            <dd>
              {lastRun
                ? `${lastRun.feeds_seen} (+${lastRun.feeds_added} new, −${lastRun.feeds_removed} gone)`
                : "—"}
            </dd>
          </div>
          <div>
            <dt className="text-neutral-400">Scan error</dt>
            <dd className="truncate">{lastRun?.error_message ?? "none"}</dd>
          </div>
        </dl>
        <p className="mt-2 text-[11px] text-neutral-400">
          Discovery only lists what the account already has access to. A new advertiser appears here
          after it is joined on Awin — no code change, no feed id to type in.
        </p>
      </section>

      {merchants.length === 0 ? (
        <p className="rounded-lg border border-neutral-200 bg-white p-6 text-sm text-neutral-500">
          No merchants yet.
        </p>
      ) : (
        <div className="space-y-3">
          {merchants.map((m) => {
            const net = networkByMerchant.get(m.id);
            const feeds = feedsByMerchant.get(m.id) ?? [];
            return (
            <section key={m.id} className="rounded-lg border border-neutral-200 bg-white p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <div className="text-sm font-semibold">{m.name}</div>
                  <div className="font-mono text-xs text-neutral-500">{m.slug}</div>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  {net && (
                    <span className="rounded-full bg-neutral-900 px-2 py-0.5 text-[11px] font-semibold text-white">
                      {net.network} #{net.network_advertiser_id}
                    </span>
                  )}
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
                  <dt className="text-neutral-400">Feed source</dt>
                  <dd className="font-mono">
                    {net
                      ? `${net.network} · ${net.enabled_feed_count}/${net.feed_count} feeds on`
                      : (m.feed_url_host ?? "not configured")}
                  </dd>
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
                  <dt className="text-neutral-400">Verified shipping</dt>
                  <dd>
                    {m.shipping_countries?.length
                      ? m.shipping_countries.join(", ")
                      : "unverified"}
                  </dd>
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

              {canManage && (
                <div className="mt-3 border-t border-neutral-100 pt-3">
                  <div className="mb-1 text-xs font-semibold text-neutral-700">
                    Verified delivery destinations
                  </div>
                  <ShippingCountriesEditor
                    id={m.id}
                    current={m.shipping_countries ?? []}
                    unknownProducts={net?.unknown_shipping_count ?? 0}
                  />
                </div>
              )}

              {net && (
                <details className="mt-3 border-t border-neutral-100 pt-3" open={feeds.length <= 8}>
                  <summary className="cursor-pointer text-xs font-semibold text-neutral-700">
                    Feeds — {net.enabled_feed_count} of {net.feed_count} importing
                    {net.declared_products > 0 &&
                      `, ${net.declared_products.toLocaleString()} products declared`}
                    {net.removed_feed_count > 0 && `, ${net.removed_feed_count} withdrawn`}
                  </summary>
                  <div className="mt-2">
                    <FeedList feeds={feeds} canManage={canManage} />
                  </div>
                  <p className="mt-2 text-[11px] text-neutral-400">
                    Last run: {net.last_run_status ?? "none"}
                    {net.last_run_complete === false && (
                      <span className="ml-1 font-semibold text-amber-700">
                        — source incomplete, so nothing was retired
                      </span>
                    )}
                    {` · ${when(net.last_run_at)}`}
                  </p>
                </details>
              )}

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
            );
          })}
        </div>
      )}
    </div>
  );
}
