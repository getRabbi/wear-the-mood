"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import {
  clearFeedLock,
  requestNetworkDiscovery,
  requestProductSync,
  setMerchantApproved,
  setMerchantFeedEnabled,
  setMerchantFeedState,
  setMerchantShipping,
  setProductActive,
  setProductOverride,
  setProductTryOnImage,
  updateProduct,
} from "@/lib/actions/catalog";

/** Shared button. Keeps every mutation's pending/error handling identical. */
function ActionButton({
  label,
  onRun,
  tone = "neutral",
  confirm,
}: {
  label: string;
  onRun: () => Promise<{ ok: boolean; error?: string; message?: string }>;
  tone?: "neutral" | "on" | "off" | "danger";
  confirm?: string;
}) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const tones = {
    neutral: "bg-neutral-200 text-neutral-700",
    on: "bg-green-100 text-green-800",
    off: "bg-neutral-200 text-neutral-600",
    danger: "bg-red-100 text-red-800",
  } as const;

  return (
    <span className="inline-flex flex-col items-start">
      <button
        disabled={pending}
        onClick={() => {
          if (confirm && !window.confirm(confirm)) return;
          setError(null);
          start(async () => {
            const res = await onRun();
            if (!res.ok) setError(res.error ?? "Failed.");
            router.refresh();
          });
        }}
        className={`rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50 ${tones[tone]}`}
      >
        {pending ? "…" : label}
      </button>
      {error && <span className="mt-1 text-[11px] text-red-600">{error}</span>}
    </span>
  );
}

function fd(entries: Record<string, string | string[]>): FormData {
  const form = new FormData();
  for (const [k, v] of Object.entries(entries)) {
    if (Array.isArray(v)) v.forEach((item) => form.append(k, item));
    else form.set(k, v);
  }
  return form;
}

export function ProductActiveToggle({ id, active }: { id: string; active: boolean }) {
  return (
    <ActionButton
      label={active ? "Published" : "Unpublished"}
      tone={active ? "on" : "off"}
      onRun={() => setProductActive(null, fd({ productId: id, active: String(!active) }))}
    />
  );
}

export function ProductOverrideToggle({
  id,
  enabled,
  fields,
}: {
  id: string;
  enabled: boolean;
  fields: string[];
}) {
  return (
    <ActionButton
      label={enabled ? `Override${fields.length ? ` (${fields.join(", ")})` : " (all)"}` : "No override"}
      tone={enabled ? "on" : "off"}
      onRun={() =>
        setProductOverride(
          null,
          fd({ productId: id, enabled: String(!enabled), fields: enabled ? [] : fields })
        )
      }
    />
  );
}

/** The preferred try-on image. Empty clears it and drops the product out of ready. */
export function TryOnImageEditor({
  id,
  current,
  source,
}: {
  id: string;
  current: string | null;
  source: string | null;
}) {
  const router = useRouter();
  const [value, setValue] = useState(current ?? "");
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);

  return (
    <div className="space-y-1">
      <div className="flex gap-2">
        <input
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder="https://… (blank clears)"
          className="w-full rounded border border-neutral-300 px-2 py-1 text-xs"
        />
        <button
          disabled={pending}
          onClick={() => {
            setMsg(null);
            start(async () => {
              const res = await setProductTryOnImage(null, fd({ productId: id, imageUrl: value }));
              setMsg(res.ok ? "Saved." : (res.error ?? "Failed."));
              router.refresh();
            });
          }}
          className="rounded bg-neutral-800 px-3 py-1 text-xs font-semibold text-white disabled:opacity-50"
        >
          Save
        </button>
      </div>
      <div className="text-[11px] text-neutral-500">
        {source ? `source: ${source}` : "no override"}
        {msg && <span className="ml-2 text-neutral-800">{msg}</span>}
      </div>
    </div>
  );
}

/**
 * The editorial fields a human may correct.
 *
 * An affiliate feed supplies neither a usable category nor, often, a usable
 * title — four of the five launch products arrived with a null category. A
 * catalog you cannot categorise is not one you can curate, and doing it by SQL
 * is not "manage it myself".
 *
 * Price, currency and the affiliate reference are deliberately absent: those
 * are the merchant's claims about their own offer, and the database refuses
 * them too.
 */
export function ProductDetailsEditor({
  id,
  title,
  category,
  subcategory,
  brand,
  audience,
}: {
  id: string;
  title: string;
  category: string | null;
  subcategory: string | null;
  brand: string | null;
  audience: string | null;
}) {
  const router = useRouter();
  const [form, setForm] = useState({
    title,
    category: category ?? "",
    subcategory: subcategory ?? "",
    brand: brand ?? "",
    audience: audience ?? "",
  });
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);

  const field = (key: keyof typeof form, placeholder: string) => (
    <input
      value={form[key]}
      onChange={(e) => setForm({ ...form, [key]: e.target.value })}
      placeholder={placeholder}
      className="w-full rounded border border-neutral-300 px-2 py-1 text-xs"
    />
  );

  return (
    <div className="space-y-2">
      {field("title", "Title")}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {field("category", "Category")}
        {field("subcategory", "Subcategory")}
        {field("brand", "Brand")}
        <select
          value={form.audience}
          onChange={(e) => setForm({ ...form, audience: e.target.value })}
          className="w-full rounded border border-neutral-300 px-2 py-1 text-xs"
        >
          <option value="">Audience —</option>
          {["women", "men", "unisex", "kids", "baby"].map((a) => (
            <option key={a} value={a}>
              {a}
            </option>
          ))}
        </select>
      </div>
      <div className="flex items-center gap-2">
        <button
          disabled={pending}
          onClick={() => {
            setMsg(null);
            start(async () => {
              const res = await updateProduct(null, fd({ productId: id, ...form }));
              setMsg(res.ok ? "Saved." : (res.error ?? "Failed."));
              router.refresh();
            });
          }}
          className="rounded bg-neutral-800 px-3 py-1 text-xs font-semibold text-white disabled:opacity-50"
        >
          {pending ? "…" : "Save details"}
        </button>
        {msg && <span className="text-[11px] text-neutral-700">{msg}</span>}
      </div>
    </div>
  );
}

export function MerchantApprovedToggle({ id, approved }: { id: string; approved: boolean }) {
  return (
    <ActionButton
      label={approved ? "Approved" : "Disabled"}
      tone={approved ? "on" : "off"}
      confirm={
        approved
          ? "Disable this merchant? Its products stop being served immediately."
          : undefined
      }
      onRun={() => setMerchantApproved(null, fd({ merchantId: id, approved: String(!approved) }))}
    />
  );
}

export function FeedEnabledToggle({ id, enabled }: { id: string; enabled: boolean }) {
  return (
    <ActionButton
      label={enabled ? "Feed ON" : "Feed OFF"}
      tone={enabled ? "on" : "off"}
      onRun={() => setMerchantFeedEnabled(null, fd({ merchantId: id, enabled: String(!enabled) }))}
    />
  );
}

export function ClearLockButton({ id }: { id: string }) {
  return (
    <ActionButton
      label="Clear stuck lock"
      tone="danger"
      confirm="Only clear a lock left by a crashed run. Locks under 30 minutes old are not cleared."
      onRun={() => clearFeedLock(null, fd({ merchantId: id }))}
    />
  );
}

export function SyncNowButton({ id, dryRun }: { id: string; dryRun: boolean }) {
  return (
    <ActionButton
      label={dryRun ? "Dry run" : "Sync now"}
      onRun={() => requestProductSync(null, fd({ merchantId: id, dryRun: String(dryRun) }))}
    />
  );
}

/**
 * One discovered feed. `removed` means the network stopped offering it — the
 * row stays for the history, but there is nothing left to switch on.
 */
export function FeedStateToggle({
  id,
  enabled,
  removed,
}: {
  id: string;
  enabled: boolean;
  removed: boolean;
}) {
  if (removed) {
    return (
      <span className="rounded-full bg-neutral-100 px-3 py-1 text-xs font-semibold text-neutral-400">
        withdrawn
      </span>
    );
  }
  return (
    <ActionButton
      label={enabled ? "Importing" : "Off"}
      tone={enabled ? "on" : "off"}
      onRun={() => setMerchantFeedState(null, fd({ feedId: id, enabled: String(!enabled) }))}
    />
  );
}

/**
 * The countries this merchant is verified to deliver to.
 *
 * Empty is meaningful and is shown as such: it is the answer given for every
 * product whose feed said nothing about shipping, and that answer is "no".
 */
export function ShippingCountriesEditor({
  id,
  current,
  unknownProducts,
}: {
  id: string;
  current: string[];
  unknownProducts: number;
}) {
  const router = useRouter();
  const [value, setValue] = useState(current.join(", "));
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);

  return (
    <div className="space-y-1">
      <div className="flex gap-2">
        <input
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder="BD, PL, GB — blank means unverified"
          className="w-full rounded border border-neutral-300 px-2 py-1 text-xs"
        />
        <button
          disabled={pending}
          onClick={() => {
            setMsg(null);
            start(async () => {
              const res = await setMerchantShipping(null, fd({ merchantId: id, countries: value }));
              setMsg(res.ok ? "Saved." : (res.error ?? "Failed."));
              router.refresh();
            });
          }}
          className="rounded bg-neutral-800 px-3 py-1 text-xs font-semibold text-white disabled:opacity-50"
        >
          Save
        </button>
      </div>
      <div className="text-[11px] text-neutral-500">
        {unknownProducts > 0 ? (
          <>
            <strong>{unknownProducts.toLocaleString()}</strong> product
            {unknownProducts === 1 ? "" : "s"} here have no shipping data of their own and are
            answered by this list. While it is empty they match no country filter.
          </>
        ) : (
          "Verified delivery destinations. Empty means unverified, not worldwide."
        )}
        {msg && <span className="ml-2 text-neutral-800">{msg}</span>}
      </div>
    </div>
  );
}

export function DiscoverNetworkButton({ network }: { network: string }) {
  return (
    <ActionButton
      label="Re-scan network"
      onRun={() => requestNetworkDiscovery(null, fd({ network }))}
    />
  );
}
