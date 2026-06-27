"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import { ModerationActionButton } from "@/components/ModerationActionButton";
import {
  archiveAllSeed,
  deleteAllSeed,
  pauseAllSeed,
  toggleSeedEnabled,
} from "@/lib/actions/seed";

export function SeedToggle({ enabled }: { enabled: boolean }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  function flip() {
    start(async () => {
      const fd = new FormData();
      fd.set("enabled", String(!enabled));
      await toggleSeedEnabled(null, fd);
      router.refresh();
    });
  }
  return (
    <div className="flex items-center gap-3">
      <span
        className={`rounded-full px-2 py-0.5 text-xs font-medium ${
          enabled ? "bg-green-100 text-green-800" : "bg-neutral-200 text-neutral-600"
        }`}
      >
        Seed creation: {enabled ? "ENABLED" : "DISABLED"}
      </span>
      <button
        onClick={flip}
        disabled={pending}
        className="rounded-md border border-neutral-300 px-2.5 py-1 text-xs hover:bg-neutral-100 disabled:opacity-50"
      >
        {enabled ? "Disable" : "Enable"}
      </button>
    </div>
  );
}

export function SeedWinddown({ canDelete }: { canDelete: boolean }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [confirm, setConfirm] = useState("");
  const [delErr, setDelErr] = useState<string | null>(null);

  function pauseAll() {
    if (!window.confirm("Pause ALL active seed accounts?")) return;
    start(async () => {
      await pauseAllSeed();
      router.refresh();
    });
  }

  function deleteAll() {
    setDelErr(null);
    start(async () => {
      const fd = new FormData();
      fd.set("confirm", confirm);
      const res = await deleteAllSeed(null, fd);
      if (res.ok) {
        setConfirm("");
        router.refresh();
      } else {
        setDelErr(res.error ?? "Failed.");
      }
    });
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        <ModerationActionButton
          action={archiveAllSeed}
          payload={{}}
          label="Archive all seed content"
          title="Archive all seed posts"
          defaultReason="Winding down seed content."
        />
        <button
          onClick={pauseAll}
          disabled={pending}
          className="rounded-md border border-neutral-300 px-2.5 py-1 text-xs font-medium hover:bg-neutral-100 disabled:opacity-50"
        >
          Pause all seed accounts
        </button>
      </div>

      {canDelete ? (
        <div className="rounded-md border border-red-200 bg-red-50 p-3">
          <div className="text-xs font-semibold text-red-800">
            Danger — delete ALL seed accounts (owner only)
          </div>
          <p className="mt-1 text-xs text-red-700">
            This permanently deletes every seed account and all their content. Type
            <span className="font-mono"> DELETE ALL SEED </span> to confirm.
          </p>
          <div className="mt-2 flex items-center gap-2">
            <input
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              placeholder="DELETE ALL SEED"
              className="rounded-md border border-red-300 px-2 py-1 text-xs"
            />
            <button
              onClick={deleteAll}
              disabled={pending || confirm !== "DELETE ALL SEED"}
              className="rounded-md bg-red-600 px-2.5 py-1 text-xs font-medium text-white hover:bg-red-700 disabled:opacity-50"
            >
              Delete all
            </button>
          </div>
          {delErr ? <p className="mt-1 text-xs text-red-700">{delErr}</p> : null}
        </div>
      ) : null}
    </div>
  );
}
