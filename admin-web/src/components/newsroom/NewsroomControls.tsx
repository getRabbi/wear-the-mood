"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import {
  requestNewsSync,
  setNewsItemStatus,
  setNewsSourceEnabled,
  updateNewsItem,
  upsertNewsSource,
} from "@/lib/actions/newsroom";

type Result = { ok: boolean; error?: string; message?: string };

function fd(entries: Record<string, string>): FormData {
  const form = new FormData();
  for (const [k, v] of Object.entries(entries)) form.set(k, v);
  return form;
}

function Btn({
  label,
  onRun,
  tone = "neutral",
}: {
  label: string;
  onRun: () => Promise<Result>;
  tone?: "neutral" | "on" | "off" | "go";
}) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);
  const tones = {
    neutral: "bg-neutral-200 text-neutral-700",
    on: "bg-green-100 text-green-800",
    off: "bg-neutral-200 text-neutral-600",
    go: "bg-neutral-800 text-white",
  } as const;
  return (
    <span className="inline-flex flex-col items-start">
      <button
        disabled={pending}
        onClick={() => {
          setMsg(null);
          start(async () => {
            const res = await onRun();
            setMsg(res.ok ? (res.message ?? null) : (res.error ?? "Failed."));
            router.refresh();
          });
        }}
        className={`rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50 ${tones[tone]}`}
      >
        {pending ? "…" : label}
      </button>
      {msg && <span className="mt-1 max-w-64 text-[11px] text-neutral-600">{msg}</span>}
    </span>
  );
}

export function SourceEnabledToggle({ id, enabled }: { id: string; enabled: boolean }) {
  return (
    <Btn
      label={enabled ? "Enabled" : "Disabled"}
      tone={enabled ? "on" : "off"}
      onRun={() => setNewsSourceEnabled(null, fd({ sourceId: id, enabled: String(!enabled) }))}
    />
  );
}

export function SourceSyncButton({ id, dryRun }: { id: string; dryRun: boolean }) {
  return (
    <Btn
      label={dryRun ? "Dry run" : "Sync now"}
      onRun={() => requestNewsSync(null, fd({ sourceId: id, dryRun: String(dryRun) }))}
    />
  );
}

export function ItemStatusButtons({ id, status }: { id: string; status: string }) {
  return (
    <span className="flex flex-wrap gap-2">
      {status !== "published" && (
        <Btn
          label="Publish"
          tone="go"
          onRun={() => setNewsItemStatus(null, fd({ itemId: id, status: "published" }))}
        />
      )}
      {status === "published" && (
        <Btn
          label="Unpublish"
          onRun={() => setNewsItemStatus(null, fd({ itemId: id, status: "review_required" }))}
        />
      )}
      {status !== "archived" && (
        <Btn
          label="Archive"
          onRun={() => setNewsItemStatus(null, fd({ itemId: id, status: "archived" }))}
        />
      )}
    </span>
  );
}

/** Headline, summary and attribution. Deliberately no body-text field. */
export function ItemEditor({
  id,
  title,
  summary,
  attribution,
}: {
  id: string;
  title: string;
  summary: string | null;
  attribution: string | null;
}) {
  const router = useRouter();
  const [t, setT] = useState(title);
  const [s, setS] = useState(summary ?? "");
  const [a, setA] = useState(attribution ?? "");
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);

  return (
    <div className="mt-2 space-y-2">
      <input
        value={t}
        onChange={(e) => setT(e.target.value)}
        className="w-full rounded border border-neutral-300 px-2 py-1 text-sm"
      />
      <textarea
        value={s}
        onChange={(e) => setS(e.target.value)}
        rows={3}
        maxLength={1200}
        placeholder="Summary (never the full article)"
        className="w-full rounded border border-neutral-300 px-2 py-1 text-xs"
      />
      <div className="flex gap-2">
        <input
          value={a}
          onChange={(e) => setA(e.target.value)}
          placeholder="Attribution, e.g. Reuters"
          className="flex-1 rounded border border-neutral-300 px-2 py-1 text-xs"
        />
        <button
          disabled={pending}
          onClick={() => {
            setMsg(null);
            start(async () => {
              const res = await updateNewsItem(
                null,
                fd({ itemId: id, title: t, summary: s, attribution: a })
              );
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
        {s.length}/1200 — a summary and a link, never the article body.
        {msg && <span className="ml-2 text-neutral-800">{msg}</span>}
      </div>
    </div>
  );
}

export function AddSourceForm() {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);

  return (
    <form
      action={(form) => {
        setMsg(null);
        start(async () => {
          const res = await upsertNewsSource(null, form);
          setMsg(res.ok ? (res.message ?? "Saved.") : (res.error ?? "Failed."));
          router.refresh();
        });
      }}
      className="grid gap-2 sm:grid-cols-2"
    >
      <input name="slug" placeholder="slug (e.g. hypebeast)" required
        className="rounded border border-neutral-300 px-2 py-1 text-sm" />
      <input name="name" placeholder="Display name" required
        className="rounded border border-neutral-300 px-2 py-1 text-sm" />
      <input name="feedUrl" placeholder="https://…/feed.xml" required
        className="rounded border border-neutral-300 px-2 py-1 text-sm sm:col-span-2" />
      <input name="publisher" placeholder="Publisher (attribution)"
        className="rounded border border-neutral-300 px-2 py-1 text-sm" />
      <input name="category" placeholder="Category"
        className="rounded border border-neutral-300 px-2 py-1 text-sm" />
      <input name="priority" type="number" defaultValue={100} min={1} max={1000}
        className="rounded border border-neutral-300 px-2 py-1 text-sm" />
      <label className="flex items-center gap-2 text-xs text-neutral-600">
        <input type="checkbox" name="autoPublish" value="true" />
        Trusted — publish without review
      </label>
      <div className="sm:col-span-2">
        <button disabled={pending}
          className="rounded bg-neutral-800 px-3 py-1 text-sm font-semibold text-white disabled:opacity-50">
          {pending ? "Saving…" : "Add source"}
        </button>
        {msg && <span className="ml-3 text-xs text-neutral-700">{msg}</span>}
      </div>
    </form>
  );
}
