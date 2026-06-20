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
import 'package:app/data/models/outfit.dart';
import 'package:app/data/models/profile.dart';
import 'package:app/data/models/tryon_result.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/account_repository.dart';
import 'package:app/data/repositories/auth_repository.dart';
import 'package:app/data/repositories/profile_repository.dart';
import 'package:app/data/repositories/social_repository.dart';
import 'package:app/data/repositories/tryon_repository.dart';
import 'package:app/features/collections/local_collections.dart';
import 'package:app/features/outfits/outfit_providers.dart';
import 'package:app/features/profile/profile_picture_service.dart';
import 'package:app/features/profile/profile_screen.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/l10n/app_localizations.dart';

import '../helpers/fake_dio.dart';

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

  // Wraps a child in a ProviderScope that keeps the signed-in profile fully
  // offline: a stub profile, empty stats/feed, and no signed-photo network call.
  Widget signedInScope(
    Widget child, {
    AccountRepository? account,
    AuthRepository? auth,
    LinkLauncher? launcher,
  }) {
    final (dio, _) = fakeDio((_) => jsonResponse(<Object>[]));
    return ProviderScope(
      overrides: [
        signedInEmailProvider.overrideWithValue('a@b.com'),
        currentUserProvider.overrideWithValue(null),
        profileProvider.overrideWith(
          (ref) async => const Profile(id: 'u1', displayName: 'Mim'),
        ),
        profilePictureSignedUrlProvider.overrideWith((ref) async => null),
        wardrobeItemsProvider.overrideWith((ref) async => const <WardrobeItem>[]),
        outfitsProvider.overrideWith((ref) async => const <Outfit>[]),
        tryOnResultsProvider.overrideWith((ref) async => const <TryonResult>[]),
        socialRepositoryProvider.overrideWithValue(SocialRepository(dio)),
        if (account != null)
          accountRepositoryProvider.overrideWithValue(account),
        if (auth != null) authRepositoryProvider.overrideWithValue(auth),
        if (launcher != null) linkLauncherProvider.overrideWithValue(launcher),
      ],
      child: child,
    );
  }

  Widget app() => MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ProfileScreen(),
  );

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

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

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

  testWidgets('signed-in user sees their profile and sign-out under Settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      signedInScope(app(), auth: _FakeAuthRepository()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Display name in the header (full email never appears in public header).
    expect(find.text('Mim'), findsWidgets);
    expect(find.text('a@b.com'), findsNothing);

    await openSettings(tester);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Personal details'), findsOneWidget);
  });

  testWidgets('delete account asks for confirmation', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      signedInScope(
        app(),
        account: _FakeAccountRepository(),
        auth: _FakeAuthRepository(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await openSettings(tester);
    await tester.tap(find.text('Delete account & data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Delete your account?'), findsOneWidget);
  });

  testWidgets('legal tiles open the hosted policy links', (tester) async {
    tester.view.physicalSize = const Size(1100, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final launcher = _FakeLinkLauncher();
    await tester.pumpWidget(
      signedInScope(app(), launcher: launcher, auth: _FakeAuthRepository()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await openSettings(tester);
    await tester.ensureVisible(find.text('Privacy policy'));
    await tester.tap(find.text('Privacy policy'));
    await tester.pump();
    await tester.ensureVisible(find.text('Acceptable use policy'));
    await tester.tap(find.text('Acceptable use policy'));
    await tester.pump();

    expect(launcher.opened, [LegalLinks.privacy, LegalLinks.acceptableUse]);
  });

  testWidgets('export copies all data to the clipboard', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
      signedInScope(app(), account: account, auth: _FakeAuthRepository()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await openSettings(tester);
    await tester.tap(find.text('Export my data'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(account.exportCalls, 1);
    expect(clips.single, contains('wardrobe_items'));
    expect(find.text('Your data was copied to the clipboard'), findsOneWidget);
  });

  testWidgets('delete confirm wipes the account and signs out', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final account = _FakeAccountRepository();
    final auth = _FakeAuthRepository();
    await tester.pumpWidget(
      signedInScope(appRouter(router()), account: account, auth: auth),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await openSettings(tester);
    await tester.tap(find.text('Delete account & data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Confirm via the sheet's destructive button (the tile behind it shares the
    // label, so target the last match — the sheet is pushed on top).
    await tester.tap(find.text('Delete account & data').last);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(account.deleteCalls, 1);
    expect(auth.signedOut, isTrue);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('cancelling the delete sheet does nothing', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final account = _FakeAccountRepository();
    await tester.pumpWidget(
      signedInScope(app(), account: account, auth: _FakeAuthRepository()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await openSettings(tester);
    await tester.tap(find.text('Delete account & data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(account.deleteCalls, 0);
  });

  testWidgets('tapping a saved look opens it full-screen (Issue 3)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Keep the saved-look store in memory (no encrypted storage in tests).
    const storageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      storageChannel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        storageChannel,
        null,
      ),
    );

    final (dio, _) = fakeDio((_) => jsonResponse(<Object>[]));
    final container = ProviderContainer(
      overrides: [
        signedInEmailProvider.overrideWithValue('a@b.com'),
        currentUserProvider.overrideWithValue(null),
        profileProvider.overrideWith(
          (ref) async => const Profile(id: 'u1', displayName: 'Mim'),
        ),
        profilePictureSignedUrlProvider.overrideWith((ref) async => null),
        wardrobeItemsProvider.overrideWith((ref) async => const <WardrobeItem>[]),
        outfitsProvider.overrideWith((ref) async => const <Outfit>[]),
        tryOnResultsProvider.overrideWith((ref) async => const <TryonResult>[]),
        socialRepositoryProvider.overrideWithValue(SocialRepository(dio)),
      ],
    );
    addTearDown(container.dispose);

    // A saved try-on look with a durable URL.
    container.read(savedLookRecordsProvider.notifier).add(
          SavedLook(
            id: 'l1',
            imageUrl: 'https://cdn.example/look.jpg',
            createdAt: DateTime(2026),
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: app()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Open the Saved tab ("Saved" also labels a stat, so scope to the TabBar).
    await tester.tap(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Saved'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The look tile is now tappable; tapping opens the full-screen viewer.
    final tile = find.byWidgetPredicate(
      (w) => w is Hero && '${w.tag}'.startsWith('look_'),
    );
    expect(tile, findsOneWidget);
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
}
