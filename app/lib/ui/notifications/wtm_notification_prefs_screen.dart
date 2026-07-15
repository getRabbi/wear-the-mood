import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/push/push_messaging.dart';
import '../../data/models/notification_prefs.dart';
import '../../data/repositories/notification_prefs_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Per-category push preferences (§20). Toggling gates PUSH delivery only — the
/// in-app notification center always shows every durable notification, so this
/// screen never hides history. Each of the seven category toggles PATCHes
/// immediately (optimistic, with revert on failure) and NEVER triggers an OS
/// permission prompt; even when the OS has blocked notifications the toggles
/// remain editable. A master status row reflects the OS permission and offers
/// the one correct action (enable, or open system settings). Promotional is
/// opt-in (default off).
class WtmNotificationPrefsScreen extends ConsumerStatefulWidget {
  const WtmNotificationPrefsScreen({super.key});

  @override
  ConsumerState<WtmNotificationPrefsScreen> createState() =>
      _WtmNotificationPrefsScreenState();
}

class _WtmNotificationPrefsScreenState
    extends ConsumerState<WtmNotificationPrefsScreen>
    with WidgetsBindingObserver {
  NotificationPreferences? _prefs; // local (optimistic) copy once loaded
  final Set<String> _saving = {};
  PushPermissionStatus _permission = PushPermissionStatus.unavailable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have flipped the OS toggle in system settings and returned —
    // re-read the permission (never prompts) so the master status stays honest.
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final status = await ref.read(pushMessagingProvider).permissionStatus();
    if (mounted) setState(() => _permission = status);
  }

  Future<void> _set(String key, bool value) async {
    final l10n = AppLocalizations.of(context);
    final previous = _prefs!;
    setState(() {
      _prefs = _withKey(previous, key, value);
      _saving.add(key);
    });
    try {
      // Preferences are independent of the OS permission — we PATCH regardless,
      // so a user can pre-tune categories even before enabling system push.
      final updated = await ref
          .read(notificationPrefsRepositoryProvider)
          .update({key: value});
      if (!mounted) return;
      setState(() {
        _prefs = updated;
        _saving.remove(key);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _prefs = previous; // revert
        _saving.remove(key);
      });
      wtmSnack(context, l10n.wtmNotifPrefsSaveError);
    }
  }

  static NotificationPreferences _withKey(
    NotificationPreferences p,
    String key,
    bool v,
  ) => switch (key) {
    'account_updates' => p.copyWith(accountUpdates: v),
    'referral_rewards' => p.copyWith(referralRewards: v),
    'social_activity' => p.copyWith(socialActivity: v),
    'community' => p.copyWith(community: v),
    'daily_style' => p.copyWith(dailyStyle: v),
    'product_updates' => p.copyWith(productUpdates: v),
    'promotional' => p.copyWith(promotional: v),
    _ => p,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(notificationPrefsProvider);

    return WtmPage(
      fullBleed: true,
      title: l10n.wtmNotifPrefsTitle,
      eyebrow: l10n.wtmNotifPrefsEyebrow,
      children: async.when(
        skipLoadingOnReload: true,
        loading: () => const [
          SizedBox(height: WtmSpace.s10),
          LoadingShimmer(width: double.infinity, height: 72),
          SizedBox(height: WtmSpace.s10),
          LoadingShimmer(width: double.infinity, height: 72),
          SizedBox(height: WtmSpace.s10),
          LoadingShimmer(width: double.infinity, height: 72),
        ],
        error: (_, _) => [
          const SizedBox(height: WtmSpace.s22),
          WtmEmptyState(
            glyph: WtmGlyph.bell,
            title: l10n.wtmNotifPrefsError,
            message: l10n.wtmNotifPrefsIntro,
            ctaLabel: l10n.commonRetry,
            onCta: () => ref.invalidate(notificationPrefsProvider),
          ),
        ],
        data: (server) {
          final p = _prefs ??= server; // seed local copy once
          return [
            Text(l10n.wtmNotifPrefsIntro, style: WtmType.sub),
            const SizedBox(height: WtmSpace.s12),
            _MasterStatus(
              status: _permission,
              onEnable: () async {
                await ref.read(pushMessagingProvider).promptPermission();
                await _refreshPermission();
              },
              onOpenSettings: () =>
                  ref.read(pushMessagingProvider).openSystemNotificationSettings(),
            ),
            const SizedBox(height: WtmSpace.s14),
            _Toggle('account_updates', l10n.wtmNotifPrefsAccount,
                l10n.wtmNotifPrefsAccountSub, p.accountUpdates,
                _saving.contains('account_updates'), _set),
            _Toggle('referral_rewards', l10n.wtmNotifPrefsReferral,
                l10n.wtmNotifPrefsReferralSub, p.referralRewards,
                _saving.contains('referral_rewards'), _set),
            _Toggle('social_activity', l10n.wtmNotifPrefsSocial,
                l10n.wtmNotifPrefsSocialSub, p.socialActivity,
                _saving.contains('social_activity'), _set),
            _Toggle('community', l10n.wtmNotifPrefsCommunity,
                l10n.wtmNotifPrefsCommunitySub, p.community,
                _saving.contains('community'), _set),
            _Toggle('daily_style', l10n.wtmNotifPrefsStyle,
                l10n.wtmNotifPrefsStyleSub, p.dailyStyle,
                _saving.contains('daily_style'), _set),
            _Toggle('product_updates', l10n.wtmNotifPrefsProduct,
                l10n.wtmNotifPrefsProductSub, p.productUpdates,
                _saving.contains('product_updates'), _set),
            _Toggle('promotional', l10n.wtmNotifPrefsPromotions,
                l10n.wtmNotifPrefsPromotionsSub, p.promotional,
                _saving.contains('promotional'), _set),
            const SizedBox(height: WtmSpace.s6),
            Text(l10n.wtmNotifPrefsMutedNote, style: WtmType.micro),
            const SizedBox(height: WtmSpace.s16),
          ];
        },
      ),
    );
  }
}

/// The master OS-permission row: an accurate status line plus the single action
/// that matches the state — enable when never asked, open system settings when
/// blocked, nothing when already on (§20).
class _MasterStatus extends StatelessWidget {
  const _MasterStatus({
    required this.status,
    required this.onEnable,
    required this.onOpenSettings,
  });

  final PushPermissionStatus status;
  final Future<void> Function() onEnable;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final granted = status == PushPermissionStatus.granted;
    final denied = status == PushPermissionStatus.denied;

    final String line = switch (status) {
      PushPermissionStatus.granted => l10n.wtmNotifPrefsPushOn,
      PushPermissionStatus.denied => l10n.wtmNotifPrefsBlocked,
      _ => l10n.wtmNotifPrefsPushOff,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: WtmGradients.cardFill,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: granted ? WtmColors.gold : WtmColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              WtmIcon(
                WtmGlyph.bell,
                size: 17,
                color: granted ? WtmColors.gold : WtmColors.muted,
              ),
              const SizedBox(width: WtmSpace.s12),
              Expanded(child: Text(line, style: WtmType.labelMedium)),
            ],
          ),
          if (!granted) ...[
            const SizedBox(height: WtmSpace.s10),
            GhostButton(
              label: denied
                  ? l10n.wtmNotifPrefsOpenSettings
                  : l10n.wtmNotifPrefsEnable,
              onPressed: denied ? onOpenSettings : () => onEnable(),
            ),
          ],
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.keyName, this.title, this.subtitle, this.value, this.saving,
      this.onChanged);

  final String keyName;
  final String title;
  final String subtitle;
  final bool value;
  final bool saving;
  final Future<void> Function(String key, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: WtmGradients.cardFill,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: WtmType.labelMedium),
                const SizedBox(height: 3),
                Text(subtitle, style: WtmType.micro),
              ],
            ),
          ),
          const SizedBox(width: WtmSpace.s12),
          Switch(
            value: value,
            onChanged: saving ? null : (v) => onChanged(keyName, v),
            activeThumbColor: WtmColors.ctaText,
            activeTrackColor: WtmColors.gold,
            inactiveThumbColor: WtmColors.muted,
            inactiveTrackColor: WtmColors.line,
          ),
        ],
      ),
    );
  }
}
