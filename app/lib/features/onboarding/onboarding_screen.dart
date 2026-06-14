import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'onboarding_providers.dart';

/// First-run flow (CLAUDE.md §17): a short value carousel ending in an explicit
/// consent screen (§10) before the user enters the app. The first "wow" is not
/// gated behind sign-up — account creation stays soft and later.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _busy = false;

  static const _consentIndex = 3;
  static const _pageCount = 4;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) => _controller.animateToPage(
    page,
    duration: AppMotion.base,
    curve: AppMotion.easing,
  );

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    final analytics = ref.read(analyticsProvider);
    await analytics.track(AnalyticsEvents.consentGranted);
    await ref.read(onboardingRepositoryProvider).markComplete();
    await analytics.track(AnalyticsEvents.onboardingCompleted);
    // RootGate re-resolves to the app.
    ref.invalidate(onboardingSeenProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onConsent = _index == _consentIndex;

    final pages = <Widget>[
      _ValuePage(
        icon: Icons.auto_awesome,
        title: l10n.onboardingValue1Title,
        body: l10n.onboardingValue1Body,
      ),
      _ValuePage(
        icon: Icons.checkroom_rounded,
        title: l10n.onboardingValue2Title,
        body: l10n.onboardingValue2Body,
      ),
      _ValuePage(
        icon: Icons.wb_sunny_rounded,
        title: l10n.onboardingValue3Title,
        body: l10n.onboardingValue3Body,
      ),
      _ConsentPage(
        title: l10n.onboardingConsentTitle,
        body: l10n.onboardingConsentBody,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.centerRight,
                child: onConsent
                    ? null
                    : TextButton(
                        onPressed: () => _goTo(_consentIndex),
                        child: Text(l10n.onboardingSkip),
                      ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                children: pages,
              ),
            ),
            _Dots(count: _pageCount, index: _index),
            const SizedBox(height: AppSpace.lg),
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: PrimaryButton(
                label: onConsent
                    ? l10n.onboardingConsentAgree
                    : l10n.onboardingNext,
                icon: onConsent ? Icons.check_rounded : null,
                isLoading: _busy,
                onPressed: onConsent ? _finish : () => _goTo(_index + 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValuePage extends StatelessWidget {
  const _ValuePage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: const BoxDecoration(
              gradient: AppGradients.brand,
              shape: BoxShape.circle,
              boxShadow: AppShadow.accentGlow,
            ),
            child: Icon(icon, size: 56, color: Colors.white),
          ),
          const SizedBox(height: AppSpace.xl),
          Text(title, style: text.displaySmall, textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.md),
          Text(body, style: text.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ConsentPage extends StatelessWidget {
  const _ConsentPage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              gradient: AppGradients.brand,
              shape: BoxShape.circle,
              boxShadow: AppShadow.accentGlow,
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              size: 46,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.md),
          Text(body, style: text.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: AppMotion.fast,
          margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.mist,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        );
      }),
    );
  }
}
