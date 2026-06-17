/// Centralized brand constants — the single source of truth for the app's
/// user-facing product names (CLAUDE.md §1, §4).
///
/// User-facing UI copy flows through localization (`lib/l10n/app_en.arb`) per
/// the l10n rule (§4.3), so screens read these names from `AppLocalizations`,
/// not from here. These constants mirror those canonical names for any
/// non-localized code path (logging, analytics properties, defaults) and so the
/// brand has one place to read. When a name changes, update it BOTH here and in
/// `app_en.arb` (then re-run `flutter gen-l10n`).
abstract class Brand {
  /// The app name shown to users (Android label, app title, splash).
  static const appName = 'Wear The Mood';

  /// The product tagline / subtitle.
  static const tagline = 'Your personal Fashion OS';

  /// The exact premium subscription plan name.
  static const premiumPlanName = 'Fashion OS Premium';

  /// The branded name for the virtual try-on feature.
  static const moodMirrorName = 'MoodMirror';

  /// The standard community/look-card call-to-action.
  static const communityTryCta = 'Try this look';
}
