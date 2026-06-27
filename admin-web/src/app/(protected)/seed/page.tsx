import { SeedAccountForm } from "@/components/seed/SeedAccountForm";
import { SeedAvatarUpload } from "@/components/seed/SeedAvatarUpload";
import { SeedToggle, SeedWinddown } from "@/components/seed/SeedControls";
import { SeedFeed } from "@/components/seed/SeedFeed";
import { SeedPostForm } from "@/components/seed/SeedPostForm";
import { SeedProfileEditor } from "@/components/seed/SeedProfileEditor";
import { SeedRowActions } from "@/components/seed/SeedRowActions";
import { StatusBadge } from "@/components/StatusBadge";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { listPosts } from "@/lib/dal/content";
import { getSeedEnabled, listSeedAccounts } from "@/lib/dal/seed";
import { fmtNum } from "@/lib/format";

const WARNING =
  "Seed accounts are official Wear The Mood studio/inspiration accounts used to " +
  "populate launch content. They must not impersonate real users or create fake engagement.";

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-neutral-200 bg-white">
      <div className="border-b border-neutral-200 px-4 py-3 text-sm font-semibold">{title}</div>
      <div className="p-4">{children}</div>
    </section>
  );
}

export default async function SeedPage() {
  const admin = await requirePermission("manage_seed");
  const [enabled, list, seedPosts] = await Promise.all([
    getSeedEnabled(),
    listSeedAccounts({}),
    listPosts({ seed: true, limit: 24 }),
  ]);
  const active = list.rows.filter((r) => r.status === "active");
  const canCreatePost = can(admin.role, "create_seed_posts");
  const canArchiveAll = can(admin.role, "archive_all_seed");
  const canDelete = can(admin.role, "delete_seed");

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-lg font-semibold">Seed / Studio</h1>
        <SeedToggle enabled={enabled} />
      </div>

      <div className="rounded-md bg-blue-50 px-4 py-3 text-sm text-blue-900">{WARNING}</div>

      <Card title="Create seed account">
        <p className="mb-3 text-xs text-neutral-500">
          Create as many as you like — the form clears after each one (each needs a unique username).
        </p>
        <SeedAccountForm disabled={!enabled} />
      </Card>

      {canCreatePost ? (
        <Card title="Compose seed post (look)">
          <SeedPostForm
            accounts={active.map((a) => ({
              user_id: a.user_id,
              display_name: a.display_name,
              username: a.username,
            }))}
            disabled={!enabled}
          />
        </Card>
      ) : null}

      <Card title={`Seed accounts (${fmtNum(list.total)})`}>
        {list.rows.length === 0 ? (
          <p className="text-sm text-neutral-500">No seed accounts yet.</p>
        ) : (
          <div className="space-y-3">
            {list.rows.map((r) => (
              <div key={r.id} className="rounded-lg border border-neutral-200 p-3">
                <div className="flex flex-wrap items-start gap-3">
                  <SeedAvatarUpload userId={r.user_id} current={r.profile_picture_url} />
                  <div className="min-w-0 grow">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-medium">{r.display_name}</span>
                      <StatusBadge status={r.status} />
                      <span className="rounded bg-blue-50 px-1.5 py-0.5 text-[10px] text-blue-700">
                        {r.public_label}
                      </span>
                    </div>
                    <div className="text-xs text-neutral-500">
                      @{r.username} · {r.seed_type} · {fmtNum(r.post_count)} posts
                    </div>
                  </div>
                  <SeedRowActions seedId={r.id} status={r.status} />
                </div>
                <div className="mt-2">
                  <SeedProfileEditor row={r} />
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      {canCreatePost ? (
        <Card title="Seed feed — engage as studio accounts">
          <SeedFeed
            accounts={active.map((a) => ({
              user_id: a.user_id,
              display_name: a.display_name,
              username: a.username,
            }))}
            posts={seedPosts.rows.map((p) => ({
              id: p.id,
              caption: p.caption,
              image_url: p.image_url,
              author_name: p.author_name,
              like_count: p.like_count,
              comment_count: p.comment_count,
            }))}
          />
        </Card>
      ) : null}

      {canArchiveAll || canDelete ? (
        <Card title="Winddown">
          <SeedWinddown canDelete={canDelete} />
        </Card>
      ) : null}
    </div>
  );
}
