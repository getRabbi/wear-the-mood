import Link from "next/link";
import { notFound } from "next/navigation";

import { AddNoteForm } from "@/components/AddNoteForm";
import { ModerationActionButton } from "@/components/ModerationActionButton";
import { StatusBadge } from "@/components/StatusBadge";
import {
  banUser,
  restoreUser,
  shadowbanUser,
  softDeleteUser,
  suspendUser,
} from "@/lib/actions/moderation";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { listUserTryonJobs } from "@/lib/dal/ops";
import { getUserDetail } from "@/lib/dal/users";
import { fmtDate, fmtNum } from "@/lib/format";

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <div className="text-xs text-neutral-500">{label}</div>
      <div className="text-sm">{value ?? "—"}</div>
    </div>
  );
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-neutral-200 bg-white">
      <div className="border-b border-neutral-200 px-4 py-3 text-sm font-semibold">{title}</div>
      <div className="p-4">{children}</div>
    </section>
  );
}

export default async function UserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const admin = await requirePermission("view_users");
  const { id } = await params;
  const detail = await getUserDetail(id);
  if (!detail || !detail.profile) notFound();

  const p = detail.profile;
  const c = detail.counts;
  const canNote = can(admin.role, "add_note");
  const tryonJobs = await listUserTryonJobs(id, 10);
  const mod = {
    suspend: can(admin.role, "suspend_user"),
    ban: can(admin.role, "ban_user"),
    shadowban: can(admin.role, "shadowban_user"),
    restore: can(admin.role, "restore_user"),
    softDelete: can(admin.role, "soft_delete_user"),
  };
  const canModerate = Object.values(mod).some(Boolean);
  const uid = { userId: p.user_id };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold">{p.display_name || p.username || "User"}</h1>
          <p className="text-sm text-neutral-500">{p.email}</p>
        </div>
        <div className="flex items-center gap-2">
          <StatusBadge status={p.account_status} />
          <Link href="/users" className="text-sm text-neutral-500 hover:underline">
            ← Back to users
          </Link>
        </div>
      </div>

      {canModerate ? (
        <section className="rounded-lg border border-neutral-200 bg-white px-4 py-3">
          <div className="mb-2 text-sm font-semibold">Moderation</div>
          <div className="flex flex-wrap items-center gap-2">
            {mod.suspend ? (
              <ModerationActionButton
                action={suspendUser}
                payload={uid}
                label="Suspend"
                title="Suspend user"
                withPresets
              />
            ) : null}
            {mod.shadowban ? (
              <ModerationActionButton
                action={shadowbanUser}
                payload={uid}
                label="Shadowban"
                title="Shadowban user"
                withPresets
              />
            ) : null}
            {mod.ban ? (
              <ModerationActionButton
                action={banUser}
                payload={uid}
                label="Ban"
                title="Ban user"
                danger
                withPresets
              />
            ) : null}
            {mod.restore ? (
              <ModerationActionButton
                action={restoreUser}
                payload={uid}
                label="Restore"
                title="Restore user to active"
                defaultReason="Restored after review."
              />
            ) : null}
            {mod.softDelete ? (
              <ModerationActionButton
                action={softDeleteUser}
                payload={uid}
                label="Soft delete"
                title="Soft delete / anonymize user"
                danger
              />
            ) : null}
          </div>
        </section>
      ) : null}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <Card title="Profile">
          <div className="grid grid-cols-2 gap-3">
            <Field label="User ID" value={<span className="break-all font-mono text-xs">{p.user_id}</span>} />
            <Field label="Username" value={p.username} />
            <Field label="Account status" value={<StatusBadge status={p.account_status} />} />
            <Field label="Joined" value={fmtDate(p.created_at)} />
            <Field label="Ban reason" value={p.ban_reason} />
            <Field label="Banned until" value={fmtDate(p.banned_until)} />
            <Field label="Seed / official" value={p.is_seed ? p.public_label || "seed" : "no"} />
            <Field label="Timezone" value={p.timezone} />
          </div>
          {p.bio ? <p className="mt-3 text-sm text-neutral-600">{p.bio}</p> : null}
        </Card>

        <Card title="Subscription & credits">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Tier" value={detail.subscription?.tier ?? "free"} />
            <Field label="Sub status" value={detail.subscription?.status ?? "—"} />
            <Field label="Renews / ends" value={fmtDate(detail.subscription?.current_period_end)} />
            <Field label="Credits (total)" value={fmtNum(detail.credits?.total ?? 0)} />
            <Field label="Plan balance" value={fmtNum(detail.credits?.balance ?? 0)} />
            <Field label="Top-up balance" value={fmtNum(detail.credits?.topup_balance ?? 0)} />
          </div>
        </Card>

        <Card title="Activity">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Posts" value={fmtNum(c.post_count)} />
            <Field label="Comments" value={fmtNum(c.comment_count)} />
            <Field label="Followers" value={fmtNum(c.follower_count)} />
            <Field label="Following" value={fmtNum(c.following_count)} />
            <Field label="Reports against" value={fmtNum(c.reports_against)} />
            <Field label="Reports filed" value={fmtNum(c.reports_by)} />
          </div>
        </Card>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <Card title="Recent posts">
          {detail.recent_posts.length === 0 ? (
            <p className="text-sm text-neutral-500">No posts.</p>
          ) : (
            <ul className="space-y-2 text-sm">
              {detail.recent_posts.map((post) => (
                <li key={post.id} className="flex items-center justify-between gap-3">
                  <span className="truncate">{post.caption || "(no caption)"}</span>
                  <span className="flex shrink-0 items-center gap-2 text-xs text-neutral-500">
                    <StatusBadge status={post.status} />
                    {fmtDate(post.created_at)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card title="Recent comments">
          {detail.recent_comments.length === 0 ? (
            <p className="text-sm text-neutral-500">No comments.</p>
          ) : (
            <ul className="space-y-2 text-sm">
              {detail.recent_comments.map((cm) => (
                <li key={cm.id} className="flex items-center justify-between gap-3">
                  <span className="truncate">{cm.body}</span>
                  <span className="flex shrink-0 items-center gap-2 text-xs text-neutral-500">
                    <StatusBadge status={cm.status} />
                    {fmtDate(cm.created_at)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <Card title="Recent try-on jobs (credit disputes)">
        {tryonJobs.length === 0 ? (
          <p className="text-sm text-neutral-500">No try-on jobs.</p>
        ) : (
          <ul className="space-y-1 text-sm">
            {tryonJobs.map((j) => (
              <li key={j.id} className="flex items-center justify-between gap-3">
                <span className="min-w-0 truncate">
                  <span className="font-mono text-xs">{j.id.slice(0, 8)}…</span> ·{" "}
                  {j.model_source}
                  {j.hd ? " · HD" : ""}
                  {j.error ? <span className="ml-1 text-red-700">{j.error}</span> : null}
                </span>
                <span className="flex shrink-0 items-center gap-2 text-xs text-neutral-500">
                  <StatusBadge status={j.status} />
                  {fmtDate(j.created_at)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card title="Reports against this user">
        {detail.reports_against_list.length === 0 ? (
          <p className="text-sm text-neutral-500">No reports.</p>
        ) : (
          <ul className="space-y-1 text-sm">
            {detail.reports_against_list.map((r) => (
              <li key={r.id} className="flex items-center justify-between">
                <span>
                  {r.reason || "—"} <span className="text-neutral-500">({r.subject_type})</span>
                </span>
                <span className="text-xs text-neutral-500">
                  {r.status} · {fmtDate(r.created_at)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card title="Admin notes">
        {canNote ? (
          <div className="mb-4">
            <AddNoteForm targetId={p.user_id} />
          </div>
        ) : null}
        {detail.notes.length === 0 ? (
          <p className="text-sm text-neutral-500">No notes yet.</p>
        ) : (
          <ul className="space-y-3 text-sm">
            {detail.notes.map((n) => (
              <li key={n.id} className="border-l-2 border-neutral-200 pl-3">
                <div>{n.note}</div>
                <div className="text-xs text-neutral-500">
                  {n.created_by_email || "admin"} · {fmtDate(n.created_at)}
                </div>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card title="Audit history">
        {detail.audit.length === 0 ? (
          <p className="text-sm text-neutral-500">No admin actions on this user.</p>
        ) : (
          <ul className="space-y-1 text-sm">
            {detail.audit.map((a) => (
              <li key={a.id} className="flex items-center justify-between">
                <span>
                  <span className="font-medium">{a.action}</span>
                  {a.reason ? <span className="text-neutral-500"> — {a.reason}</span> : null}
                </span>
                <span className="text-xs text-neutral-500">
                  {a.admin_email} · {fmtDate(a.created_at)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
