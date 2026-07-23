import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/env/app_env.dart';
import '../../core/router/routes.dart';
import '../../features/onboarding/onboarding_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// WTM Splash (board §3.1, P10) — the breathing orb + wordmark, then auto-routes
/// by session: signed out → auth; signed in but new → onboarding; else home.
class WtmSplashScreen extends ConsumerStatefulWidget {
  const WtmSplashScreen({super.key});

  @override
  ConsumerState<WtmSplashScreen> createState() => _WtmSplashScreenState();
}

class _WtmSplashScreenState extends ConsumerState<WtmSplashScreen> {
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  /// Decide where to go from the splash. Two triggers:
  ///  * the initial timed pass (cold launch) — breathe once, then route by
  ///    session; a genuinely signed-out user falls to the auth gate here;
  ///  * an auth-state change (`fromAuthChange`) — an OAuth/email session that
  ///    lands WHILE the splash is on screen routes straight in, no wait, so we
  ///    never navigate before the session is available and never strand an
  ///    authenticated user on Sign In (and never flash the auth screen first).
  Future<void> _route({bool fromAuthChange = false}) async {
    if (_routed || !mounted) return;
    if (!fromAuthChange) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (_routed || !mounted) return;
    }
    final signedIn =
        AppEnv.hasSupabaseConfig && ref.read(isAuthenticatedProvider);
    if (!signedIn) {
      // Only the initial timed pass decides "signed out → auth". A later
      // auth-change pass never lands here (it fires only when signed in), so it
      // simply waits for the real session instead of racing to the gate.
      if (fromAuthChange) return;
      _routed = true;
      context.go(AppRoute.wtmAuth);
      return;
    }
    _routed = true;
    var done = false;
    try {
      done = await ref.read(onboardingSeenProvider.future);
    } catch (_) {
      done = false;
    }
    if (!mounted) return;
    context.go(done ? AppRoute.wtmHome : AppRoute.wtmOnboarding);
  }

  @override
  Widget build(BuildContext context) {
    // Route the instant a real session appears (OAuth deep-link / email signup
    // landing while the splash is visible) — reactive, never a stale read.
    ref.listen(isAuthenticatedProvider, (_, next) {
      if (next) _route(fromAuthChange: true);
    });
    final l10n = AppLocalizations.of(context);
    final words = l10n.appTitle.toUpperCase().split(' ');
    return WtmScaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuroraBox(
            borderRadius: BorderRadius.zero,
            border: false,
            vignette: true,
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TheOrb(size: 96),
                const SizedBox(height: WtmSpace.s22),
                Text(
                  words.join('\n'),
                  textAlign: TextAlign.center,
                  style: WtmType.display.copyWith(
                    fontSize: 30,
                    height: 1.15,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: WtmSpace.s10),
                Text(
                  l10n.wtmSplashTagline,
                  style: WtmType.micro.copyWith(
                    color: WtmColors.goldDim,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
