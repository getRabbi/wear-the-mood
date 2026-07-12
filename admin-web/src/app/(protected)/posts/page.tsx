import Link from "next/link";

import { ModerationActionButton } from "@/components/ModerationActionButton";
import { StatusBadge } from "@/components/StatusBadge";
import { bulkHidePosts, deletePost, hidePost, restorePost } from "@/lib/actions/moderation";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { listPosts } from "@/lib/dal/content";
import { fmtDate, fmtNum } from "@/lib/format";

const PAGE_SIZE = 25;
const STATUSES = ["published", "hidden", "deleted", "archived"];

type SP = { q?: string; status?: string; seed?: string; page?: string };

function qs(base: SP, overrides: Partial<SP>): string {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...base, ...overrides })) {
    if (v != null && v !== "") p.set(k, String(v));
  }
  const s = p.toString();
  return s ? `?${s}` : "";
}

export default async function PostsPage({ searchParams }: { searchParams: Promise<SP> }) {
  const admin = await requirePermission("view_content");
  const sp = await searchParams;
  const page = Math.max(1, parseInt(sp.page ?? "1", 10) || 1);
  const seed = sp.seed === "true" ? true : sp.seed === "false" ? false : null;

  const result = await listPosts({
    search: sp.q ?? null,
    status: sp.status ?? null,
    seed,
    limit: PAGE_SIZE,
    offset: (page - 1) * PAGE_SIZE,
  });
  const totalPages = Math.max(1, Math.ceil(result.total / PAGE_SIZE));
  const canHide = can(admin.role, "hide_post");
  const canDelete = can(admin.role, "delete_post");

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold">Posts</h1>
        <div className="text-sm text-neutral-500">{fmtNum(result.total)} total</div>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-2">
        <input
          type="text"
          name="q"
          defaultValue={sp.q ?? ""}
          placeholder="Search caption / author / post id"
          className="min-w-64 grow rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
        <select name="status" defaultValue={sp.status ?? ""} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="">All statuses</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
        <select name="seed" defaultValue={sp.seed ?? ""} className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          <option value="">All posts</option>
          <option value="true">Seed only</option>
          <option value="false">Real only</option>
        </select>
        <button type="submit" className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800">
          Filter
        </button>
        <Link href="/posts" className="rounded-md border border-neutral-300 px-3 py-2 text-sm hover:bg-neutral-100">
          Reset
        </Link>
      </form>

      <form action={bulkHidePosts} className="space-y-3">
        {result.rows.length === 0 ? (
          <div className="rounded-lg border border-neutral-200 bg-white p-8 text-center text-sm text-neutral-500">
            No posts match these filters.
          </div>
        ) : (
          result.rows.map((post) => (
            <div
              key={post.id}
              className="flex gap-4 rounded-lg border border-neutral-200 bg-white p-3"
            >
              {canHide ? (
                <input
                  type="checkbox"
                  name="ids"
                  value={post.id}
                  className="mt-1 h-4 w-4 shrink-0 self-start"
                  aria-label="Select post"
                />
              ) : null}
              {post.image_url ? (
                <img
                  src={post.image_url}
                  alt=""
                  className="h-20 w-20 shrink-0 rounded-md object-cover"
                />
              ) : (
                <div className="flex h-20 w-20 shrink-0 items-center justify-center rounded-md bg-neutral-100 text-xs text-neutral-400">
                  no image
                </div>
              )}

              <div className="min-w-0 grow">
                <div className="flex items-center gap-2">
                  <StatusBadge status={post.status} />
                  {post.is_seed ? (
                    <span className="rounded bg-blue-50 px-1.5 py-0.5 text-[10px] text-blue-700">
                      seed
                    </span>
                  ) : null}
                  {post.report_count > 0 ? (
                    <span className="rounded bg-red-50 px-1.5 py-0.5 text-[10px] text-red-700">
                      {post.report_count} reports
                    </span>
                  ) : null}
                </div>
                <p className="mt-1 truncate text-sm">{post.caption || "(no caption)"}</p>
                <div className="mt-0.5 text-xs text-neutral-500">
                  by{" "}
                  <Link href={`/users/${post.user_id}`} className="hover:underline">
                    {post.author_name || post.author_username || post.author_email}
                  </Link>{" "}
                  · {fmtNum(post.like_count)} likes · {fmtNum(post.comment_count)} comments ·{" "}
                  {fmtDate(post.created_at)}
                </div>
                {post.moderation_reason ? (
                  <div className="mt-0.5 text-xs text-amber-700">
                    reason: {post.moderation_reason}
                  </div>
                ) : null}
              </div>

              <div className="flex shrink-0 flex-col items-end gap-1.5">
                {canHide && post.status === "published" ? (
                  <ModerationActionButton
                    action={hidePost}
                    payload={{ postId: post.id }}
                    label="Hide"
                    title="Hide post"
                    withPresets
                  />
                ) : null}
                {canHide && post.status !== "published" ? (
                  <ModerationActionButton
                    action={restorePost}
                    payload={{ postId: post.id }}
                    label="Restore"
                    title="Restore post"
                    defaultReason="Restored after review."
                  />
                ) : null}
                {canDelete && post.status !== "deleted" ? (
                  <ModerationActionButton
                    action={deletePost}
                    payload={{ postId: post.id }}
                    label="Delete"
                    title="Delete post"
                    danger
                    withPresets
                  />
                ) : null}
              </div>
            </div>
          ))
        )}

        {canHide && result.rows.length > 0 ? (
          <div className="flex flex-wrap items-center gap-2 rounded-lg border border-neutral-200 bg-white p-3">
            <span className="text-xs text-neutral-500">Bulk (checked rows):</span>
            <input
              type="text"
              name="reason"
              required
              placeholder="Shared reason (required)"
              className="min-w-56 grow rounded-md border border-neutral-300 px-3 py-1.5 text-sm"
            />
            <button
              type="submit"
              className="rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50"
            >
              Hide selected
            </button>
          </div>
        ) : null}
      </form>

      <div className="flex items-center justify-between text-sm">
        <div className="text-neutral-500">
          Page {page} of {totalPages}
        </div>
        <div className="flex gap-2">
          {page > 1 ? (
            <Link href={`/posts${qs(sp, { page: String(page - 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Previous
            </Link>
          ) : null}
          {page < totalPages ? (
            <Link href={`/posts${qs(sp, { page: String(page + 1) })}`} className="rounded-md border border-neutral-300 px-3 py-1.5 hover:bg-neutral-100">
              Next
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
