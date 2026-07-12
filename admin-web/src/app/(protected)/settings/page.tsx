import { AdminUserManager } from "@/components/settings/AdminUserManager";
import { ConfigToggle } from "@/components/settings/ConfigToggle";
import { FlagToggle } from "@/components/settings/FlagToggle";
import { can } from "@/lib/auth/permissions";
import { requirePermission } from "@/lib/auth/require-admin";
import { getAppConfig, listAdmins } from "@/lib/dal/admin";
import { listFeatureFlags } from "@/lib/dal/ops";
import { VIOLATION_PRESETS } from "@/lib/moderation/guidelines";

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-neutral-200 bg-white">
      <div className="border-b border-neutral-200 px-4 py-3 text-sm font-semibold">{title}</div>
      <div className="p-4">{children}</div>
    </section>
  );
}

export default async function SettingsPage() {
  const admin = await requirePermission("manage_settings");
  const config = await getAppConfig();
  const flags = await listFeatureFlags();
  const canManageAdmins = can(admin.role, "manage_admin_users");
  const admins = canManageAdmins ? await listAdmins() : [];
  const ipAllowlist = process.env.ADMIN_IP_ALLOWLIST?.trim();

  return (
    <div className="space-y-6">
      <h1 className="text-lg font-semibold">Settings</h1>

      <Card title="Feature configuration">
        <ConfigToggle
          configKey="seed_accounts_enabled"
          label="Seed accounts"
          description="Allow creating seed/studio accounts and posts."
          value={!!config.seed_accounts_enabled}
        />
        <ConfigToggle
          configKey="public_official_badges_enabled"
          label="Official badges"
          description="Show the WTM Studio / Official badge in the app."
          value={!!config.public_official_badges_enabled}
        />
        <ConfigToggle
          configKey="maintenance_mode"
          label="Maintenance mode"
          description="Signal the app/backend to show a maintenance state."
          value={!!config.maintenance_mode}
        />
      </Card>

      <Card title="App feature flags (kill switches — served to the app by /v1/flags)">
        {flags.length === 0 ? (
          <p className="text-sm text-neutral-500">No flags defined.</p>
        ) : (
          flags.map((f) => (
            <FlagToggle
              key={f.key}
              flagKey={f.key}
              description={f.description}
              value={f.enabled}
            />
          ))
        )}
      </Card>

      {canManageAdmins ? (
        <Card title="Admin users (owner only)">
          <AdminUserManager admins={admins} currentUserId={admin.userId} />
        </Card>
      ) : (
        <Card title="Admin users">
          <p className="text-sm text-neutral-500">Only the owner can manage admin users.</p>
        </Card>
      )}

      <Card title="Admin IP allowlist (env-controlled, read-only)">
        {ipAllowlist ? (
          <div className="flex flex-wrap gap-1.5">
            {ipAllowlist.split(",").map((ip) => (
              <span key={ip} className="rounded bg-neutral-100 px-2 py-0.5 font-mono text-xs">
                {ip.trim()}
              </span>
            ))}
          </div>
        ) : (
          <p className="text-sm text-neutral-500">
            No IP allowlist set. Configure <span className="font-mono">ADMIN_IP_ALLOWLIST</span> (or
            Cloudflare Access) to restrict console access by IP.
          </p>
        )}
      </Card>

      <Card title="Guideline → action map">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-neutral-200 text-left text-xs uppercase text-neutral-500">
              <th className="px-2 py-2">Violation</th>
              <th className="px-2 py-2">Suggested action</th>
            </tr>
          </thead>
          <tbody>
            {VIOLATION_PRESETS.map((v) => (
              <tr key={v.label} className="border-t border-neutral-100">
                <td className="px-2 py-2 font-medium">{v.label}</td>
                <td className="px-2 py-2 text-neutral-600">{v.suggested}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
    </div>
  );
}
