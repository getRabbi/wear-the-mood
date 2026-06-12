import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/legal/legal_links.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/utils/link_launcher.dart';
import 'package:app/data/repositories/account_repository.dart';
import 'package:app/data/repositories/auth_repository.dart';
import 'package:app/features/profile/profile_screen.dart';
import 'package:app/l10n/app_localizations.dart';

class _FakeLinkLauncher implements LinkLauncher {
  final List<String> opened = [];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({this.exportResult = const {}});

  final Map<String, dynamic> exportResult;
  int exportCalls = 0;
  int deleteCalls = 0;

  @override
  Future<Map<String, dynamic>> exportData() async {
    exportCalls++;
    return exportResult;
  }

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
  }
}

class _FakeAuthRepository implements AuthRepository {
  bool signedOut = false;

  @override
  Future<void> signOut() async {
    signedOut = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Plain harness for the static states (no navigation triggered).
  Widget app() => MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ProfileScreen(),
  );

  // Router harness for flows that call context.go() (account deletion).
  GoRouter router() => GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Center(child: Text('home'))),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
    ],
  );

  Widget appRouter(GoRouter r) => MaterialApp.router(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: r,
  );

  testWidgets('guest sees a sign-in prompt', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [signedInEmailProvider.overrideWithValue(null)],
        child: app(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("You're browsing as a guest"), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('signed-in user sees their email and sign-out', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [signedInEmailProvider.overrideWithValue('a@b.com')],
        child: app(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Signed in as a@b.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('delete account asks for confirmation', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [signedInEmailProvider.overrideWithValue('a@b.com')],
        child: app(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete account & data'));
    await tester.pumpAndSettle();

    expect(find.text('Delete your account?'), findsOneWidget);
  });

  testWidgets('legal tiles open the hosted policy links', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final launcher = _FakeLinkLauncher();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signedInEmailProvider.overrideWithValue('a@b.com'),
          linkLauncherProvider.overrideWithValue(launcher),
        ],
        child: app(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Privacy policy'));
    await tester.tap(find.text('Privacy policy'));
    await tester.pump();
    await tester.ensureVisible(find.text('Acceptable use policy'));
    await tester.tap(find.text('Acceptable use policy'));
    await tester.pump();

    expect(launcher.opened, [LegalLinks.privacy, LegalLinks.acceptableUse]);
  });

  testWidgets('export copies all data to the clipboard', (tester) async {
    final clips = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clips.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final account = _FakeAccountRepository(
      exportResult: const {'user_id': 'u1', 'wardrobe_items': <dynamic>[]},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signedInEmailProvider.overrideWithValue('a@b.com'),
          accountRepositoryProvider.overrideWithValue(account),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
        child: app(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Export my data'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(account.exportCalls, 1);
    expect(clips.single, contains('wardrobe_items'));
    expect(find.text('Your data was copied to the clipboard'), findsOneWidget);
  });

  testWidgets('delete confirm wipes the account and signs out', (tester) async {
    final account = _FakeAccountRepository();
    final auth = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signedInEmailProvider.overrideWithValue('a@b.com'),
          accountRepositoryProvider.overrideWithValue(account),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: appRouter(router()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Delete account & data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Confirm via the dialog's destructive button (same label, a FilledButton).
    await tester.tap(
      find.widgetWithText(FilledButton, 'Delete account & data'),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(account.deleteCalls, 1);
    expect(auth.signedOut, isTrue);
    expect(find.text('home'), findsOneWidget); // navigated to a clean state
  });

  testWidgets('cancelling the delete dialog does nothing', (tester) async {
    final account = _FakeAccountRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signedInEmailProvider.overrideWithValue('a@b.com'),
          accountRepositoryProvider.overrideWithValue(account),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
        child: app(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Delete account & data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(account.deleteCalls, 0);
  });
}
