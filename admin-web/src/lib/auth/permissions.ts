// Role / permission matrix (BUILD_PROMPT_ADMIN_PANEL_PERFECT_FINAL.md §6).
// The SINGLE source of truth for "who can do what". Re-checked server-side in
// every Server Action / Route Handler / DAL function from later phases — never
// trusted from the client. "limited" / "if approved" nuances from the spec table
// are enforced per-action in the relevant phase; here a role is granted if it has
// ANY access to the capability.

export const ROLES = ["owner", "admin", "moderator", "support", "content_manager"] as const;
export type Role = (typeof ROLES)[number];

export type Permission =
  | "view_dashboard"
  | "view_users"
  | "view_user_full"
  | "add_note"
  | "suspend_user"
  | "ban_user"
  | "shadowban_user"
  | "restore_user"
  | "soft_delete_user"
  | "hard_delete_user"
  | "view_content"
  | "hide_post"
  | "delete_post"
  | "update_post"
  | "hide_comment"
  | "delete_comment"
  | "moderate_giveaways"
  | "review_chats"
  | "moderate_ai_images"
  | "manage_presets"
  | "view_costs"
  | "manage_reports"
  | "manage_appeals"
  | "manage_seed"
  | "create_seed_posts"
  | "archive_all_seed"
  | "delete_seed"
  | "send_push"
  | "adjust_credits"
  | "view_subscriptions"
  | "trigger_refunds"
  | "view_audit"
  | "manage_settings"
  | "manage_admin_users"
  | "change_admin_roles"
  // Catalog + automation (0057-0059). Split viewing from mutating, and
  // mutating the CATALOG from mutating a MERCHANT: editing a product is
  // day-to-day merchandising, while approving a merchant or enabling its feed
  // decides what the importer is allowed to pull and who gets paid.
  | "view_catalog"
  | "manage_products"
  | "manage_merchants"
  | "run_product_sync"
  // Newsroom. Publishing is editorial; trusting a SOURCE to auto-publish is a
  // standing decision about what can reach the app unreviewed, so it sits with
  // the higher bar.
  | "view_newsroom"
  | "manage_news_items"
  | "manage_news_sources";

// Which roles hold each permission. (owner holds everything by construction.)
const MATRIX: Record<Permission, Role[]> = {
  view_dashboard: ["owner", "admin", "moderator", "support", "content_manager"],
  view_users: ["owner", "admin", "moderator", "support", "content_manager"],
  view_user_full: ["owner", "admin", "moderator", "support"],
  add_note: ["owner", "admin", "moderator", "support"],
  suspend_user: ["owner", "admin", "moderator"],
  ban_user: ["owner", "admin", "moderator"],
  shadowban_user: ["owner", "admin", "moderator"],
  restore_user: ["owner", "admin", "moderator"],
  soft_delete_user: ["owner", "admin"],
  hard_delete_user: ["owner"],
  view_content: ["owner", "admin", "moderator", "support", "content_manager"],
  hide_post: ["owner", "admin", "moderator"],
  delete_post: ["owner", "admin", "moderator"],
  update_post: ["owner", "admin", "moderator", "content_manager"],
  hide_comment: ["owner", "admin", "moderator"],
  delete_comment: ["owner", "admin", "moderator"],
  // Giveaway listings are public UGC → same bar as posts. Pickup-chat
  // transcripts are PRIVATE messages (§10) → moderation roles only, no support.
  moderate_giveaways: ["owner", "admin", "moderator"],
  review_chats: ["owner", "admin", "moderator"],
  moderate_ai_images: ["owner", "admin", "moderator"],
  // Presets are ops-owned content (like seed); costs are financial (owner/admin).
  manage_presets: ["owner", "admin", "content_manager"],
  view_costs: ["owner", "admin"],
  manage_reports: ["owner", "admin", "moderator", "support"],
  manage_appeals: ["owner", "admin", "moderator", "support"],
  manage_seed: ["owner", "admin", "content_manager"],
  create_seed_posts: ["owner", "admin", "content_manager"],
  archive_all_seed: ["owner", "admin"],
  delete_seed: ["owner"],
  send_push: ["owner", "admin", "content_manager"],
  adjust_credits: ["owner", "admin", "support"],
  view_subscriptions: ["owner", "admin", "support"],
  trigger_refunds: ["owner", "admin"],
  view_audit: ["owner", "admin", "moderator"],
  manage_settings: ["owner", "admin"],
  manage_admin_users: ["owner"],
  change_admin_roles: ["owner"],

  // Catalog. content_manager merchandises — searches, edits, publishes a
  // product, picks its try-on image — but cannot approve a merchant or enable
  // its feed, because that decides what gets imported and which affiliate
  // account earns. support/moderator can look but not touch: a sold-out
  // product is a common support question and reading it should not need admin.
  view_catalog: ["owner", "admin", "content_manager", "moderator", "support"],
  manage_products: ["owner", "admin", "content_manager"],
  manage_merchants: ["owner", "admin"],
  // Triggering a sync spends someone else's rate limit and can move the whole
  // catalog, so it is not merchandising.
  run_product_sync: ["owner", "admin"],

  // Newsroom. content_manager is the editor: reviews, edits and publishes
  // items. Trusting a SOURCE to publish unreviewed is a standing decision
  // about what reaches the app without a human, and stays with admin.
  view_newsroom: ["owner", "admin", "content_manager", "moderator"],
  manage_news_items: ["owner", "admin", "content_manager"],
  manage_news_sources: ["owner", "admin"],
};

export function can(role: Role, permission: Permission): boolean {
  if (role === "owner") return true;
  return MATRIX[permission]?.includes(role) ?? false;
}
