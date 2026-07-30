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

/// Master switch for local-first background removal — segmenting the garment
/// ON DEVICE (Apple Vision / Google ML Kit) instead of waiting on the Azure
/// BiRefNet worker. When false, Add Garment behaves exactly as it does today:
/// upload → `POST /v1/wardrobe` → queue → BiRefNet → poll → reveal.
///
/// The BACKEND has its own gate (`LOCAL_CUTOUT_UPLOAD_ENABLED`); both must be on.
/// Turning this on alone is safe — the app falls back to the cloud path when the
/// endpoint reports the feature is unavailable.
const bool kLocalBgRemovalEnabled = bool.fromEnvironment(
  'LOCAL_BG_REMOVAL_ENABLED',
  defaultValue: false,
);

/// Per-platform arm for Android (Google ML Kit Subject Segmentation). Gated
/// separately from [kLocalBgIosEnabled] so the rollout can enable one store
/// build at a time (§9 of the rollout runbook). Requires
/// [kLocalBgRemovalEnabled] as well — this alone does nothing.
const bool kLocalBgAndroidEnabled = bool.fromEnvironment(
  'LOCAL_BG_ANDROID_ENABLED',
  defaultValue: false,
);

/// Per-platform arm for iOS (Apple Vision, iOS 17+). See [kLocalBgAndroidEnabled];
/// requires [kLocalBgRemovalEnabled] too. Devices below iOS 17 report themselves
/// unsupported at runtime regardless of this flag and use the cloud fallback.
const bool kLocalBgIosEnabled = bool.fromEnvironment(
  'LOCAL_BG_IOS_ENABLED',
  defaultValue: false,
);

/// INTERNAL BUILDS ONLY — Apple Vision device diagnostics (iOS Phase 3).
///
/// When on, one local cutout can export its own artifacts (the exact source bytes
/// Vision saw, the scaled mask PNG, the cutout PNG and a privacy-safe
/// `result.json`) through the iOS share sheet, and a local failure is surfaced
/// instead of being quietly replaced by the cloud path. That is the only way to
/// prove what Vision actually returns on hardware from a Windows dev machine.
///
/// **This must never be true in an App Store build.** It changes fallback
/// behaviour and adds an export affordance, neither of which belongs in front of
/// real users. It is deliberately NOT wired into the `app_prod_config` env group —
/// only the dedicated internal workflow overrides it (see `codemagic.yaml`,
/// `ios-internal-diagnostic`).
///
/// Note the asymmetry with the gates above, which `codemagic.yaml` REQUIRES to be
/// stated explicitly so a release cannot silently ship them off. This one defaults
/// off and stays off unless a workflow deliberately turns it on, because for a
/// diagnostic switch the dangerous accident is silently ON, not silently off.
const bool kLocalBgIosDiagnosticsEnabled = bool.fromEnvironment(
  'LOCAL_BG_IOS_DIAGNOSTICS_ENABLED',
  defaultValue: false,
);
