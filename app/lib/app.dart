import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/auth_providers.dart';
import 'core/push/push_messaging.dart';
import 'core/router/app_router.dart';
import 'core/router/routes.dart';
import 'core/theme/app_theme.dart';
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

class _FashionOsAppState extends ConsumerState<FashionOsApp> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    if (widget.enablePush) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pushMessagingProvider).start();
      });
      // Centralized auth-driven navigation (§11/§23): a password-reset deep link
      // arrives as `passwordRecovery` → go set a new password.
      //
      // Sign-in / sign-out navigation (closing the auth screen, bouncing to the
      // gate) is handled DECLARATIVELY by the router redirect (refreshListenable
      // on isAuthenticatedProvider). We deliberately do NOT also pop() here: an
      // imperative pop racing the declarative redirect was a source of flaky
      // post-sign-in navigation. The redirect is the single source of truth.
      _authSub = ref.read(authRepositoryProvider).authStateChanges().listen((
        state,
      ) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          ref.read(goRouterProvider).pushNamed(AppRoute.setPasswordName);
        }
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
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
