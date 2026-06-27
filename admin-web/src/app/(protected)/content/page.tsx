import Link from "next/link";

import { requirePermission } from "@/lib/auth/require-admin";

// Content hub — entry point to the post/comment moderation screens.
export default async function ContentPage() {
  await requirePermission("view_content");
  const cards = [
    { href: "/posts", title: "Posts", desc: "Search, hide, restore, or delete community posts." },
    {
      href: "/comments",
      title: "Comments",
      desc: "Search, hide, restore, or delete comments.",
    },
  ];
  return (
    <div className="space-y-4">
      <h1 className="text-lg font-semibold">Content</h1>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {cards.map((c) => (
          <Link
            key={c.href}
            href={c.href}
            className="rounded-lg border border-neutral-200 bg-white p-5 hover:border-neutral-400"
          >
            <div className="text-sm font-semibold">{c.title}</div>
            <div className="mt-1 text-sm text-neutral-500">{c.desc}</div>
          </Link>
        ))}
      </div>
    </div>
  );
}
