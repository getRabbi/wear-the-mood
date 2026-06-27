"use client";

import { useRouter } from "next/navigation";
import { useTransition } from "react";

import { setConfig } from "@/lib/actions/admin";

export function ConfigToggle({
  configKey,
  label,
  description,
  value,
}: {
  configKey: string;
  label: string;
  description: string;
  value: boolean;
}) {
  const router = useRouter();
  const [pending, start] = useTransition();
  function flip() {
    start(async () => {
      const fd = new FormData();
      fd.set("key", configKey);
      fd.set("value", String(!value));
      await setConfig(null, fd);
      router.refresh();
    });
  }
  return (
    <div className="flex items-center justify-between gap-4 border-b border-neutral-100 py-3 last:border-0">
      <div>
        <div className="text-sm font-medium">{label}</div>
        <div className="text-xs text-neutral-500">{description}</div>
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
