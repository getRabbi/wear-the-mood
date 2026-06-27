"use client";

import { useActionState } from "react";

import { adjustCredits, type ActionState } from "@/lib/actions/credits";

export function CreditAdjustForm({ userId }: { userId: string }) {
  const [state, action, pending] = useActionState<ActionState | null, FormData>(adjustCredits, null);
  return (
    <form action={action} className="flex flex-wrap items-end gap-2">
      <input type="hidden" name="userId" value={userId} />
      <input
        name="amount"
        type="number"
        required
        placeholder="+grant / -deduct"
        className="w-36 rounded-md border border-neutral-300 px-3 py-2 text-sm"
      />
      <input
        name="reason"
        required
        placeholder="Reason (e.g. comp for failed try-on)"
        className="min-w-64 grow rounded-md border border-neutral-300 px-3 py-2 text-sm"
      />
      <button
        type="submit"
        disabled={pending}
        className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-50"
      >
        {pending ? "Applying…" : "Apply"}
      </button>
      {state?.ok ? <span className="text-sm text-green-700">Applied.</span> : null}
      {state && !state.ok ? <span className="text-sm text-red-700">{state.error}</span> : null}
    </form>
  );
}
