"use client";

import { useActionState, useEffect, useRef } from "react";

import { createSeedPost, type ActionState } from "@/lib/actions/seed";

const input = "w-full rounded-md border border-neutral-300 px-3 py-2 text-sm";

type Account = { user_id: string; display_name: string | null; username: string | null };

export function SeedPostForm({ accounts, disabled }: { accounts: Account[]; disabled: boolean }) {
  const [state, action, pending] = useActionState<ActionState | null, FormData>(
    createSeedPost,
    null
  );
  const ref = useRef<HTMLFormElement>(null);
  useEffect(() => {
    if (state?.ok) ref.current?.reset();
  }, [state]);

  if (accounts.length === 0) {
    return <p className="text-sm text-neutral-500">Create an active seed account first.</p>;
  }

  return (
    <form ref={ref} action={action} className="space-y-2">
      <select name="seedUserId" required className={input}>
        {accounts.map((a) => (
          <option key={a.user_id} value={a.user_id}>
            {a.display_name || a.username}
          </option>
        ))}
      </select>
      <label className="block text-sm text-neutral-600">
        Look photo (upload)
        <input
          name="imageFile"
          type="file"
          accept="image/*"
          className="mt-1 block w-full text-sm file:mr-3 file:rounded-md file:border-0 file:bg-neutral-900 file:px-3 file:py-1.5 file:text-white"
        />
      </label>
      <input name="imageUrl" placeholder="…or paste an image URL" className={input} />
      <textarea name="caption" rows={2} placeholder="Caption" className={input} />
      <input name="tags" placeholder="tags, comma, separated" className={input} />
      <div className="flex items-center gap-3">
        <button
          type="submit"
          disabled={pending || disabled}
          className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-50"
        >
          {pending ? "Posting…" : "Create seed post"}
        </button>
        {state?.ok ? <span className="text-sm text-green-700">Posted.</span> : null}
        {state && !state.ok ? <span className="text-sm text-red-700">{state.error}</span> : null}
      </div>
    </form>
  );
}
