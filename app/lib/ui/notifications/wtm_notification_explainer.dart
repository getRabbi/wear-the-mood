import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/push/push_messaging.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// One-time "Stay in the loop" notification explainer (§11, §20) — shown AFTER
/// authenticated onboarding (from Home), never on splash and never nagging. On
/// Enable it triggers the OS permission prompt; on Not now the app works
/// normally and the in-app notification center still functions. Gated by a
/// secure-storage flag so it appears at most once per install, plus an in-memory
/// guard so it's scheduled at most once per session.
class NotificationExplainer {
  NotificationExplainer(this._ref);

  final Ref _ref;
  static const _seenKey = 'wtm.notif.explainer_seen';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _triggered = false;

  /// Whether this session has already scheduled the explainer (callers use this
  /// to avoid re-scheduling on every rebuild).
  bool get triggered => _triggered;

  /// Show the explainer once if it hasn't been shown before. Best-effort — any
  /// error is swallowed; this must never block the app.
  Future<void> maybeShow(BuildContext context) async {
    if (_triggered) return;
    _triggered = true;
    try {
      if (await _storage.read(key: _seenKey) == 'true') return;
      await _storage.write(key: _seenKey, value: 'true');
      if (!context.mounted) return;
      final enable = await _show(context);
      if (enable == true) {
        await _ref.read(pushMessagingProvider).promptPermission();
      }
    } catch (_) {
      // best-effort — never break startup
    }
  }

  Future<bool?> _show(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bullets = [
      l10n.wtmNotifExplainerB1,
      l10n.wtmNotifExplainerB2,
      l10n.wtmNotifExplainerB3,
      l10n.wtmNotifExplainerB4,
      l10n.wtmNotifExplainerB5,
    ];
    return showDialog<bool>(
      context: context,
      barrierColor: const Color(0xB3050308),
      builder: (context) => Dialog(
        backgroundColor: WtmColors.panel,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WtmRadius.card),
          side: const BorderSide(color: WtmColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WtmSpace.s18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WtmIcon(WtmGlyph.bell, size: 22, color: WtmColors.gold),
              const SizedBox(height: WtmSpace.s12),
              Text(
                l10n.wtmNotifExplainerTitle,
                style: WtmType.h1.copyWith(fontSize: 20),
              ),
              const SizedBox(height: WtmSpace.s8),
              Text(l10n.wtmNotifExplainerIntro, style: WtmType.sub),
              const SizedBox(height: WtmSpace.s12),
              for (final b in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const WtmIcon(WtmGlyph.check, size: 12, color: WtmColors.gold),
                      const SizedBox(width: WtmSpace.s8),
                      Expanded(child: Text(b, style: WtmType.micro)),
                    ],
                  ),
                ),
              const SizedBox(height: WtmSpace.s14),
              GradientCta(
                label: l10n.wtmNotifExplainerEnable,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: WtmSpace.s8),
              GhostButton(
                label: l10n.wtmNotifExplainerLater,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final notificationExplainerProvider = Provider<NotificationExplainer>(
  (ref) => NotificationExplainer(ref),
);
