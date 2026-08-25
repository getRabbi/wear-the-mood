import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/auth/guest_session.dart';
import '../../core/legal/legal_links.dart';
import '../../core/platform/platform_capabilities.dart';
import '../../core/router/routes.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// The iOS account-choice gate (App Review 5.1.1(v)).
///
/// **iOS/iPadOS only.** The Android signed-out landing is still
/// [WtmAuthScreen], reached by exactly the path it has always been reached by;
/// this screen is never built there. That isolation is enforced in the router,
/// not here, but the screen also refuses to render its guest affordance if it
/// somehow gets mounted on another platform — two locks on one door, because
/// the cost of this leaking onto Android is a changed launch experience for
/// users who already have the app.
///
/// The hierarchy is deliberate and is not a dark pattern:
///
///  1. **Create My Wardrobe** — the primary gradient CTA. It is first and it is
///     the loudest because it is genuinely the better outcome for the user;
///     everything WTM does well needs somewhere to keep their things.
///  2. **Continue as Guest** — a full-width outlined button of the same height
///     and the same tap target, immediately below. Not a grey footnote, not
///     8pt type at the bottom of a scroll: a reviewer, and a real person,
///     should find it without looking for it.
///  3. **Already have an account? Sign In** — a text action.
class WtmWelcomeScreen extends ConsumerStatefulWidget {
  const WtmWelcomeScreen({super.key});

  @override
  ConsumerState<WtmWelcomeScreen> createState() => _WtmWelcomeScreenState();
}

class _WtmWelcomeScreenState extends ConsumerState<WtmWelcomeScreen> {
  /// Guards double taps and the window between "guest chosen" and the router
  /// settling on Home. Without it a fast double tap fires two navigations and
  /// the second lands on a route the first already left.
  bool _busy = false;

  Future<void> _continueAsGuest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(guestSessionProvider.notifier).enterGuest();
      unawaited(
        ref.read(analyticsProvider).track(AnalyticsEvents.iosGuestEntered),
      );
      if (!mounted) return;
      // `go` (not `push`): the welcome screen must not stay under Home, or the
      // iOS back gesture would slide back to a gate the user has passed.
      context.go(AppRoute.wtmHome);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openAuth({required bool signUp}) {
    if (_busy) return;
    context.push(AppRoute.wtmAuth, extra: signUp);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Second lock (see the class doc). If this is somehow mounted off iOS, the
    // guest choice is simply not offered and the screen degrades to the two
    // account actions.
    final guestAllowed = ref.watch(guestModeSupportedProvider);

    return WtmScaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuroraBox(
            borderRadius: BorderRadius.zero,
            border: false,
            vignette: true,
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Centred on a tall iPad, scrollable on a small iPhone at large
                // Dynamic Type — one layout that handles both, instead of a
                // Column that overflows the moment text scales.
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    WtmSpace.screenH,
                    WtmSpace.s22,
                    WtmSpace.screenH,
                    WtmSpace.s18,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          constraints.maxHeight - (WtmSpace.s22 + WtmSpace.s18),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        // Keeps the CTAs a comfortable measure on iPad rather
                        // than stretching them the full width of the screen.
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Center(child: TheOrb(size: 84)),
                            const SizedBox(height: WtmSpace.s22),
                            Text(
                              l10n.wtmWelcomeTitle,
                              textAlign: TextAlign.center,
                              style: WtmType.h1.copyWith(fontSize: 27),
                            ),
                            const SizedBox(height: WtmSpace.s10),
                            Text(
                              l10n.wtmWelcomeSubtitle,
                              textAlign: TextAlign.center,
                              style: WtmType.sub,
                            ),
                            const SizedBox(height: WtmSpace.s22),
                            GradientCta(
                              label: l10n.wtmWelcomeCreate,
                              onPressed: _busy
                                  ? null
                                  : () => _openAuth(signUp: true),
                            ),
                            if (guestAllowed) ...[
                              const SizedBox(height: WtmSpace.s12),
                              GhostButton(
                                label: l10n.wtmWelcomeGuest,
                                onPressed: _busy ? null : _continueAsGuest,
                              ),
                              const SizedBox(height: WtmSpace.s8),
                              Text(
                                l10n.wtmWelcomeGuestHint,
                                textAlign: TextAlign.center,
                                style: WtmType.micro,
                              ),
                            ],
                            const SizedBox(height: WtmSpace.s18),
                            Center(
                              child: _WelcomeTextAction(
                                label: l10n.wtmWelcomeSignIn,
                                onTap: _busy
                                    ? null
                                    : () => _openAuth(signUp: false),
                              ),
                            ),
                            const SizedBox(height: WtmSpace.s18),
                            _WelcomeLegal(l10n: l10n),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "Already have an account? Sign In" — a real 48dp target with its own
/// semantics, not a bare [Text] with a tap recogniser.
class _WelcomeTextAction extends StatelessWidget {
  const _WelcomeTextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: WtmType.micro.copyWith(color: WtmColors.gold),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeLegal extends StatelessWidget {
  const _WelcomeLegal({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    Widget link(String label, String url) => Semantics(
      link: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Text(
            label,
            style: WtmType.micro.copyWith(color: WtmColors.gold),
          ),
        ),
      ),
    );
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: WtmSpace.s6,
        runSpacing: WtmSpace.s4,
        children: [
          Text(l10n.wtmAuthLegal, style: WtmType.micro),
          link(l10n.wtmSettingsPrivacyPolicy, LegalLinks.privacy),
          Text('·', style: WtmType.micro),
          link(l10n.wtmSettingsTerms, LegalLinks.terms),
        ],
      ),
    );
  }
}
