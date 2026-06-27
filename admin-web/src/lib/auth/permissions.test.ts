import { describe, expect, it } from "vitest";

import { can, ROLES, type Permission } from "@/lib/auth/permissions";

describe("permission matrix", () => {
  it("owner can do everything", () => {
    const perms: Permission[] = [
      "hard_delete_user",
      "manage_admin_users",
      "change_admin_roles",
      "ban_user",
      "adjust_credits",
    ];
    for (const p of perms) expect(can("owner", p)).toBe(true);
  });

  it("every role can view the dashboard", () => {
    for (const r of ROLES) expect(can(r, "view_dashboard")).toBe(true);
  });

  it("support cannot ban/suspend/shadowban users", () => {
    expect(can("support", "ban_user")).toBe(false);
    expect(can("support", "suspend_user")).toBe(false);
    expect(can("support", "shadowban_user")).toBe(false);
  });

  it("moderator can hide posts but not hard-delete or soft-delete users", () => {
    expect(can("moderator", "hide_post")).toBe(true);
    expect(can("moderator", "hard_delete_user")).toBe(false);
    expect(can("moderator", "soft_delete_user")).toBe(false);
  });

  it("only the owner manages admin users + roles", () => {
    expect(can("admin", "manage_admin_users")).toBe(false);
    expect(can("admin", "change_admin_roles")).toBe(false);
    expect(can("owner", "manage_admin_users")).toBe(true);
  });

  it("content_manager cannot view full user data or ban", () => {
    expect(can("content_manager", "view_user_full")).toBe(false);
    expect(can("content_manager", "ban_user")).toBe(false);
    expect(can("content_manager", "manage_seed")).toBe(true);
  });

  it("note-adding is allowed for owner/admin/moderator/support, not content_manager", () => {
    expect(can("owner", "add_note")).toBe(true);
    expect(can("admin", "add_note")).toBe(true);
    expect(can("moderator", "add_note")).toBe(true);
    expect(can("support", "add_note")).toBe(true);
    expect(can("content_manager", "add_note")).toBe(false);
  });
});
