import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/core/router/routes.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/auth/auth_screen.dart';
import 'package:app/l10n/app_localizations.dart';

/// Stub controller: sign-in fails with invalid credentials; sign-up reports the
/// email is already registered — exercising the error-mapping + recovery paths
/// without touching Supabase.
class _StubAuthController extends AuthController {
  @override
  Future<void> build() async {}

  @override
  Future<bool> signInEmail(String email, String password) async {
    state = AsyncError(
      const AuthException('Invalid login credentials',
          code: 'invalid_credentials'),
      StackTrace.current,
    );
    return false;
  }

  @override
  Future<SignUpResult> signUpEmail(String email, String password) async {
    state = const AsyncData(null);
    return SignUpResult.alreadyRegistered;
  }
}

/// Controller whose sign-in succeeds — exercises the navigate-to-home path.
class _OkAuthController extends AuthController {
  @override
  Future<void> build() async {}

  @override
  Future<bool> signInEmail(String email, String password) async {
    state = const AsyncData(null);
    return true;
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget app() => ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AuthScreen(),
    ),
  );

  Widget appWith(AuthController Function() make) => ProviderScope(
    overrides: [authControllerProvider.overrideWith(make)],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AuthScreen(),
    ),
  );

  testWidgets('renders the sign-in form by default', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('switches to the sign-up form via the segmented toggle', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Tap the "Sign up" segment of the mode switcher.
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget); // title
    expect(find.text('Create account'), findsOneWidget); // submit CTA
  });

  testWidgets('shows a validation error for an invalid email', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log in')); // sign-in submit button
    await tester.pump();

    expect(find.text('Enter a valid email.'), findsOneWidget);
  });

  testWidgets('sign-up flags mismatched confirm password', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign up')); // switch to sign-up mode
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.enterText(find.byType(TextFormField).at(2), 'password2');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text("Passwords don't match."), findsOneWidget);
  });

  testWidgets('sign-in failure shows a clear mapped error, not the raw string', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(_StubAuthController.new));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(
      find.text('Incorrect email or password. Please try again.'),
      findsOneWidget,
    );
    // The raw Supabase string is never surfaced.
    expect(find.text('Invalid login credentials'), findsNothing);
    // Loading cleared — no stuck spinner.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('sign-up with an existing email flips to sign-in with a message', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(_StubAuthController.new));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.enterText(find.byType(TextFormField).at(2), 'password1');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    // Flipped back to the sign-in form (title) and surfaced the reason.
    expect(find.text('Welcome back'), findsOneWidget);
    expect(
      find.text('That email is already registered. Try signing in instead.'),
      findsWidgets,
    );
  });

  testWidgets('a successful sign-in navigates to home (leaves the auth screen)', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoute.auth,
      routes: [
        GoRoute(
          path: AppRoute.home,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: AppRoute.auth,
          builder: (_, _) => const AuthScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(_OkAuthController.new)],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    // Landed on home; the auth screen is gone.
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
  });
}
