import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/auth_providers.dart';
import 'core/env/app_env.dart';
import 'core/push/push_messaging.dart';
import 'core/router/app_router.dart';
import 'core/router/routes.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/ai_studio_repository.dart';
import 'data/repositories/credits_repository.dart';
import 'features/paywall/billing_providers.dart';
import 'features/paywall/subscription_service.dart';
import 'l10n/app_localizations.dart';

/// Root application widget. Drives theme, localization, and routing, and (when
/// [enablePush]) starts FCM push registration after the first frame. Push is off
/// by default so widget tests never touch Firebase.
class FashionOsApp extends ConsumerStatefulWidget {
  const FashionOsApp({super.key, this.enablePush = false});

  final bool enablePush;

  @override
  ConsumerState<FashionOsApp> createState() => _FashionOsAppState();
}

class _FashionOsAppState extends ConsumerState<FashionOsApp>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Auth-driven navigation — runs whenever Supabase is configured, independent
    // of push, so it's never gated behind the push flag (widget tests have no
    // Supabase config, so this stays inert there).
    if (AppEnv.hasSupabaseConfig) {
      _authSub = ref.read(authRepositoryProvider).authStateChanges().listen((
        state,
      ) {
        if (!mounted) return;
        final router = ref.read(goRouterProvider);
        switch (state.event) {
          case AuthChangeEvent.passwordRecovery:
            // Password-reset deep link → set a new password (§11/§23).
            router.pushNamed(AppRoute.setPasswordName);
          case AuthChangeEvent.initialSession:
            // Cold start with a restored session: identify the RevenueCat
            // customer + bind the CustomerInfo listener + refresh the plan for
            // THIS user, so tier/credits are correct without waiting for a fresh
            // sign-in. Routing is declarative (RootGate) — no navigation here.
            final userId = state.session?.user.id;
            if (userId != null) {
              unawaited(
                ref
                    .read(subscriptionServiceProvider)
                    .syncIdentity(userId),
              );
            }
          case AuthChangeEvent.signedIn:
            // Identify the RevenueCat customer as THIS Supabase user so the
            // webhook's app_user_id is our UUID and an account switch never
            // inherits the previous user's cached entitlement (§18). Also
            // refreshes the server subscription state for the new identity.
            unawaited(
              ref
                  .read(subscriptionServiceProvider)
                  .syncIdentity(state.session?.user.id),
            );
            // Close the (imperatively pushed) auth screen on ANY successful
            // sign-in: email sign-in, email sign-up auto-login, native Google,
            // or the Google browser-OAuth deep-link return. Use go() — which
            // reliably REPLACES the stack — because go_router's refreshListenable
            // redirect does NOT pop an imperatively pushed route, which left the
            // user stranded on /auth after signing in. Guarded to the auth screen
            // so it never disrupts in-app navigation or cold-start session
            // restore (RootGate handles that declaratively).
            final atAuth = router
                .routerDelegate
                .currentConfiguration
                .uri
                .path
                .startsWith(AppRoute.auth);
            if (atAuth) router.go(AppRoute.home);
          case AuthChangeEvent.signedOut:
            // Clear the RevenueCat identity so the next user starts clean.
            unawaited(ref.read(subscriptionServiceProvider).syncIdentity(null));
          default:
            break;
        }
      });
    }

    if (widget.enablePush) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pushMessagingProvider).start();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On foreground, re-sync the SERVER-verified plan so a subscription change
    // (RevenueCat purchase, webhook, renewal/expiry, or an admin grant) reflects
    // promptly — no full app restart needed. entitlementProvider (drawers/premium
    // gates) isn't auto-dispose, so without this it would stay stale until a
    // relaunch; credits + studio models refresh alongside it.
    if (state == AppLifecycleState.resumed && AppEnv.hasSupabaseConfig) {
      ref.invalidate(entitlementProvider);
      ref.invalidate(creditsProvider);
      ref.invalidate(studioModelsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
