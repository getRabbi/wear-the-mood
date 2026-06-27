"use client";

import { useActionState, useEffect, useRef } from "react";

import { addUserNote, type ActionState } from "@/lib/actions/notes";

export function AddNoteForm({ targetId }: { targetId: string }) {
  const [state, formAction, pending] = useActionState<ActionState | null, FormData>(
    addUserNote,
    null
  );
  const formRef = useRef<HTMLFormElement>(null);

  // Clear the textarea after a successful save.
  useEffect(() => {
    if (state?.ok) formRef.current?.reset();
  }, [state]);

  return (
    <form ref={formRef} action={formAction} className="space-y-2">
      <input type="hidden" name="targetType" value="user" />
      <input type="hidden" name="targetId" value={targetId} />
      <textarea
        name="note"
        required
        rows={3}
        maxLength={2000}
        placeholder="Add an internal note about this user…"
        className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-500"
      />
      <div className="flex items-center gap-3">
        <button
          type="submit"
          disabled={pending}
          className="rounded-md bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-50"
        >
          {pending ? "Saving…" : "Add note"}
        </button>
        {state?.ok ? <span className="text-sm text-green-700">Saved.</span> : null}
        {state && !state.ok ? (
          <span className="text-sm text-red-700">{state.error}</span>
        ) : null}
      </div>
    </form>
  );
}
