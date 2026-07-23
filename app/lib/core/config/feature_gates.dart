/// Compile-time feature gates, resolved from `--dart-define` at build time.
///
/// All default to OFF so an un-flagged build — including every already-shipped
/// production build — behaves exactly as before. Flip one on for a build with
/// e.g. `--dart-define=CUTOUT_EDITOR_ENABLED=true`.
library;

/// Free manual Erase/Restore cutout editor (§ BG upgrade Phase 8). When false the
/// "Fix cutout" affordance never renders — no dead button, no empty spacing — so
/// old app versions and un-flagged builds are unchanged. The BACKEND has its own
/// gate (`CUTOUT_EDITOR_ENABLED` env); both must be on for the flow to work end to
/// end, and the editor still handles a backend that returns feature-unavailable.
const bool kCutoutEditorEnabled = bool.fromEnvironment(
  'CUTOUT_EDITOR_ENABLED',
  defaultValue: false,
);
