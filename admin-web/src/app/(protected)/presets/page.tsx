import { PresetEditor } from "@/components/ops/PresetEditor";
import { requirePermission } from "@/lib/auth/require-admin";
import { listModelPresets } from "@/lib/dal/ops";

// Try-on model presets (0033–0035): studio mannequins + catalog styles. These
// were previously managed by hand-SQL on the droplet; every edit/activation is
// audited and activation refuses a preset without a real image.
export default async function PresetsPage() {
  await requirePermission("manage_presets");
  const presets = await listModelPresets();
  const studio = presets.filter((p) => p.kind === "studio_tryon");
  const catalog = presets.filter((p) => p.kind === "catalog");

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-lg font-semibold">Try-on model presets</h1>
        <p className="mt-1 text-sm text-neutral-500">
          Inactive presets are invisible in the app. A preset can only be activated once it has a
          hosted image; activating it makes it selectable in the try-on body picker (studio) or
          catalog shot (catalog) immediately.
        </p>
      </div>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold">Studio mannequins ({studio.length})</h2>
        {studio.map((p) => (
          <PresetEditor key={p.id} preset={p} />
        ))}
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold">Catalog styles ({catalog.length})</h2>
        {catalog.map((p) => (
          <PresetEditor key={p.id} preset={p} />
        ))}
      </section>
    </div>
  );
}
