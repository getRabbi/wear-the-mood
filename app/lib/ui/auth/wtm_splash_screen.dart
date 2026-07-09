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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    // Let the orb breathe once before deciding where to go.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final signedIn =
        AppEnv.hasSupabaseConfig && ref.read(isAuthenticatedProvider);
    if (!signedIn) {
      context.go(AppRoute.wtmAuth);
      return;
    }
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
