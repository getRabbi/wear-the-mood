// Coloured pill for an account / content status. Pure render (server-safe).
const STYLES: Record<string, string> = {
  active: "bg-green-100 text-green-800",
  published: "bg-green-100 text-green-800",
  suspended: "bg-amber-100 text-amber-800",
  shadowbanned: "bg-purple-100 text-purple-800",
  banned: "bg-red-100 text-red-800",
  deleted: "bg-neutral-200 text-neutral-600",
  archived: "bg-neutral-200 text-neutral-600",
  hidden: "bg-amber-100 text-amber-800",
};

export function StatusBadge({ status }: { status: string | null | undefined }) {
  const s = (status ?? "unknown").toLowerCase();
  const cls = STYLES[s] ?? "bg-neutral-100 text-neutral-700";
  return (
    <span className={`inline-block rounded-full px-2 py-0.5 text-xs font-medium ${cls}`}>{s}</span>
  );
}
