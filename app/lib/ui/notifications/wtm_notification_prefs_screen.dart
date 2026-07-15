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
/// screen never hides history. Each toggle PATCHes immediately (optimistic, with
/// revert on failure). Promotions are opt-in (default off).
class WtmNotificationPrefsScreen extends ConsumerStatefulWidget {
  const WtmNotificationPrefsScreen({super.key});

  @override
  ConsumerState<WtmNotificationPrefsScreen> createState() =>
      _WtmNotificationPrefsScreenState();
}

class _WtmNotificationPrefsScreenState
    extends ConsumerState<WtmNotificationPrefsScreen> {
  NotificationPreferences? _prefs; // local (optimistic) copy once loaded
  final Set<String> _saving = {};

  Future<void> _set(String key, bool value) async {
    final l10n = AppLocalizations.of(context);
    final previous = _prefs!;
    setState(() {
      _prefs = _withKey(previous, key, value);
      _saving.add(key);
    });
    try {
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
    'social' => p.copyWith(social: v),
    'referral' => p.copyWith(referral: v),
    'account' => p.copyWith(account: v),
    'community' => p.copyWith(community: v),
    'style' => p.copyWith(style: v),
    'promotions' => p.copyWith(promotions: v),
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
            const SizedBox(height: WtmSpace.s10),
            GhostButton(
              label: l10n.wtmNotifPrefsEnable,
              icon: const WtmIcon(WtmGlyph.bell, size: 15, color: WtmColors.text),
              onPressed: () => ref.read(pushMessagingProvider).promptPermission(),
            ),
            const SizedBox(height: WtmSpace.s14),
            _Toggle('social', l10n.wtmNotifPrefsSocial, l10n.wtmNotifPrefsSocialSub,
                p.social, _saving.contains('social'), _set),
            _Toggle('referral', l10n.wtmNotifPrefsReferral,
                l10n.wtmNotifPrefsReferralSub, p.referral,
                _saving.contains('referral'), _set),
            _Toggle('account', l10n.wtmNotifPrefsAccount,
                l10n.wtmNotifPrefsAccountSub, p.account,
                _saving.contains('account'), _set),
            _Toggle('community', l10n.wtmNotifPrefsCommunity,
                l10n.wtmNotifPrefsCommunitySub, p.community,
                _saving.contains('community'), _set),
            _Toggle('style', l10n.wtmNotifPrefsStyle, l10n.wtmNotifPrefsStyleSub,
                p.style, _saving.contains('style'), _set),
            _Toggle('promotions', l10n.wtmNotifPrefsPromotions,
                l10n.wtmNotifPrefsPromotionsSub, p.promotions,
                _saving.contains('promotions'), _set),
          ];
        },
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
