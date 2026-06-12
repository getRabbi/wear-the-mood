import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/referral.dart';
import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/referral_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';

/// Referral loop (CLAUDE.md §24) — share your code, redeem a friend's. All four
/// states (§4.3). Both sides earn bonus try-on credits on redemption.
class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  final _redeemController = TextEditingController();
  bool _redeeming = false;

  @override
  void dispose() {
    _redeemController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share(Referral referral) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(
      ClipboardData(text: l10n.referralShareText(referral.code)),
    );
    await ref.read(analyticsProvider).track(AnalyticsEvents.referralSent);
    if (mounted) _snack(l10n.referralCopied);
  }

  Future<void> _redeem() async {
    final code = _redeemController.text.trim();
    if (code.isEmpty || _redeeming) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _redeeming = true);
    try {
      final credits = await ref.read(referralRepositoryProvider).redeem(code);
      _redeemController.clear();
      ref.invalidate(referralProvider);
      ref.invalidate(creditsProvider);
      if (mounted) _snack(l10n.referralRedeemSuccess(credits));
    } on ApiException {
      if (mounted) _snack(l10n.referralRedeemError);
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final referral = ref.watch(referralProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.referralTitle)),
      body: SafeArea(
        child: referral.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            title: l10n.referralErrorTitle,
            onRetry: () => ref.invalidate(referralProvider),
          ),
          data: (r) => ListView(
            padding: const EdgeInsets.all(AppSpace.lg),
            children: [
              Text(l10n.referralHeadline, style: _t(context).headlineSmall),
              const SizedBox(height: AppSpace.sm),
              Text(l10n.referralSubtitle(r.rewardCredits), style: _t(context).bodyMedium),
              const SizedBox(height: AppSpace.xl),
              _CodeCard(code: r.code),
              const SizedBox(height: AppSpace.lg),
              PrimaryButton(
                label: l10n.referralShare,
                icon: Icons.ios_share_rounded,
                onPressed: () => _share(r),
              ),
              if (r.referralCount > 0) ...[
                const SizedBox(height: AppSpace.md),
                Text(
                  l10n.referralCount(r.referralCount),
                  style: _t(context).bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpace.xxl),
              Text(l10n.referralRedeemTitle, style: _t(context).titleMedium),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _redeemController,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _redeem(),
                      decoration: InputDecoration(
                        hintText: l10n.referralRedeemHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  IconButton.filled(
                    onPressed: _redeeming ? null : _redeem,
                    icon: const Icon(Icons.redeem_rounded),
                    tooltip: l10n.referralRedeem,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextTheme _t(BuildContext context) => Theme.of(context).textTheme;
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        children: [
          Text(l10n.referralYourCode, style: text.bodySmall),
          const SizedBox(height: AppSpace.sm),
          Text(
            code,
            style: text.displaySmall?.copyWith(
              letterSpacing: 4,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
