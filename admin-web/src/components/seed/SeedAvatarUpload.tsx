"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, useTransition } from "react";

import { setSeedAvatar } from "@/lib/actions/seed";

export function SeedAvatarUpload({ userId, current }: { userId: string; current: string | null }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [err, setErr] = useState<string | null>(null);
  const ref = useRef<HTMLInputElement>(null);

  function onPick(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setErr(null);
    start(async () => {
      const fd = new FormData();
      fd.set("userId", userId);
      fd.set("avatar", file);
      const res = await setSeedAvatar(null, fd);
      if (ref.current) ref.current.value = "";
      if (res.ok) router.refresh();
      else setErr(res.error ?? "Failed.");
    });
  }

  return (
    <div className="flex items-center gap-2">
      {current ? (
        <img src={current} alt="" className="h-9 w-9 rounded-full object-cover" />
      ) : (
        <div className="flex h-9 w-9 items-center justify-center rounded-full bg-neutral-200 text-[10px] text-neutral-400">
          —
        </div>
      )}
      <label className="cursor-pointer text-xs text-neutral-600 hover:underline">
        {pending ? "Uploading…" : current ? "Change" : "Add photo"}
        <input
          ref={ref}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={onPick}
          disabled={pending}
        />
      </label>
      {err ? <span className="text-xs text-red-600">{err}</span> : null}
    </div>
  );
}
