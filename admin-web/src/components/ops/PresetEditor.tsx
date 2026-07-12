"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";

import { setPresetActive, updateModelPreset } from "@/lib/actions/ops";
import type { ModelPresetRow } from "@/lib/dal/ops";

// Edit + activate one try-on model preset. Activation is guarded server-side:
// a preset with no image can never go live (0035/0040).
export function PresetEditor({ preset }: { preset: ModelPresetRow }) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  function toggleActive() {
    setError(null);
    start(async () => {
      const fd = new FormData();
      fd.set("presetId", preset.id);
      fd.set("active", String(!preset.is_active));
      const res = await setPresetActive(null, fd);
      if (!res.ok) setError(res.error ?? "Failed.");
      else router.refresh();
    });
  }

  function save(formData: FormData) {
    setError(null);
    start(async () => {
      formData.set("presetId", preset.id);
      const res = await updateModelPreset(null, formData);
      if (!res.ok) setError(res.error ?? "Failed.");
      else {
        setEditing(false);
        router.refresh();
      }
    });
  }

  return (
    <div className="rounded-lg border border-neutral-200 bg-white p-3">
      <div className="flex gap-4">
        {preset.image_url ? (
          <img src={preset.image_url} alt="" className="h-24 w-16 shrink-0 rounded-md object-cover" />
        ) : (
          <div className="flex h-24 w-16 shrink-0 items-center justify-center rounded-md bg-neutral-100 text-center text-[10px] text-neutral-400">
            no image
          </div>
        )}
        <div className="min-w-0 grow">
          <div className="flex items-center gap-2">
            <span className="text-sm font-medium">{preset.name}</span>
            <span className="rounded bg-neutral-100 px-1.5 py-0.5 text-[10px] text-neutral-600">
              {preset.kind}
            </span>
            {preset.style ? (
              <span className="font-mono text-[10px] text-neutral-400">{preset.style}</span>
            ) : null}
          </div>
          <div className="mt-0.5 text-xs text-neutral-500">
            sort {preset.sort_order} · {preset.is_pro_only ? "pro only" : "all tiers"}
          </div>
          {error ? <div className="mt-1 text-xs text-red-700">{error}</div> : null}
        </div>
        <div className="flex shrink-0 flex-col items-end gap-1.5">
          <button
            type="button"
            onClick={toggleActive}
            disabled={pending}
            className={`rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50 ${
              preset.is_active ? "bg-green-100 text-green-800" : "bg-neutral-200 text-neutral-600"
            }`}
          >
            {preset.is_active ? "ACTIVE" : "INACTIVE"}
          </button>
          <button
            type="button"
            onClick={() => setEditing((e) => !e)}
            className="rounded-md border border-neutral-300 px-2.5 py-1 text-xs font-medium text-neutral-700 hover:bg-neutral-100"
          >
            {editing ? "Cancel" : "Edit"}
          </button>
        </div>
      </div>

      {editing ? (
        <form action={save} className="mt-3 grid grid-cols-1 gap-2 border-t border-neutral-100 pt-3 sm:grid-cols-2">
          <label className="text-xs text-neutral-600">
            Name
            <input
              name="name"
              defaultValue={preset.name}
              className="mt-1 w-full rounded-md border border-neutral-300 px-2 py-1.5 text-sm"
            />
          </label>
          <label className="text-xs text-neutral-600">
            Sort order
            <input
              name="sortOrder"
              type="number"
              defaultValue={preset.sort_order}
              className="mt-1 w-full rounded-md border border-neutral-300 px-2 py-1.5 text-sm"
            />
          </label>
          <label className="text-xs text-neutral-600 sm:col-span-2">
            Image URL (https) — or upload below
            <input
              name="imageUrl"
              defaultValue={preset.image_url ?? ""}
              placeholder="https://…"
              className="mt-1 w-full rounded-md border border-neutral-300 px-2 py-1.5 text-sm"
            />
          </label>
          <label className="text-xs text-neutral-600 sm:col-span-2">
            Upload model image (replaces the URL)
            <input name="imageFile" type="file" accept="image/*" className="mt-1 w-full text-sm" />
          </label>
          <div className="sm:col-span-2">
            <button
              type="submit"
              disabled={pending}
              className="rounded-md bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-50"
            >
              {pending ? "Saving…" : "Save preset"}
            </button>
          </div>
        </form>
      ) : null}
    </div>
  );
}
