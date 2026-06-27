"use client";

import { useActionState, useEffect, useRef } from "react";

import { createSeedAccount, type ActionState } from "@/lib/actions/seed";
import { SEED_TYPES } from "@/lib/validation/seed";

const input = "w-full rounded-md border border-neutral-300 px-3 py-2 text-sm";

export function SeedAccountForm({ disabled }: { disabled: boolean }) {
  const [state, action, pending] = useActionState<ActionState | null, FormData>(
    createSeedAccount,
    null
  );
  const ref = useRef<HTMLFormElement>(null);
  useEffect(() => {
    if (state?.ok) ref.current?.reset();
  }, [state]);

  return (
    <form ref={ref} action={action} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
      <input name="displayName" required placeholder="Display name (e.g. WTM Studio)" className={input} />
      <input name="username" required placeholder="username (a-z 0-9 _)" className={input} />
      <select name="seedType" defaultValue="studio" className={input}>
        {SEED_TYPES.map((t) => (
          <option key={t} value={t}>
            {t}
          </option>
        ))}
      </select>
      <input name="publicLabel" required defaultValue="WTM Studio" placeholder="Public label" className={input} />
      <textarea
        name="bio"
        rows={2}
        defaultValue="Official outfit inspiration from Wear The Mood."
        placeholder="Bio"
        className={`${input} sm:col-span-2`}
      />
      <label className="text-sm text-neutral-600 sm:col-span-2">
        Profile picture (optional)
        <input
          name="avatar"
          type="file"
          accept="image/*"
          className="mt-1 block w-full text-sm file:mr-3 file:rounded-md file:border-0 file:bg-neutral-900 file:px-3 file:py-1.5 file:text-white"
        />
      </label>
      <div className="flex items-center gap-3 sm:col-span-2">
        <button
          type="submit"
          disabled={pending || disabled}
          className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-50"
        >
          {pending ? "Creating…" : "Create seed account"}
        </button>
        {state?.ok ? <span className="text-sm text-green-700">Created.</span> : null}
        {state && !state.ok ? <span className="text-sm text-red-700">{state.error}</span> : null}
        {disabled ? <span className="text-sm text-amber-700">Seed creation is disabled.</span> : null}
      </div>
    </form>
  );
}
