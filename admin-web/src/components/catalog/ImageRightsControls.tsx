"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import { setMerchantImageRights, setProductImageRights } from "@/lib/actions/catalog";
import type { MerchantRightsPreview, TryOnReadiness } from "@/lib/dal/catalog";

/**
 * AI image-use rights, at merchant and product level.
 *
 * The one thing every control here has in common: it never decides anything.
 * `product_tryon_ready()` and `product_effective_image_rights()` are the
 * canonical definitions and they live in the database, so this file renders the
 * answers the server already computed. A console that re-derives readiness is a
 * console that can quietly disagree with what users actually get.
 *
 * Rights are stated in words as well as colour — an amber pill is not a status.
 */

const RIGHTS = ["unknown", "licensed", "restricted"] as const;
type Rights = (typeof RIGHTS)[number];

const MEANING: Record<Rights, string> = {
  unknown: "No verified decision. Not eligible for AI try-on.",
  licensed: "Verified for AI try-on processing. May become eligible.",
  restricted: "Explicitly not permitted for AI try-on. Never eligible.",
};

const TONE: Record<Rights, string> = {
  unknown: "bg-amber-100 text-amber-900",
  licensed: "bg-green-100 text-green-800",
  restricted: "bg-red-100 text-red-800",
};

function asRights(value: string | null | undefined): Rights {
  return (RIGHTS as readonly string[]).includes(value ?? "") ? (value as Rights) : "unknown";
}

export function RightsBadge({ value, label }: { value: string | null; label?: string }) {
  const rights = asRights(value);
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase ${TONE[rights]}`}
      title={MEANING[rights]}
    >
      {label ? `${label}: ` : ""}
      {rights}
    </span>
  );
}

export function ReadinessBadge({ ready }: { ready: boolean }) {
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase ${
        ready ? "bg-violet-100 text-violet-800" : "bg-neutral-200 text-neutral-700"
      }`}
    >
      {ready ? "try-on ready" : "not eligible"}
    </span>
  );
}

const BLOCKED: Record<NonNullable<TryOnReadiness["blocked_by"]>, string> = {
  rights_restricted: "Image rights are restricted.",
  rights_not_licensed: "Image rights are not licensed.",
  no_image: "No usable try-on image.",
  status_pending: "The feed marked this garment as not yet compatible.",
  status_not_ready: "Try-on status has not been earned.",
};

/**
 * The readiness breakdown, exactly as `product_tryon_readiness()` reported it.
 *
 * Rights alone are never the answer — a licensed product with no usable image is
 * still not ready, and an operator who cannot see that will keep re-licensing
 * something that was never blocked on rights.
 */
export function ReadinessPanel({ readiness }: { readiness: TryOnReadiness }) {
  const rows: [string, boolean, string?][] = [
    ["Image rights", readiness.rights_ok, readiness.effective_rights],
    ["Try-on image", readiness.image_ok, readiness.image_ok ? "available" : "missing"],
    ["Try-on status", readiness.status_ok, readiness.status],
    ["Published", readiness.active_ok],
    ["Servable in shopping", readiness.servable],
  ];
  return (
    <div className="space-y-1 text-[11px]">
      {rows.map(([label, ok, note]) => (
        <div key={label} className="flex items-center gap-2">
          {/* A word, not just a mark: "✓/✕" alone fails a screen reader and
              anyone who cannot separate the two colours. */}
          <span className={ok ? "text-green-700" : "text-neutral-500"}>
            {ok ? "✓ pass" : "✕ fail"}
          </span>
          <span className="text-neutral-600">{label}</span>
          {note && <span className="text-neutral-400">({note})</span>}
        </div>
      ))}
      <div className="pt-1">
        <ReadinessBadge ready={readiness.ready} />
        {readiness.blocked_by && (
          <span className="ml-2 text-neutral-600">{BLOCKED[readiness.blocked_by]}</span>
        )}
      </div>
    </div>
  );
}

/**
 * Merchant-level default, with a confirmation step on the way to `licensed`.
 *
 * Everything else in the console saves on click. This one does not, because it
 * is the only control that can make an entire catalogue eligible for paid AI
 * rendering on imagery we do not own — and the person clicking it has to be able
 * to see how many products that is before they do.
 */
export function MerchantImageRightsControl({
  merchantId,
  merchantName,
  current,
  preview,
}: {
  merchantId: string;
  merchantName: string;
  current: string | null;
  preview: MerchantRightsPreview | null;
}) {
  const router = useRouter();
  const currentRights = asRights(current);
  const [choice, setChoice] = useState<Rights>(currentRights);
  const [acknowledged, setAcknowledged] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const noConfig = preview ? !preview.has_feed_config : false;
  const licensing = choice === "licensed" && currentRights !== "licensed";
  const dirty = choice !== currentRights;

  function save() {
    setMsg(null);
    setError(null);
    start(async () => {
      const form = new FormData();
      form.set("merchantId", merchantId);
      form.set("rights", choice);
      form.set("acknowledged", String(acknowledged));
      const res = await setMerchantImageRights(null, form);
      if (res.ok) {
        setMsg("Saved.");
        setConfirming(false);
        setAcknowledged(false);
      } else {
        setError(res.error ?? "Failed.");
      }
      router.refresh();
    });
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        <RightsBadge value={currentRights} label="current" />
        <span className="text-[11px] text-neutral-500">{MEANING[currentRights]}</span>
      </div>

      <p className="text-[11px] text-neutral-500">
        This setting controls the default AI image-use eligibility for products from this merchant
        when no product-specific override exists.
      </p>

      {noConfig ? (
        <p className="rounded border border-amber-200 bg-amber-50 px-2 py-1 text-[11px] text-amber-900">
          This merchant has no feed configuration, so there is no default to set. Products keep
          whatever rights they already carry; use the per-product override instead.
        </p>
      ) : (
        <>
          <div className="flex flex-wrap items-center gap-2">
            <label className="text-[11px] font-semibold uppercase text-neutral-400" htmlFor={`rights-${merchantId}`}>
              AI image rights default
            </label>
            <select
              id={`rights-${merchantId}`}
              value={choice}
              disabled={pending}
              onChange={(e) => {
                setChoice(e.target.value as Rights);
                setConfirming(false);
                setAcknowledged(false);
                setMsg(null);
              }}
              className="rounded border border-neutral-300 px-2 py-1 text-xs"
            >
              {RIGHTS.map((r) => (
                <option key={r} value={r}>
                  {r[0].toUpperCase() + r.slice(1)}
                </option>
              ))}
            </select>
            <button
              disabled={pending || !dirty}
              onClick={() => (licensing ? setConfirming(true) : save())}
              className="rounded bg-neutral-800 px-3 py-1 text-xs font-semibold text-white disabled:opacity-40"
            >
              {pending ? "…" : licensing ? "Review and confirm" : "Save"}
            </button>
            {msg && <span className="text-[11px] text-neutral-700">{msg}</span>}
            {error && <span className="text-[11px] text-red-600">{error}</span>}
          </div>

          {licensing && !confirming && (
            <p className="text-[11px] text-amber-900">
              Select Licensed only after confirming that Wear The Mood is permitted to submit this
              merchant&apos;s product imagery to the configured AI processing provider for try-on.
            </p>
          )}

          {confirming && (
            <div className="space-y-2 rounded border border-amber-300 bg-amber-50 p-3">
              <div className="text-xs font-semibold text-amber-900">
                Change AI image rights for {merchantName}?
              </div>
              <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-[11px] text-neutral-700">
                <div>
                  <dt className="text-neutral-500">Current</dt>
                  <dd className="font-semibold uppercase">{currentRights}</dd>
                </div>
                <div>
                  <dt className="text-neutral-500">New</dt>
                  <dd className="font-semibold uppercase">{choice}</dd>
                </div>
                <div>
                  <dt className="text-neutral-500">Products inheriting this default</dt>
                  <dd className="font-semibold">{preview?.inheriting_products ?? "—"}</dd>
                </div>
                <div>
                  <dt className="text-neutral-500">Products with their own override</dt>
                  <dd className="font-semibold">{preview?.overridden_products ?? "—"}</dd>
                </div>
                <div className="col-span-2">
                  <dt className="text-neutral-500">May become try-on eligible</dt>
                  <dd className="font-semibold">
                    {preview?.would_become_ready ?? "—"} product
                    {preview?.would_become_ready === 1 ? "" : "s"}
                  </dd>
                </div>
              </dl>
              <p className="text-[11px] text-neutral-700">
                Inheriting products are re-pointed at the new default and their try-on readiness is
                recomputed. Products with their own override are not changed.
              </p>
              <label className="flex items-start gap-2 text-[11px] text-neutral-800">
                <input
                  type="checkbox"
                  checked={acknowledged}
                  onChange={(e) => setAcknowledged(e.target.checked)}
                  className="mt-0.5"
                />
                <span>
                  I confirm that the required rights for AI processing of this merchant&apos;s
                  applicable product imagery have been verified.
                </span>
              </label>
              <div className="flex items-center gap-2">
                <button
                  disabled={pending || !acknowledged}
                  onClick={save}
                  className="rounded bg-amber-700 px-3 py-1 text-xs font-semibold text-white disabled:opacity-40"
                >
                  {pending ? "…" : "Set to Licensed"}
                </button>
                <button
                  disabled={pending}
                  onClick={() => {
                    setConfirming(false);
                    setAcknowledged(false);
                    setChoice(currentRights);
                  }}
                  className="rounded bg-neutral-200 px-3 py-1 text-xs font-semibold text-neutral-700"
                >
                  Cancel
                </button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}

/**
 * Product-level override.
 *
 * The three values are shown alongside each other on purpose — merchant default,
 * this product's override, and what actually results — because "inherit" is
 * meaningless without the value being inherited, and an operator who cannot see
 * all three cannot tell whether a change did anything.
 */
export function ProductImageRightsControl({
  productId,
  merchantDefault,
  override,
  effective,
  readiness,
}: {
  productId: string;
  merchantDefault: string;
  override: string | null;
  effective: string;
  readiness: TryOnReadiness;
}) {
  const router = useRouter();
  // "" is INHERIT, which is what a null override means.
  const [choice, setChoice] = useState<string>(override ?? "");
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const dirty = choice !== (override ?? "");

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        <RightsBadge value={merchantDefault} label="merchant default" />
        <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-[11px] font-semibold uppercase text-neutral-700">
          override: {override ?? "inherit"}
        </span>
        <RightsBadge value={effective} label="effective" />
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <label
          className="text-[11px] font-semibold uppercase text-neutral-400"
          htmlFor={`product-rights-${productId}`}
        >
          Product override
        </label>
        <select
          id={`product-rights-${productId}`}
          value={choice}
          disabled={pending}
          onChange={(e) => {
            setChoice(e.target.value);
            setMsg(null);
          }}
          className="rounded border border-neutral-300 px-2 py-1 text-xs"
        >
          <option value="">Inherit merchant default</option>
          {RIGHTS.map((r) => (
            <option key={r} value={r}>
              {r[0].toUpperCase() + r.slice(1)}
            </option>
          ))}
        </select>
        <button
          disabled={pending || !dirty}
          onClick={() => {
            setMsg(null);
            setError(null);
            start(async () => {
              const form = new FormData();
              form.set("productId", productId);
              form.set("rights", choice);
              const res = await setProductImageRights(null, form);
              if (res.ok) setMsg("Saved.");
              else setError(res.error ?? "Failed.");
              router.refresh();
            });
          }}
          className="rounded bg-neutral-800 px-3 py-1 text-xs font-semibold text-white disabled:opacity-40"
        >
          {pending ? "…" : "Save rights"}
        </button>
        {msg && <span className="text-[11px] text-neutral-700">{msg}</span>}
        {error && <span className="text-[11px] text-red-600">{error}</span>}
      </div>

      <ReadinessPanel readiness={readiness} />
    </div>
  );
}
