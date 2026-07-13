import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/share/share_service.dart';
import '../../data/models/referral_summary.dart';
import '../../data/repositories/referral_rewards_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Compact "Invite friends" card for the Profile — links to the full referral
/// screen and offers a quick Copy link. Reads the server-controlled bonus (§24).
class WtmInviteFriendsCard extends ConsumerWidget {
  const WtmInviteFriendsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summary = ref.watch(referralSummaryProvider).asData?.value;
    final bonus = summary?.bonus ?? 10; // display fallback; grant is server-side

    return Semantics(
      button: true,
      label: l10n.wtmProfileInviteTitle,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push(AppRoute.wtmReferral),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(color: WtmColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const WtmIcon(WtmGlyph.gift, size: 18, color: WtmColors.gold),
                    const SizedBox(width: WtmSpace.s10),
                    Expanded(
                      child: Text(l10n.wtmProfileInviteTitle,
                          style: WtmType.labelMedium),
                    ),
                    const WtmIcon(WtmGlyph.chevron, size: 15, color: WtmColors.faint),
                  ],
                ),
                const SizedBox(height: 6),
                Text(l10n.wtmProfileInviteSub(bonus), style: WtmType.micro),
                const SizedBox(height: WtmSpace.s12),
                Row(
                  children: [
                    GoldPill(
                      label: l10n.wtmReferralShareAction,
                      icon: const WtmIcon(WtmGlyph.gift, size: 12, color: WtmColors.gold),
                      onTap: () => context.push(AppRoute.wtmReferral),
                    ),
                    const SizedBox(width: WtmSpace.s8),
                    if (summary != null)
                      GoldPill(
                        label: l10n.wtmReferralCopyAction,
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: summary.url),
                          );
                          if (context.mounted) {
                            wtmSnack(context, l10n.wtmReferralCopied);
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Invite Friends — referral rewards (§24). Share your link; the REFERRER earns
/// bonus credits once an eligible new friend installs from Google Play and
/// creates their first account. Server-authoritative — no code entry, no local
/// grants, no private friend data. Shows a one-time "you earned N" banner when a
/// new successful referral is detected since the last visit.
class WtmReferralScreen extends ConsumerStatefulWidget {
  const WtmReferralScreen({super.key});

  @override
  ConsumerState<WtmReferralScreen> createState() => _WtmReferralScreenState();
}

class _WtmReferralScreenState extends ConsumerState<WtmReferralScreen> {
  static const _seenKey = 'wtm.referral.seen_count';
  final _storage = const FlutterSecureStorage();
  int? _seenCount; // null until loaded
  bool _expandRules = false;

  @override
  void initState() {
    super.initState();
    _loadSeen();
  }

  Future<void> _loadSeen() async {
    try {
      final raw = await _storage.read(key: _seenKey);
      if (mounted) setState(() => _seenCount = int.tryParse(raw ?? '') ?? 0);
    } catch (_) {
      if (mounted) setState(() => _seenCount = 0);
    }
  }

  Future<void> _dismissBanner(int count) async {
    try {
      await _storage.write(key: _seenKey, value: '$count');
    } catch (_) {
      // best-effort
    }
    if (mounted) setState(() => _seenCount = count);
  }

  Future<void> _share(ReferralSummary r) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(shareServiceProvider).shareText(l10n.wtmReferralShareText(r.url));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: r.url));
      if (mounted) wtmSnack(context, l10n.wtmReferralCopied);
    }
  }

  Future<void> _copy(ReferralSummary r) async {
    await Clipboard.setData(ClipboardData(text: r.url));
    if (mounted) wtmSnack(context, AppLocalizations.of(context).wtmReferralCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(referralSummaryProvider);

    return WtmPage(
      fullBleed: true,
      title: l10n.wtmReferralTitle,
      eyebrow: l10n.wtmReferralEyebrow,
      children: async.when(
        skipLoadingOnReload: true,
        loading: () => const [
          _Skeleton(),
        ],
        error: (_, _) => [
          const SizedBox(height: WtmSpace.s22),
          WtmEmptyState(
            glyph: WtmGlyph.gift,
            title: l10n.wtmReferralError,
            message: l10n.wtmReferralEligibility,
            ctaLabel: l10n.commonRetry,
            onCta: () => ref.invalidate(referralSummaryProvider),
          ),
        ],
        data: (r) => _content(context, l10n, r),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    AppLocalizations l10n,
    ReferralSummary r,
  ) {
    if (!r.enabled) {
      return [
        const SizedBox(height: WtmSpace.s22),
        WtmEmptyState(
          glyph: WtmGlyph.gift,
          title: l10n.wtmReferralDisabled,
          message: l10n.wtmReferralEligibility,
        ),
      ];
    }

    final showBanner = _seenCount != null && r.successfulCount > _seenCount!;

    return [
      if (showBanner) ...[
        _RewardBanner(
          message: l10n.wtmReferralRewardBanner(
            (r.successfulCount - _seenCount!) * r.bonus,
          ),
          onDismiss: () => _dismissBanner(r.successfulCount),
        ),
        const SizedBox(height: WtmSpace.s14),
      ],
      Text.rich(
        TextSpan(
          text: '${l10n.wtmReferralHeadline} ',
          style: WtmType.display.copyWith(fontSize: 24),
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: WtmSpace.s6),
      Text(
        l10n.wtmReferralSub(r.bonus),
        textAlign: TextAlign.center,
        style: WtmType.sub,
      ),
      const SizedBox(height: WtmSpace.s16),
      _LinkCard(referral: r, onCopy: () => _copy(r)),
      const SizedBox(height: WtmSpace.s14),
      GradientCta(
        label: l10n.wtmReferralShareAction,
        icon: const WtmIcon(WtmGlyph.gift, size: 15, color: WtmColors.ctaText),
        onPressed: () => _share(r),
      ),
      const SizedBox(height: WtmSpace.s10),
      GhostButton(
        label: l10n.wtmReferralCopyAction,
        onPressed: () => _copy(r),
      ),
      const SizedBox(height: WtmSpace.s16),
      Row(
        children: [
          Expanded(
            child: _Stat('${r.successfulCount}', l10n.wtmReferralStatFriends),
          ),
          const SizedBox(width: WtmSpace.s10),
          Expanded(
            child: _Stat('${r.totalEarned}', l10n.wtmReferralStatCredits),
          ),
        ],
      ),
      const SizedBox(height: WtmSpace.s14),
      Text(l10n.wtmReferralEligibility, style: WtmType.micro),
      const SizedBox(height: WtmSpace.s10),
      // Expandable rules / terms.
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expandRules = !_expandRules),
        child: Row(
          children: [
            Text(l10n.wtmReferralRules,
                style: WtmType.micro.copyWith(color: WtmColors.gold)),
            const Spacer(),
            WtmIcon(
              _expandRules ? WtmGlyph.chevron : WtmGlyph.chevron,
              size: 13,
              color: WtmColors.gold,
            ),
          ],
        ),
      ),
      if (_expandRules) ...[
        const SizedBox(height: WtmSpace.s6),
        Text(l10n.wtmReferralRulesBody(r.bonus), style: WtmType.micro),
      ],
    ];
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.referral, required this.onCopy});

  final ReferralSummary referral;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: WtmGradients.assistFill,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.assistBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EyebrowLabel(l10n.wtmReferralYourCode),
          const SizedBox(height: 6),
          Text(
            referral.code,
            style: WtmType.h1.copyWith(fontSize: 26, letterSpacing: 4),
          ),
          const SizedBox(height: WtmSpace.s12),
          EyebrowLabel(l10n.wtmReferralYourLink),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  referral.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WtmType.micro.copyWith(color: WtmColors.text),
                ),
              ),
              const SizedBox(width: WtmSpace.s8),
              GoldPill(
                label: l10n.wtmReferralCopyAction,
                onTap: onCopy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: WtmGradients.cardFill,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.line),
      ),
      child: Column(
        children: [
          Text(value, style: WtmType.h1.copyWith(fontSize: 24, color: WtmColors.gold)),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: WtmType.micro.copyWith(fontSize: 8.5, letterSpacing: 1.36),
          ),
        ],
      ),
    );
  }
}

class _RewardBanner extends StatelessWidget {
  const _RewardBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WtmColors.pillBg,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.pillBorder),
      ),
      child: Row(
        children: [
          const WtmIcon(WtmGlyph.gift, size: 18, color: WtmColors.gold),
          const SizedBox(width: WtmSpace.s10),
          Expanded(
            child: Text(
              message,
              style: WtmType.labelMedium.copyWith(color: WtmColors.gold),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: WtmIcon(WtmGlyph.check, size: 14, color: WtmColors.faint),
            ),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: WtmSpace.s10),
        LoadingShimmer(
          width: double.infinity,
          height: 140,
          borderRadius: BorderRadius.all(Radius.circular(WtmRadius.card)),
        ),
        SizedBox(height: WtmSpace.s14),
        LoadingShimmer(width: double.infinity, height: 52),
      ],
    );
  }
}
