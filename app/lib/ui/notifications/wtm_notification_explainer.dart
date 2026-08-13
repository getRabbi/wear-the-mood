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
/// normally and the in-app notification center still functions.
///
/// **Idempotent against the OS, not just against a flag.** It used to be gated
/// solely by a secure-storage "seen" marker, which made the marker the only
/// thing standing between an already-subscribed user and being asked again —
/// and a marker is device state that can go missing (a reinstall, a keychain
/// that answers late, a storage error swallowed on the way in). Signing out and
/// back in is not a reason to re-ask somebody who already said yes, so the
/// question is now asked of the OS first: only [PushPermissionStatus.notDetermined]
/// — genuinely never asked — earns the explainer. Granted needs nothing.
/// Denied cannot be undone from in-app anyway, and the honest place for it is
/// the notification preferences screen's Open Settings action, so this stays
/// quiet rather than presenting a request that cannot succeed.
///
/// The storage marker is kept as the second gate, so a user who chose Not now
/// on a `notDetermined` device is still not asked twice.
class NotificationExplainer {
  NotificationExplainer(this._ref);

  final Ref _ref;
  static const _seenKey = 'wtm.notif.explainer_seen';
  bool _triggered = false;

  FlutterSecureStorage get _storage =>
      _ref.read(notificationExplainerStorageProvider);

  /// Whether this session has already scheduled the explainer (callers use this
  /// to avoid re-scheduling on every rebuild).
  bool get triggered => _triggered;

  /// Show the explainer once if it hasn't been shown before. Best-effort — any
  /// error is swallowed; this must never block the app.
  Future<void> maybeShow(BuildContext context) async {
    if (_triggered) return;
    _triggered = true;
    try {
      final push = _ref.read(pushMessagingProvider);

      // The OS is the authority. Anything other than "never asked" means this
      // prompt has nothing to offer, whatever the local marker says.
      final status = await push.permissionStatus();
      if (status == PushPermissionStatus.granted ||
          status == PushPermissionStatus.denied) {
        // Record it, so a device that later loses the OS answer (or reports
        // `unavailable` because Firebase is not configured) does not treat the
        // absence as a fresh install and start asking again.
        await _markSeen();
        return;
      }

      if (await _storage.read(key: _seenKey) == 'true') return;
      await _markSeen();
      if (!context.mounted) return;
      final enable = await _show(context);
      if (enable == true) {
        await push.promptPermission();
      }
    } catch (_) {
      // best-effort — never break startup
    }
  }

  Future<void> _markSeen() async {
    try {
      await _storage.write(key: _seenKey, value: 'true');
    } catch (_) {
      // A marker that cannot be written costs at most one extra prompt on a
      // device the OS has not been asked about — never a broken launch.
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
                      const WtmIcon(
                        WtmGlyph.check,
                        size: 12,
                        color: WtmColors.gold,
                      ),
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

/// Where the "already asked" marker lives.
///
/// Behind a provider so a test can supply an in-memory keychain — including one
/// that FAILS to write, which is one of the ways the marker goes missing on a
/// real device and the reason the OS is now the primary gate.
final notificationExplainerStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

final notificationExplainerProvider = Provider<NotificationExplainer>(
  (ref) => NotificationExplainer(ref),
);
