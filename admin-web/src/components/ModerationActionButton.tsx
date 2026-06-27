"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import type { ActionState } from "@/lib/actions/moderation";
import { VIOLATION_PRESETS } from "@/lib/moderation/guidelines";

type Props = {
  action: (prev: ActionState | null, fd: FormData) => Promise<ActionState>;
  payload: Record<string, string>;
  label: string;
  title: string;
  danger?: boolean;
  defaultReason?: string;
  withPresets?: boolean;
};

// Reusable moderation action: a button that opens a reason dialog, submits the
// (audited) server action, then refreshes. Every action requires a reason (§20).
export function ModerationActionButton({
  action,
  payload,
  label,
  title,
  danger,
  defaultReason,
  withPresets,
}: Props) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState(defaultReason ?? "");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function submit() {
    setError(null);
    startTransition(async () => {
      const fd = new FormData();
      for (const [k, v] of Object.entries(payload)) fd.set(k, v);
      fd.set("reason", reason);
      const res = await action(null, fd);
      if (res.ok) {
        setOpen(false);
        setReason(defaultReason ?? "");
        router.refresh();
      } else {
        setError(res.error ?? "Action failed.");
      }
    });
  }

  const btn = danger
    ? "border-red-300 text-red-700 hover:bg-red-50"
    : "border-neutral-300 text-neutral-700 hover:bg-neutral-100";

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={`rounded-md border px-2.5 py-1 text-xs font-medium ${btn}`}
      >
        {label}
      </button>

      {open ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-md rounded-lg bg-white p-5 shadow-xl">
            <h3 className="text-sm font-semibold">{title}</h3>

            {withPresets ? (
              <div className="mt-3 flex flex-wrap gap-1.5">
                {VIOLATION_PRESETS.map((p) => (
                  <button
                    key={p.label}
                    type="button"
                    onClick={() => setReason(p.reason)}
                    title={p.suggested}
                    className="rounded-full border border-neutral-200 px-2 py-0.5 text-[11px] text-neutral-600 hover:bg-neutral-100"
                  >
                    {p.label}
                  </button>
                ))}
              </div>
            ) : null}

            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={3}
              placeholder="Reason (required)"
              className="mt-3 w-full rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-500"
            />

            {error ? <p className="mt-2 text-sm text-red-700">{error}</p> : null}

            <div className="mt-4 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setOpen(false)}
                className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm hover:bg-neutral-100"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={submit}
                disabled={pending || reason.trim() === ""}
                className={`rounded-md px-3 py-1.5 text-sm font-medium text-white disabled:opacity-50 ${
                  danger ? "bg-red-600 hover:bg-red-700" : "bg-neutral-900 hover:bg-neutral-800"
                }`}
              >
                {pending ? "Working…" : "Confirm"}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}
