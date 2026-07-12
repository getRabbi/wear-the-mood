import { requirePermission } from "@/lib/auth/require-admin";
import { getAiCostDaily } from "@/lib/dal/ops";
import { fmtDate, fmtNum } from "@/lib/format";

function usd(v: number): string {
  return `$${Number(v).toFixed(2)}`;
}

// AI cost dashboard (CLAUDE.md §14 — cost runaway is risk #1). Rolls up
// ai_usage_log per day/provider: spend, calls, tokens, failures.
export default async function CostsPage() {
  await requirePermission("view_costs");
  const cost = await getAiCostDaily(30);

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-lg font-semibold">AI costs</h1>
        <p className="mt-1 text-sm text-neutral-500">
          Estimated spend from ai_usage_log (last 30 days), per day and provider.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {(
          [
            ["Today", cost.today_usd],
            ["Last 7 days", cost.last7_usd],
            ["Last 30 days", cost.total_usd],
          ] as const
        ).map(([label, v]) => (
          <div key={label} className="rounded-lg border border-neutral-200 bg-white p-4">
            <div className="text-xs text-neutral-500">{label}</div>
            <div className="mt-2 text-2xl font-semibold">{usd(v)}</div>
          </div>
        ))}
      </div>

      <div className="overflow-x-auto rounded-lg border border-neutral-200 bg-white">
        <table className="w-full text-left text-sm">
          <thead className="text-xs text-neutral-500">
            <tr className="border-b border-neutral-200">
              <th className="px-3 py-2 font-medium">Day</th>
              <th className="px-3 py-2 font-medium">Provider</th>
              <th className="px-3 py-2 font-medium">Calls</th>
              <th className="px-3 py-2 font-medium">Tokens (in/out)</th>
              <th className="px-3 py-2 font-medium">Images</th>
              <th className="px-3 py-2 font-medium">Failures</th>
              <th className="px-3 py-2 text-right font-medium">Est. USD</th>
            </tr>
          </thead>
          <tbody>
            {cost.days.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-3 py-8 text-center text-neutral-500">
                  No AI usage in the last 30 days.
                </td>
              </tr>
            ) : (
              cost.days.map((d) => (
                <tr key={`${d.day}-${d.provider}`} className="border-b border-neutral-100 last:border-0">
                  <td className="px-3 py-2 text-xs text-neutral-500">{fmtDate(d.day)}</td>
                  <td className="px-3 py-2">{d.provider || "—"}</td>
                  <td className="px-3 py-2">{fmtNum(d.calls)}</td>
                  <td className="px-3 py-2">
                    {fmtNum(d.input_tokens)}/{fmtNum(d.output_tokens)}
                  </td>
                  <td className="px-3 py-2">{fmtNum(d.images)}</td>
                  <td className={`px-3 py-2 ${d.failures > 0 ? "text-red-700" : ""}`}>
                    {fmtNum(d.failures)}
                  </td>
                  <td className="px-3 py-2 text-right font-medium">{usd(d.est_usd)}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
