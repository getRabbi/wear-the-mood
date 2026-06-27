"use client";

import { useRouter } from "next/navigation";
import { useTransition } from "react";

import { setSeedStatus } from "@/lib/actions/seed";

const btn =
  "rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-50";

export function SeedRowActions({ seedId, status }: { seedId: number; status: string }) {
  const router = useRouter();
  const [pending, start] = useTransition();

  function go(next: string) {
    start(async () => {
      const fd = new FormData();
      fd.set("seedId", String(seedId));
      fd.set("status", next);
      await setSeedStatus(null, fd);
      router.refresh();
    });
  }

  return (
    <div className="flex gap-1.5">
      {status !== "active" ? (
        <button className={btn} disabled={pending} onClick={() => go("active")}>
          Activate
        </button>
      ) : null}
      {status === "active" ? (
        <button className={btn} disabled={pending} onClick={() => go("paused")}>
          Pause
        </button>
      ) : null}
      {status !== "archived" ? (
        <button className={btn} disabled={pending} onClick={() => go("archived")}>
          Archive
        </button>
      ) : null}
    </div>
  );
}
