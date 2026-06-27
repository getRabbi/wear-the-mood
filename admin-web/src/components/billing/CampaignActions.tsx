"use client";

import { useRouter } from "next/navigation";
import { useTransition } from "react";

import { cancelCampaign, sendCampaign, type ActionState } from "@/lib/actions/notifications";

const btn =
  "rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-50";

export function CampaignActions({ id, status }: { id: number; status: string }) {
  const router = useRouter();
  const [pending, start] = useTransition();

  function run(fn: (p: ActionState | null, fd: FormData) => Promise<ActionState>) {
    start(async () => {
      const fd = new FormData();
      fd.set("campaignId", String(id));
      await fn(null, fd);
      router.refresh();
    });
  }

  if (status !== "draft" && status !== "scheduled") return null;

  return (
    <div className="flex gap-1.5">
      <button
        className={`${btn} border-neutral-900 bg-neutral-900 text-white hover:bg-neutral-800`}
        disabled={pending}
        onClick={() => {
          if (window.confirm("Send this campaign now?")) run(sendCampaign);
        }}
      >
        Send now
      </button>
      <button className={btn} disabled={pending} onClick={() => run(cancelCampaign)}>
        Cancel
      </button>
    </div>
  );
}
