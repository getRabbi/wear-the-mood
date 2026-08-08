import {
  AddSourceForm,
  ItemEditor,
  ItemStatusButtons,
  SourceEnabledToggle,
  SourceSyncButton,
} from "@/components/newsroom/NewsroomControls";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { listNewsItems, listNewsSources } from "@/lib/dal/newsroom";

export const dynamic = "force-dynamic";

const STATUS_TONE: Record<string, string> = {
  published: "bg-green-100 text-green-800",
  review_required: "bg-amber-100 text-amber-800",
  draft: "bg-neutral-200 text-neutral-600",
  archived: "bg-neutral-200 text-neutral-500",
};

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-neutral-200 bg-white">
      <div className="border-b border-neutral-200 px-4 py-3 text-sm font-semibold">{title}</div>
      <div className="p-4">{children}</div>
    </section>
  );
}

export default async function NewsroomPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const admin = await requirePermission("view_newsroom");
  const sp = await searchParams;
  // Review queue first: the default view is the work, not the archive.
  const status = sp.status ?? "review_required";
  const [sources, items] = await Promise.all([
    listNewsSources(),
    listNewsItems({ status, sourceId: sp.source, search: sp.q, limit: 50 }),
  ]);
  const canEditItems = can(admin.role, "manage_news_items");
  const canManageSources = can(admin.role, "manage_news_sources");

  return (
    <div className="space-y-6">
      <h1 className="text-lg font-semibold">Newsroom</h1>

      <Card title="Sources">
        <p className="mb-3 text-xs text-neutral-500">
          Only <strong>enabled</strong> sources ingest. A new source is created disabled, and only a
          source explicitly marked trusted publishes without review — everything else lands in the
          queue below.
        </p>
        {sources.length === 0 ? (
          <p className="text-sm text-neutral-500">No sources yet.</p>
        ) : (
          <div className="space-y-2">
            {sources.map((s) => (
              <div
                key={s.id}
                className="flex flex-wrap items-center justify-between gap-3 border-b border-neutral-100 py-2 last:border-0"
              >
                <div>
                  <div className="text-sm font-medium">
                    {s.name}{" "}
                    <span className="font-mono text-xs text-neutral-400">{s.slug}</span>
                  </div>
                  <div className="text-xs text-neutral-500">
                    {s.publisher ?? "—"} · priority {s.priority} · {s.item_count} items ·{" "}
                    {s.pending_review_count} awaiting review
                    {s.consecutive_failures > 0 && (
                      <span className="text-red-700"> · {s.consecutive_failures} failure(s)</span>
                    )}
                  </div>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <span
                    className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${
                      s.health === "ok"
                        ? "bg-green-100 text-green-800"
                        : s.health === "degraded"
                          ? "bg-amber-100 text-amber-800"
                          : "bg-red-100 text-red-800"
                    }`}
                  >
                    {s.health}
                  </span>
                  {s.auto_publish && (
                    <span className="rounded-full bg-violet-100 px-2 py-0.5 text-[11px] font-semibold text-violet-800">
                      trusted
                    </span>
                  )}
                  {canManageSources && <SourceEnabledToggle id={s.id} enabled={s.enabled} />}
                  {canManageSources && s.enabled && (
                    <>
                      <SourceSyncButton id={s.id} dryRun />
                      <SourceSyncButton id={s.id} dryRun={false} />
                    </>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      {canManageSources && (
        <Card title="Add a source">
          <AddSourceForm />
        </Card>
      )}

      <Card title="Items">
        <form className="mb-4 flex flex-wrap gap-2">
          <input
            name="q"
            defaultValue={sp.q ?? ""}
            placeholder="Search headlines"
            className="min-w-56 flex-1 rounded border border-neutral-300 px-2 py-1 text-sm"
          />
          <select
            name="status"
            defaultValue={status}
            className="rounded border border-neutral-300 px-2 py-1 text-sm"
          >
            <option value="review_required">Awaiting review</option>
            <option value="published">Published</option>
            <option value="draft">Draft</option>
            <option value="archived">Archived</option>
            <option value="all">All</option>
          </select>
          <select
            name="source"
            defaultValue={sp.source ?? ""}
            className="rounded border border-neutral-300 px-2 py-1 text-sm"
          >
            <option value="">All sources</option>
            {sources.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
          <button className="rounded bg-neutral-800 px-3 py-1 text-sm font-semibold text-white">
            Filter
          </button>
        </form>

        {items.length === 0 ? (
          <p className="text-sm text-neutral-500">Nothing here.</p>
        ) : (
          <div className="space-y-4">
            {items.map((n) => (
              <article key={n.id} className="border-b border-neutral-100 pb-4 last:border-0">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="text-sm font-semibold">{n.title}</div>
                    <div className="text-xs text-neutral-500">
                      {n.source_name ?? n.source ?? "—"} ·{" "}
                      {(n.published_at ?? n.created_at)?.slice(0, 16).replace("T", " ")}
                    </div>
                    {n.url && (
                      <a
                        href={n.url}
                        target="_blank"
                        rel="noopener noreferrer nofollow"
                        className="break-all text-xs text-blue-700 underline"
                      >
                        {n.url}
                      </a>
                    )}
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    <span
                      className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${
                        STATUS_TONE[n.status] ?? "bg-neutral-200 text-neutral-600"
                      }`}
                    >
                      {n.status}
                    </span>
                    {canEditItems && <ItemStatusButtons id={n.id} status={n.status} />}
                  </div>
                </div>

                {canEditItems ? (
                  <ItemEditor
                    id={n.id}
                    title={n.title}
                    summary={n.summary}
                    attribution={n.attribution}
                  />
                ) : (
                  <p className="mt-2 text-xs text-neutral-600">{n.summary ?? "—"}</p>
                )}
              </article>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
