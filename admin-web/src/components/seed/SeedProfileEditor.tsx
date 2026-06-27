"use client";

import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import { updateSeedProfile, type ActionState } from "@/lib/actions/seed";

type SeedRow = {
  user_id: string;
  display_name: string | null;
  username: string | null;
  public_label: string | null;
  bio: string | null;
  style_tags: string[] | null;
};

const input = "w-full rounded-md border border-neutral-300 px-3 py-2 text-sm";

export function SeedProfileEditor({ row }: { row: SeedRow }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState<ActionState | null, FormData>(
    updateSeedProfile,
    null
  );

  // Close + refresh after a successful save (effect, not during render).
  useEffect(() => {
    if (state?.ok) {
      setOpen(false);
      router.refresh();
    }
  }, [state, router]);

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100"
      >
        Edit profile
      </button>
    );
  }

  return (
    <form action={action} className="mt-2 grid grid-cols-1 gap-2 rounded-md bg-neutral-50 p-3 sm:grid-cols-2">
      <input type="hidden" name="userId" value={row.user_id} />
      <input name="displayName" required defaultValue={row.display_name ?? ""} placeholder="Display name" className={input} />
      <input name="username" required defaultValue={row.username ?? ""} placeholder="username" className={input} />
      <input name="publicLabel" required defaultValue={row.public_label ?? "WTM Studio"} placeholder="Public label" className={input} />
      <input name="styleTags" defaultValue={(row.style_tags ?? []).join(", ")} placeholder="style tags, comma separated" className={input} />
      <textarea name="bio" rows={2} defaultValue={row.bio ?? ""} placeholder="Bio" className={`${input} sm:col-span-2`} />
      <div className="flex items-center gap-2 sm:col-span-2">
        <button type="submit" disabled={pending} className="rounded-md bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-50">
          {pending ? "Saving…" : "Save"}
        </button>
        <button type="button" onClick={() => setOpen(false)} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm hover:bg-neutral-100">
          Cancel
        </button>
        {state && !state.ok ? <span className="text-sm text-red-700">{state.error}</span> : null}
      </div>
    </form>
  );
}
