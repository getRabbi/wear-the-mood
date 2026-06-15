import '../../l10n/app_localizations.dart';

/// Which try-on engine the user runs — the two are completely separate in logic,
/// credit handling and result mode (feat/separate-2d-tryon-engine).
///
/// - [twoD]: a FREE, on-device image composite. Never calls the AI endpoint and
///   never spends credits. Result records store mode `2d`.
/// - [aiRealistic]: the existing server-side AI render, gated on premium / AI
///   credits. Result records store mode `ai_realistic`.
enum TryOnMode { twoD, aiRealistic }

extension TryOnModeX on TryOnMode {
  /// Stable id persisted on a result record.
  String get id => switch (this) {
    TryOnMode.twoD => '2d',
    TryOnMode.aiRealistic => 'ai_realistic',
  };

  bool get isTwoD => this == TryOnMode.twoD;
  bool get isAi => this == TryOnMode.aiRealistic;

  /// The Generate button label for this mode.
  String generateLabel(AppLocalizations l) =>
      isTwoD ? l.tryOnGenerate2d : l.tryOnGenerateAi;

  /// The result-screen title for this mode.
  String resultTitle(AppLocalizations l) =>
      isTwoD ? l.tryOn2dResultTitle : l.tryOnResultTitle;
}
