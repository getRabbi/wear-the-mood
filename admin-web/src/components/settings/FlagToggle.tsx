"use client";

import { useRouter } from "next/navigation";
import { useTransition } from "react";

import { setFeatureFlag } from "@/lib/actions/ops";

// App feature-flag kill switch (feature_flags table — what /v1/flags serves).
// Toggle only; flags are created by migrations, never from the console.
export function FlagToggle({
  flagKey,
  description,
  value,
}: {
  flagKey: string;
  description: string | null;
  value: boolean;
}) {
  const router = useRouter();
  const [pending, start] = useTransition();
  function flip() {
    start(async () => {
      const fd = new FormData();
      fd.set("key", flagKey);
      fd.set("enabled", String(!value));
      await setFeatureFlag(null, fd);
      router.refresh();
    });
  }
  return (
    <div className="flex items-center justify-between gap-4 border-b border-neutral-100 py-3 last:border-0">
      <div>
        <div className="font-mono text-sm font-medium">{flagKey}</div>
        <div className="text-xs text-neutral-500">{description || "—"}</div>
      </div>
      <button
        onClick={flip}
        disabled={pending}
        className={`rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50 ${
          value ? "bg-green-100 text-green-800" : "bg-neutral-200 text-neutral-600"
        }`}
      >
        {value ? "ON" : "OFF"}
      </button>
    </div>
  );
}
