"use client";

import { useActionState, useEffect, useRef } from "react";

import { createCampaign, type ActionState } from "@/lib/actions/notifications";
import { SEGMENTS } from "@/lib/validation/billing";

const input = "w-full rounded-md border border-neutral-300 px-3 py-2 text-sm";

export function CampaignForm() {
  const [state, action, pending] = useActionState<ActionState | null, FormData>(createCampaign, null);
  const ref = useRef<HTMLFormElement>(null);
  useEffect(() => {
    if (state?.ok) ref.current?.reset();
  }, [state]);

  return (
    <form ref={ref} action={action} className="space-y-2">
      <input name="title" required maxLength={120} placeholder="Title" className={input} />
      <textarea name="body" required maxLength={500} rows={3} placeholder="Body" className={input} />
      <select name="segment" defaultValue="all" className={input}>
        {SEGMENTS.map((s) => (
          <option key={s} value={s}>
            {s}
          </option>
        ))}
      </select>
      <div className="flex items-center gap-3">
        <button
          type="submit"
          disabled={pending}
          className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-50"
        >
          {pending ? "Saving…" : "Save draft"}
        </button>
        {state?.ok ? <span className="text-sm text-green-700">Draft saved.</span> : null}
        {state && !state.ok ? <span className="text-sm text-red-700">{state.error}</span> : null}
      </div>
      <p className="text-xs text-neutral-500">
        Sending fans out in-app notifications now; device push (FCM) is delivered by the backend
        when Firebase is configured. Never sent to banned/deleted users or archived seed accounts.
      </p>
    </form>
  );
}
