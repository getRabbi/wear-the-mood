// Placeholder for routes whose functionality lands in a later phase. The route
// exists (so the shell is fully navigable + server-guarded) but is intentionally
// not built yet — keeping to the phase-gated plan.
export function ComingSoon({ title, phase }: { title: string; phase: string }) {
  return (
    <div>
      <h1 className="text-lg font-semibold">{title}</h1>
      <div className="mt-4 rounded-lg border border-dashed border-neutral-300 bg-white p-8 text-sm text-neutral-500">
        This section is built in <span className="font-medium text-neutral-700">{phase}</span>.
      </div>
    </div>
  );
}
