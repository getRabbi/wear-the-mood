import { type NextRequest } from "next/server";

import { can } from "@/lib/auth/permissions";
import { requireAdmin } from "@/lib/auth/require-admin";
import { exportAuditLog } from "@/lib/dal/admin";

// Route handlers are NOT wrapped by the (protected) layout, so we re-verify here.
// Export is restricted to owner/admin (§12.12). Returns CSV.
function csvCell(v: unknown): string {
  const s = v == null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
  return `"${s.replace(/"/g, '""')}"`;
}

export async function GET(req: NextRequest) {
  const admin = await requireAdmin();
  if (!can(admin.role, "manage_settings")) {
    return new Response("Forbidden", { status: 403 });
  }

  const p = req.nextUrl.searchParams;
  const rows = await exportAuditLog({
    action: p.get("action"),
    targetType: p.get("targetType"),
    targetId: p.get("targetId"),
    adminEmail: p.get("adminEmail"),
    from: p.get("from"),
    to: p.get("to"),
  });

  const header = [
    "id",
    "created_at",
    "admin_email",
    "action",
    "target_type",
    "target_id",
    "reason",
    "metadata",
    "before_data",
    "after_data",
  ];
  const lines = [header.join(",")];
  for (const r of rows) {
    lines.push(
      [
        r.id,
        r.created_at,
        r.admin_email,
        r.action,
        r.target_type,
        r.target_id,
        r.reason,
        r.metadata,
        r.before_data,
        r.after_data,
      ]
        .map(csvCell)
        .join(",")
    );
  }

  return new Response(lines.join("\n"), {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="audit-log-${Date.now()}.csv"`,
      "X-Robots-Tag": "noindex, nofollow",
    },
  });
}
