"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import { seedComment, seedLike } from "@/lib/actions/seed";

type Account = { user_id: string; display_name: string | null; username: string | null };
type Post = {
  id: string;
  caption: string | null;
  image_url: string | null;
  author_name: string | null;
  like_count: number;
  comment_count: number;
};

export function SeedFeed({ accounts, posts }: { accounts: Account[]; posts: Post[] }) {
  const router = useRouter();
  const [actor, setActor] = useState(accounts[0]?.user_id ?? "");
  const [pending, start] = useTransition();
  const [text, setText] = useState<Record<string, string>>({});

  if (accounts.length === 0) return <p className="text-sm text-neutral-500">Create an active seed account first.</p>;
  if (posts.length === 0) return <p className="text-sm text-neutral-500">No seed posts yet — compose one above.</p>;

  function like(postId: string) {
    start(async () => {
      const fd = new FormData();
      fd.set("seedUserId", actor);
      fd.set("postId", postId);
      fd.set("like", "true");
      await seedLike(null, fd);
      router.refresh();
    });
  }

  function comment(postId: string) {
    const body = (text[postId] ?? "").trim();
    if (!body) return;
    start(async () => {
      const fd = new FormData();
      fd.set("seedUserId", actor);
      fd.set("postId", postId);
      fd.set("body", body);
      const res = await seedComment(null, fd);
      if (res.ok) {
        setText((s) => ({ ...s, [postId]: "" }));
        router.refresh();
      }
    });
  }

  return (
    <div>
      <label className="text-sm text-neutral-600">
        Act as:{" "}
        <select
          value={actor}
          onChange={(e) => setActor(e.target.value)}
          className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm"
        >
          {accounts.map((a) => (
            <option key={a.user_id} value={a.user_id}>
              {a.display_name || a.username}
            </option>
          ))}
        </select>
      </label>
      <p className="mt-1 text-xs text-neutral-500">
        Seed accounts can only like/comment on OTHER seed posts (kept compliant — never on real users).
      </p>

      <div className="mt-3 space-y-3">
        {posts.map((p) => (
          <div key={p.id} className="flex gap-3 rounded-lg border border-neutral-200 p-3">
            {p.image_url ? (
              <img src={p.image_url} alt="" className="h-16 w-16 shrink-0 rounded object-cover" />
            ) : (
              <div className="h-16 w-16 shrink-0 rounded bg-neutral-100" />
            )}
            <div className="min-w-0 flex-1">
              <div className="text-xs text-neutral-500">{p.author_name}</div>
              <div className="truncate text-sm">{p.caption || "(no caption)"}</div>
              <div className="mt-0.5 text-xs text-neutral-500">
                ♥ {p.like_count} · 💬 {p.comment_count}
              </div>
              <div className="mt-2 flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  onClick={() => like(p.id)}
                  disabled={pending}
                  className="rounded border border-neutral-300 px-2.5 py-1 text-xs hover:bg-neutral-100 disabled:opacity-50"
                >
                  ♥ Like
                </button>
                <input
                  value={text[p.id] ?? ""}
                  onChange={(e) => setText((s) => ({ ...s, [p.id]: e.target.value }))}
                  placeholder="Comment as seed…"
                  className="min-w-40 grow rounded-md border border-neutral-300 px-2 py-1 text-xs"
                />
                <button
                  type="button"
                  onClick={() => comment(p.id)}
                  disabled={pending}
                  className="rounded-md bg-neutral-900 px-2.5 py-1 text-xs font-medium text-white hover:bg-neutral-800 disabled:opacity-50"
                >
                  Send
                </button>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
