"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import {
  bulkSetProductTryOn,
  setMerchantTryOnMode,
  setProductTryOnOverride,
} from "@/lib/actions/catalog";
import type { MerchantTryOnSummary, TryOnMode } from "@/lib/dal/catalog";

/**
 * AI virtual try-on COVERAGE — the operational switch (0068).
 *
 * The whole point of this file is that it is not the rights file. Rights say
 * whether we MAY; coverage says whether we DO. They are rendered next to each
 * other and never merged, because an operator who can only express one of them
 * ends up using a rights value to perform an outage — retracting a claim about
 * permission in order to turn something off — and that is a claim nobody should
 * make casually in either direction.
 *
 * Like `ImageRightsControls`, nothing here decides anything. Every count comes
 * from `admin_merchant_tryon_summary()` and every verdict from
 * `product_tryon_ready()`; this renders answers the database already gave.
 */

const MODES: { value: TryOnMode; label: string; blurb: string }[] = [
  {
    value: "off",
    label: "Off",
    blurb:
      "No product from this store can be tried on, including any switched on individually. Shopping, saving and Shop at Store keep working.",
  },
  {
    value: "all",
    label: "All eligible products",
    blurb:
      "Every product that passes the rights and readiness checks — and anything imported later — unless the product itself is switched off.",
  },
  {
    value: "selected",
    label: "Selected products only",
    blurb:
      "Nothing unless a product is switched on by hand. Products imported later stay off.",
  },
];

const MODE_TONE: Record<TryOnMode, string> = {
  off: "bg-neutral-200 text-neutral-700",
  all: "bg-violet-100 text-violet-800",
  selected: "bg-blue-100 text-blue-800",
};

const MODE_WORD: Record<TryOnMode, string> = {
  off: "off",
  all: "all eligible",
  selected: "selected only",
};

export function TryOnModeBadge({ mode }: { mode: TryOnMode }) {
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase ${MODE_TONE[mode]}`}
      title={MODES.find((m) => m.value === mode)?.blurb}
    >
      try-on: {MODE_WORD[mode]}
    </span>
  );
}

/**
 * Merchant coverage, with a confirmation on the way to `all`.
 *
 * `off` and `selected` save on click: both only ever narrow what is exposed, and
 * putting a dialog in front of an emergency shutdown is how a shutdown gets
 * delayed. `all` is the one direction that widens, so it quotes the real number
 * first.
 */
export function MerchantTryOnCoverageControl({
  merchantId,
  merchantName,
  summary,
}: {
  merchantId: string;
  merchantName: string;
  summary: MerchantTryOnSummary | null;
}) {
  const router = useRouter();
  const current: TryOnMode = summary?.tryon_mode ?? "off";
  const [choice, setChoice] = useState<TryOnMode>(current);
  const [acknowledged, setAcknowledged] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const widening = choice === "all" && current !== "all";
  const dirty = choice !== current;
  // The confirmation always shows for `all` — the operator has to see the number
  // before exposing a catalogue. The TICK is only required where rights have not
  // been verified: once they have, the hard decision was made on the rights
  // control and repeating it here is friction that teaches people to click
  // through. The Server Action decides this from stored rights, not from here.
  const rightsVerified = summary?.image_rights_default === "licensed";

  function save() {
    setMsg(null);
    setError(null);
    start(async () => {
      const form = new FormData();
      form.set("merchantId", merchantId);
      form.set("mode", choice);
      form.set("acknowledged", String(acknowledged || !widening));
      const res = await setMerchantTryOnMode(null, form);
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
        <TryOnModeBadge mode={current} />
        <span className="text-[11px] text-neutral-500">
          {MODES.find((m) => m.value === current)?.blurb}
        </span>
      </div>

      <fieldset className="space-y-1">
        <legend className="text-[11px] font-semibold uppercase text-neutral-400">
          Try-on coverage
        </legend>
        {MODES.map((m) => (
          <label key={m.value} className="flex items-start gap-2 text-xs text-neutral-800">
            <input
              type="radio"
              name={`tryon-mode-${merchantId}`}
              value={m.value}
              checked={choice === m.value}
              disabled={pending}
              onChange={() => {
                setChoice(m.value);
                setConfirming(false);
                setAcknowledged(false);
                setMsg(null);
              }}
              className="mt-0.5"
            />
            <span>
              <span className="font-semibold">{m.label}</span>
              <span className="block text-[11px] text-neutral-500">{m.blurb}</span>
            </span>
          </label>
        ))}
      </fieldset>

      <div className="flex flex-wrap items-center gap-2">
        <button
          disabled={pending || !dirty}
          onClick={() => (widening ? setConfirming(true) : save())}
          className="rounded bg-neutral-800 px-3 py-1 text-xs font-semibold text-white disabled:opacity-40"
        >
          {pending ? "…" : widening ? "Review and confirm" : "Save coverage"}
        </button>
        {msg && <span className="text-[11px] text-neutral-700">{msg}</span>}
        {error && <span className="text-[11px] text-red-600">{error}</span>}
      </div>

      {confirming && (
        <div className="space-y-2 rounded border border-violet-300 bg-violet-50 p-3">
          <div className="text-xs font-semibold text-violet-900">
            Switch {merchantName} to all eligible products?
          </div>
          <p className="text-[11px] text-neutral-700">
            This will allow up to{" "}
            <strong>{(summary?.eligible_if_all ?? 0).toLocaleString()}</strong> currently eligible
            product{summary?.eligible_if_all === 1 ? "" : "s"} from {merchantName} to expose Try On.
            Future eligible products from this merchant will also inherit this setting.
          </p>
          {(summary?.explicitly_disabled ?? 0) > 0 && (
            <p className="text-[11px] text-neutral-700">
              {summary?.explicitly_disabled} product
              {summary?.explicitly_disabled === 1 ? " is" : "s are"} switched off individually and
              will stay off.
            </p>
          )}
          {(summary?.blocked_rights ?? 0) > 0 && (
            <p className="text-[11px] text-neutral-700">
              {summary?.blocked_rights} product{summary?.blocked_rights === 1 ? "" : "s"} in this
              catalogue {summary?.blocked_rights === 1 ? "does" : "do"} not have licensed image
              rights and will remain ineligible. This switch does not change that.
            </p>
          )}
          {rightsVerified ? (
            <p className="text-[11px] text-neutral-600">
              This merchant&apos;s image rights are already verified as licensed.
            </p>
          ) : (
            <label className="flex items-start gap-2 text-[11px] text-neutral-800">
              <input
                type="checkbox"
                checked={acknowledged}
                onChange={(e) => setAcknowledged(e.target.checked)}
                className="mt-0.5"
              />
              <span>
                This merchant&apos;s image rights are not verified as licensed. I want its
                eligible products, present and future, to expose Try On anyway — nothing will
                actually become eligible until rights are licensed.
              </span>
            </label>
          )}
          <div className="flex items-center gap-2">
            <button
              disabled={pending || !(acknowledged || rightsVerified)}
              onClick={save}
              className="rounded bg-violet-700 px-3 py-1 text-xs font-semibold text-white disabled:opacity-40"
            >
              {pending ? "…" : "Switch on for all eligible"}
            </button>
            <button
              disabled={pending}
              onClick={() => {
                setConfirming(false);
                setAcknowledged(false);
                setChoice(current);
              }}
              className="rounded bg-neutral-200 px-3 py-1 text-xs font-semibold text-neutral-700"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {summary && <MerchantTryOnDiagnostics summary={summary} />}
    </div>
  );
}

/**
 * What is actually standing between this catalogue and try-on.
 *
 * Deliberately a breakdown rather than a ratio. "1,106 of 1,284 ready" tells an
 * operator nothing they can act on; "92 missing compatible images, 71 not a
 * supported garment, 15 switched off by hand" is three different pieces of work
 * and one of them is a decision they already made.
 */
export function MerchantTryOnDiagnostics({ summary }: { summary: MerchantTryOnSummary }) {
  const rows: [string, number, string?][] = [
    ["total", summary.total_products],
    ["Try-On ready", summary.tryon_ready],
    ["image rights not licensed", summary.blocked_rights],
    ["missing compatible images", summary.blocked_no_image],
    ["unsupported garment or category", summary.blocked_status],
    ["explicitly disabled", summary.explicitly_disabled],
    ["explicitly enabled", summary.explicitly_enabled],
  ];
  if (summary.tryon_mode === "selected") {
    rows.push(["eligible, awaiting selection", summary.awaiting_selection]);
  }
  return (
    <dl className="grid grid-cols-2 gap-x-6 gap-y-0.5 border-t border-neutral-100 pt-2 text-[11px] text-neutral-600 sm:grid-cols-3">
      {rows.map(([label, value]) => (
        <div key={label} className="flex gap-1">
          <dt className="font-semibold text-neutral-800">{value.toLocaleString()}</dt>
          <dd className="text-neutral-500">{label}</dd>
        </div>
      ))}
    </dl>
  );
}

/**
 * Product coverage: inherit / on / off.
 *
 * Shows the merchant mode, this product's override and what results, for the
 * same reason the rights control does: "inherit" means nothing without the value
 * being inherited, and an operator who cannot see all three cannot tell whether
 * their change did anything.
 */
export function ProductTryOnCoverageControl({
  productId,
  merchantMode,
  override,
  effective,
}: {
  productId: string;
  merchantMode: TryOnMode;
  override: "on" | "off" | null;
  effective: "on" | "off";
}) {
  const router = useRouter();
  const [choice, setChoice] = useState<string>(override ?? "");
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const dirty = choice !== (override ?? "");

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        <TryOnModeBadge mode={merchantMode} />
        <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-[11px] font-semibold uppercase text-neutral-700">
          override: {override ?? "inherit"}
        </span>
        <span
          className={`rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase ${
            effective === "on" ? "bg-violet-100 text-violet-800" : "bg-neutral-200 text-neutral-700"
          }`}
        >
          effective: {effective}
        </span>
      </div>

      {merchantMode === "off" && (
        <p className="rounded border border-amber-200 bg-amber-50 px-2 py-1 text-[11px] text-amber-900">
          This merchant&apos;s try-on is switched off entirely, so this product cannot be tried on
          whatever is chosen here. The setting is kept and takes effect again when the merchant is
          switched back on.
        </p>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <label
          className="text-[11px] font-semibold uppercase text-neutral-400"
          htmlFor={`product-tryon-${productId}`}
        >
          Product try-on
        </label>
        <select
          id={`product-tryon-${productId}`}
          value={choice}
          disabled={pending}
          onChange={(e) => {
            setChoice(e.target.value);
            setMsg(null);
          }}
          className="rounded border border-neutral-300 px-2 py-1 text-xs"
        >
          <option value="">Inherit store policy</option>
          <option value="on">On</option>
          <option value="off">Off</option>
        </select>
        <button
          disabled={pending || !dirty}
          onClick={() => {
            setMsg(null);
            setError(null);
            start(async () => {
              const form = new FormData();
              form.set("productId", productId);
              form.set("override", choice);
              const res = await setProductTryOnOverride(null, form);
              if (res.ok) setMsg("Saved.");
              else setError(res.error ?? "Failed.");
              router.refresh();
            });
          }}
          className="rounded bg-neutral-800 px-3 py-1 text-xs font-semibold text-white disabled:opacity-40"
        >
          {pending ? "…" : "Save try-on"}
        </button>
        {msg && <span className="text-[11px] text-neutral-700">{msg}</span>}
        {error && <span className="text-[11px] text-red-600">{error}</span>}
      </div>
      <p className="text-[11px] text-neutral-500">
        Switching a product on does not license it. A product whose image rights are not licensed
        stays ineligible.
      </p>
    </div>
  );
}

/**
 * Bulk coverage over the products currently listed.
 *
 * SELECTED-only administration is unusable if picking twenty products means
 * opening twenty pages, so this is the practical path. The result message is the
 * RPC's own accounting, including how many of the selection could NOT become
 * eligible — because the failure mode of a bulk control is an operator who
 * believes twenty things went live when five did.
 *
 * The checkbox state lives here rather than in each row: a bulk action needs one
 * selection, and threading it through the row components would be the same state
 * in two places waiting to disagree.
 */
export function ProductTryOnBulkBar({
  products,
}: {
  products: { id: string; title: string; rightsLicensed: boolean }[];
}) {
  const router = useRouter();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const chosen = products.filter((p) => selected.has(p.id));
  const unlicensed = chosen.filter((p) => !p.rightsLicensed).length;

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
    setMsg(null);
  }

  function apply(override: "on" | "off" | "") {
    setMsg(null);
    setError(null);
    start(async () => {
      const form = new FormData();
      for (const id of selected) form.append("productIds", id);
      form.set("override", override);
      const res = await bulkSetProductTryOn(null, form);
      if (res.ok) {
        setMsg(res.message ?? "Applied.");
        setSelected(new Set());
      } else {
        setError(res.error ?? "Failed.");
      }
      router.refresh();
    });
  }

  return (
    <div className="sticky top-0 z-10 space-y-2 rounded-lg border border-neutral-200 bg-white p-3 shadow-sm">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs font-semibold text-neutral-800">
          {selected.size} selected
          {selected.size > 0 && unlicensed > 0 && (
            <span className="ml-1 font-normal text-amber-800">
              ({unlicensed} without licensed rights)
            </span>
          )}
        </span>
        <button
          disabled={pending || selected.size === 0}
          onClick={() => apply("on")}
          className="rounded bg-violet-700 px-3 py-1 text-xs font-semibold text-white disabled:opacity-40"
        >
          Enable try-on
        </button>
        <button
          disabled={pending || selected.size === 0}
          onClick={() => apply("off")}
          className="rounded bg-neutral-800 px-3 py-1 text-xs font-semibold text-white disabled:opacity-40"
        >
          Disable try-on
        </button>
        <button
          disabled={pending || selected.size === 0}
          onClick={() => apply("")}
          className="rounded bg-neutral-200 px-3 py-1 text-xs font-semibold text-neutral-700 disabled:opacity-40"
        >
          Clear override
        </button>
        <button
          disabled={pending}
          onClick={() =>
            setSelected(
              selected.size === products.length ? new Set() : new Set(products.map((p) => p.id))
            )
          }
          className="rounded border border-neutral-300 px-3 py-1 text-xs font-semibold text-neutral-700"
        >
          {selected.size === products.length ? "Select none" : "Select all on this page"}
        </button>
        {msg && <span className="text-[11px] text-neutral-700">{msg}</span>}
        {error && <span className="text-[11px] text-red-600">{error}</span>}
      </div>

      <div className="max-h-40 overflow-y-auto">
        <ul className="space-y-0.5">
          {products.map((p) => (
            <li key={p.id}>
              <label className="flex items-center gap-2 text-[11px] text-neutral-700">
                <input
                  type="checkbox"
                  checked={selected.has(p.id)}
                  disabled={pending}
                  onChange={() => toggle(p.id)}
                />
                <span className="truncate">{p.title}</span>
                {!p.rightsLicensed && (
                  <span className="shrink-0 rounded-full bg-amber-100 px-1.5 text-[10px] font-semibold text-amber-900">
                    rights not licensed
                  </span>
                )}
              </label>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
