"use client";

import Link from "next/link";
import { useState } from "react";

import type { AdminIdentity } from "@/lib/auth/require-admin";
import type { ModerationBadges } from "@/lib/dal/reports";
import { can, type Permission } from "@/lib/auth/permissions";
import { SignOutButton } from "@/components/SignOutButton";

type NavItem = {
  label: string;
  href: string;
  permission: Permission;
  phase?: string;
  badge?: keyof ModerationBadges;
};

// Sidebar items, each gated by a capability. Items the role can't access are
// hidden (routes are still server-guarded). `phase` marks not-yet-built pages;
// `badge` shows a live pending count.
const NAV: NavItem[] = [
  { label: "Dashboard", href: "/dashboard", permission: "view_dashboard" },
  { label: "Users", href: "/users", permission: "view_users" },
  { label: "Content", href: "/content", permission: "view_content" },
  { label: "Posts", href: "/posts", permission: "view_content" },
  { label: "Comments", href: "/comments", permission: "view_content" },
  { label: "Reports", href: "/reports", permission: "manage_reports", badge: "reports" },
  { label: "Appeals", href: "/appeals", permission: "manage_appeals", badge: "appeals" },
  { label: "Seed / Studio", href: "/seed", permission: "manage_seed" },
  { label: "Subscriptions", href: "/subscriptions", permission: "view_subscriptions" },
  { label: "Credits", href: "/credits", permission: "adjust_credits" },
  { label: "Notifications", href: "/notifications", permission: "send_push" },
  { label: "Audit Log", href: "/audit-log", permission: "view_audit" },
  { label: "Settings", href: "/settings", permission: "manage_settings" },
];

export function AppShell({
  admin,
  badges,
  children,
}: {
  admin: AdminIdentity;
  badges?: ModerationBadges;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const items = NAV.filter((item) => can(admin.role, item.permission));

  return (
    <div className="min-h-screen bg-neutral-50 text-neutral-900 lg:flex">
      {/* Backdrop on mobile when the drawer is open */}
      {open ? (
        <div
          className="fixed inset-0 z-30 bg-black/40 lg:hidden"
          onClick={() => setOpen(false)}
          aria-hidden
        />
      ) : null}

      {/* Sidebar: slide-in drawer on mobile, static on desktop */}
      <aside
        className={`fixed inset-y-0 left-0 z-40 flex w-64 flex-col border-r border-neutral-200 bg-white transition-transform duration-200 lg:static lg:z-auto lg:w-60 lg:translate-x-0 ${
          open ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        <div className="flex items-center justify-between px-5 py-4">
          <div>
            <div className="text-sm font-semibold tracking-tight">Wear The Mood</div>
            <div className="text-xs text-neutral-500">Ops Console</div>
          </div>
          <button
            type="button"
            onClick={() => setOpen(false)}
            className="rounded-md p-1 text-neutral-500 hover:bg-neutral-100 lg:hidden"
            aria-label="Close menu"
          >
            ✕
          </button>
        </div>
        <nav className="flex-1 space-y-0.5 overflow-y-auto px-3 pb-4">
          {items.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              onClick={() => setOpen(false)}
              className="flex items-center justify-between rounded-md px-3 py-2.5 text-sm text-neutral-700 hover:bg-neutral-100"
            >
              <span>{item.label}</span>
              {item.badge && badges && badges[item.badge] > 0 ? (
                <span className="rounded-full bg-red-600 px-1.5 py-0.5 text-[10px] font-semibold text-white">
                  {badges[item.badge]}
                </span>
              ) : item.phase ? (
                <span className="rounded bg-neutral-100 px-1.5 py-0.5 text-[10px] text-neutral-400">
                  {item.phase}
                </span>
              ) : null}
            </Link>
          ))}
        </nav>
        <div className="border-t border-neutral-200 px-5 py-3 text-[11px] text-neutral-400">
          role: <span className="font-medium text-neutral-600">{admin.role}</span>
        </div>
      </aside>

      {/* Main column */}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-20 flex items-center justify-between gap-2 border-b border-neutral-200 bg-white px-4 py-3">
          <div className="flex min-w-0 items-center gap-2">
            <button
              type="button"
              onClick={() => setOpen(true)}
              className="rounded-md border border-neutral-300 p-1.5 text-neutral-700 hover:bg-neutral-100 lg:hidden"
              aria-label="Open menu"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <line x1="3" y1="6" x2="21" y2="6" />
                <line x1="3" y1="12" x2="21" y2="12" />
                <line x1="3" y1="18" x2="21" y2="18" />
              </svg>
            </button>
            <div className="truncate text-sm text-neutral-500">{admin.email}</div>
          </div>
          <SignOutButton />
        </header>
        <main className="flex-1 overflow-x-hidden p-4 sm:p-6">{children}</main>
      </div>
    </div>
  );
}
