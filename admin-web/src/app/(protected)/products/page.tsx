import {
  ProductActiveToggle,
  ProductDetailsEditor,
  ProductOverrideToggle,
  TryOnImageEditor,
} from "@/components/catalog/CatalogControls";
import {
  ProductImageRightsControl,
  ReadinessBadge,
  RightsBadge,
} from "@/components/catalog/ImageRightsControls";
import {
  ProductTryOnBulkBar,
  ProductTryOnCoverageControl,
} from "@/components/catalog/TryOnControls";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { listMerchants, listProducts } from "@/lib/dal/catalog";

export const dynamic = "force-dynamic";

function Pill({ children, tone }: { children: React.ReactNode; tone: string }) {
  return (
    <span className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${tone}`}>{children}</span>
  );
}

function money(minor: number, currency: string) {
  // Minor units are what the catalog stores; JPY has no minor unit at all, so
  // dividing by 100 unconditionally would show ¥98 for a ¥9,800 product.
  const zeroDecimal = ["JPY", "KRW", "VND"].includes(currency);
  const amount = zeroDecimal ? minor : minor / 100;
  try {
    return new Intl.NumberFormat("en", { style: "currency", currency }).format(amount);
  } catch {
    return `${amount} ${currency}`;
  }
}

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const admin = await requirePermission("view_catalog");
  const sp = await searchParams;
  const products = await listProducts({
    search: sp.q,
    merchantId: sp.merchant,
    status: sp.status ?? "all",
    tryOn: sp.tryon,
    limit: 50,
  });
  const merchants = await listMerchants();
  const editable = can(admin.role, "manage_products");
  // Rights are their own capability: merchandising a product and asserting that
  // its imagery may be sent to a generative model are different decisions.
  const canSetRights = can(admin.role, "manage_image_rights");
  const canSetCoverage = can(admin.role, "manage_tryon_coverage");
  const total = products[0]?.total_count ?? 0;

  return (
    <div className="space-y-4">
      <div className="flex items-baseline justify-between">
        <h1 className="text-lg font-semibold">Products</h1>
        <span className="text-xs text-neutral-500">{total} matching</span>
      </div>

      <form className="flex flex-wrap gap-2 rounded-lg border border-neutral-200 bg-white p-3">
        <input
          name="q"
          defaultValue={sp.q ?? ""}
          placeholder="Title, brand or external id"
          className="min-w-56 flex-1 rounded border border-neutral-300 px-2 py-1 text-sm"
        />
        <select
          name="merchant"
          defaultValue={sp.merchant ?? ""}
          className="rounded border border-neutral-300 px-2 py-1 text-sm"
        >
          <option value="">All merchants</option>
          {merchants.map((m) => (
            <option key={m.id} value={m.id}>
              {m.name}
            </option>
          ))}
        </select>
        <select
          name="status"
          defaultValue={sp.status ?? "all"}
          className="rounded border border-neutral-300 px-2 py-1 text-sm"
        >
          <option value="all">Any state</option>
          <option value="active">Published</option>
          <option value="inactive">Unpublished</option>
        </select>
        <select
          name="tryon"
          defaultValue={sp.tryon ?? ""}
          className="rounded border border-neutral-300 px-2 py-1 text-sm"
        >
          <option value="">Any try-on</option>
          <option value="ready">Ready</option>
          <option value="pending">Pending</option>
          <option value="unsupported">Unsupported</option>
        </select>
        <button className="rounded bg-neutral-800 px-3 py-1 text-sm font-semibold text-white">
          Filter
        </button>
      </form>

      {/* Bulk coverage over the current page. Selected-products-only
          administration is unusable if choosing twenty products means opening
          twenty pages, and this is deliberately scoped to what is on screen —
          a "select everything matching the filter" button is a way to switch on
          a catalogue nobody looked at. */}
      {canSetCoverage && products.length > 0 && (
        <ProductTryOnBulkBar
          products={products.map((p) => ({
            id: p.id,
            title: p.title,
            rightsLicensed: p.effective_image_rights === "licensed",
          }))}
        />
      )}

      {products.length === 0 ? (
        <p className="rounded-lg border border-neutral-200 bg-white p-6 text-sm text-neutral-500">
          No products match.
        </p>
      ) : (
        <div className="space-y-3">
          {products.map((p) => (
            <section key={p.id} className="rounded-lg border border-neutral-200 bg-white p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="flex gap-3">
                  {/* A plain <img>: merchant CDN hosts are not in the Next image
                      allowlist, and an operator has to SEE the picture to judge
                      whether a listing belongs in the catalog. */}
                  <img
                    src={p.image_urls?.[0] ?? ""}
                    alt=""
                    className="h-16 w-16 shrink-0 rounded object-cover ring-1 ring-neutral-200"
                  />
                  <div>
                    <div className="text-sm font-semibold">{p.title}</div>
                    <div className="text-xs text-neutral-500">
                      {p.merchant_name} · <span className="font-mono">{p.external_id}</span> ·{" "}
                      {money(p.price_minor, p.currency)}
                    </div>
                    <div className="text-xs text-neutral-500">
                      {[p.category, p.subcategory, p.audience].filter(Boolean).join(" / ") ||
                        "uncategorised"}
                      {p.affiliate_host && (
                        <>
                          {" · "}
                          {/* HOST ONLY — the tracking parameters decide who gets
                              paid and never leave the database (§40). */}
                          <span className="font-mono">{p.affiliate_host}</span>
                        </>
                      )}
                    </div>
                  </div>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  {/* Servability is the SERVER's answer (product_is_servable),
                      not a re-implementation — the console must never disagree
                      with the RLS policy about what users can see. */}
                  <Pill tone={p.servable ? "bg-green-100 text-green-800" : "bg-neutral-200 text-neutral-600"}>
                    {p.servable ? "servable" : "not servable"}
                  </Pill>
                  {/* Where this row came from. A curated row is frozen against
                      the importer and outlives the feed; an automated one does
                      not, and telling them apart is the difference between
                      editing a choice and editing a snapshot. */}
                  <Pill
                    tone={
                      p.manual_override
                        ? "bg-blue-100 text-blue-800"
                        : "bg-neutral-100 text-neutral-700"
                    }
                  >
                    {p.manual_override ? "curated" : "automated"}
                  </Pill>
                  {/* The gate, from `product_tryon_ready()` — never re-derived
                      here. Rights are only one of its conditions. */}
                  <ReadinessBadge ready={p.tryon_ready} />
                  {/* EFFECTIVE rights: the override where one is set, otherwise
                      the product's inherited status (0067). */}
                  <RightsBadge value={p.effective_image_rights} label="rights" />
                  <Pill tone="bg-neutral-100 text-neutral-700">stock: {p.stock_status}</Pill>
                </div>
              </div>

              <dl className="mt-3 grid grid-cols-2 gap-x-6 gap-y-1 text-xs text-neutral-600 sm:grid-cols-4">
                <div>
                  <dt className="text-neutral-400">Last synced</dt>
                  <dd>{p.last_synced_at?.slice(0, 16).replace("T", " ") ?? "—"}</dd>
                </div>
                <div>
                  <dt className="text-neutral-400">Last seen in feed</dt>
                  <dd>{p.last_seen_in_feed_at?.slice(0, 16).replace("T", " ") ?? "never"}</dd>
                </div>
                <div>
                  <dt className="text-neutral-400">Missed runs</dt>
                  <dd>{p.missing_run_count}</dd>
                </div>
                <div>
                  <dt className="text-neutral-400">Retired by sync</dt>
                  <dd>{p.deactivated_by_sync_at ? "yes" : "no"}</dd>
                </div>
                <div>
                  <dt className="text-neutral-400">Shipping</dt>
                  <dd>
                    {p.country_eligibility === "unknown"
                      ? "unknown — buyer checks at retailer"
                      : p.country_eligibility}
                  </dd>
                </div>
              </dl>

              {editable && (
                <div className="mt-3 space-y-3 border-t border-neutral-100 pt-3">
                  <ProductDetailsEditor
                    id={p.id}
                    title={p.title}
                    category={p.category}
                    subcategory={p.subcategory}
                    brand={p.brand}
                    audience={p.audience}
                  />
                  <div className="flex flex-wrap items-center gap-3">
                    <ProductActiveToggle id={p.id} active={p.active} />
                    <ProductOverrideToggle
                      id={p.id}
                      enabled={p.manual_override}
                      fields={p.manual_override_fields ?? []}
                    />
                  </div>
                  <div>
                    <div className="mb-1 text-[11px] font-semibold uppercase text-neutral-400">
                      Preferred try-on image
                    </div>
                    {/* Hidden when rights are not licensed, because the action
                        cannot succeed — the RPC refuses it. The UI is the
                        courtesy; the database is the guard, and it stays on
                        whether or not this branch is rendered. */}
                    {p.effective_image_rights === "licensed" ? (
                      <TryOnImageEditor
                        id={p.id}
                        current={p.tryon_image_url}
                        source={p.tryon_image_source}
                      />
                    ) : (
                      <p className="text-[11px] text-neutral-500">
                        Unavailable until image rights are licensed.
                      </p>
                    )}
                  </div>
                </div>
              )}

              {(canSetRights || canSetCoverage) && (
                <div className="mt-3 space-y-3 border-t border-neutral-100 pt-3">
                  <div className="text-xs font-semibold text-neutral-700">AI virtual try-on</div>

                  {canSetCoverage && (
                    <div>
                      <div className="mb-1 text-[11px] font-semibold uppercase text-neutral-400">
                        Try-on
                      </div>
                      <ProductTryOnCoverageControl
                        productId={p.id}
                        merchantMode={p.merchant_tryon_mode}
                        override={p.tryon_policy_override}
                        effective={p.effective_tryon_policy}
                      />
                    </div>
                  )}

                  {canSetRights && (
                    <div>
                      <div className="mb-1 text-[11px] font-semibold uppercase text-neutral-400">
                        Image rights
                      </div>
                      <ProductImageRightsControl
                        productId={p.id}
                        merchantDefault={p.merchant_image_rights_default}
                        override={p.image_rights_override}
                        effective={p.effective_image_rights}
                        readiness={p.tryon_readiness}
                        evidence={{
                          basis: p.rights_basis,
                          reference: p.rights_reference,
                          verifiedAt: p.rights_verified_at,
                          verifiedBy: p.rights_verified_by,
                        }}
                      />
                    </div>
                  )}
                </div>
              )}
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
