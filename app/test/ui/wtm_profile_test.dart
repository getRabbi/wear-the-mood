import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/profile.dart';
import 'package:app/data/models/public_profile.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/account_repository.dart';
import 'package:app/data/repositories/auth_repository.dart';
import 'package:app/data/repositories/profile_repository.dart';
import 'package:app/features/collections/local_collections.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/social/public_profile_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/profile/wtm_looks_screen.dart';
import 'package:app/ui/profile/wtm_profile_edit_screen.dart';
import 'package:app/ui/profile/wtm_profile_screen.dart';
import 'package:app/ui/profile/wtm_settings_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// P7 gate coverage: the real Profile + Settings on the shipped profile/account
/// lifecycle — segments, Edit Profile save, the Saved Looks gallery, and the
/// **in-app Delete Account** (double-confirm → server delete + sign-out).

const _profile = Profile(
  id: 'u1',
  displayName: 'Anika Rehman',
  bio: 'Fashion creator',
  styleTags: ['Romantic', 'Street', 'Bold'],
  isPublic: true,
);

const _publicProfile = PublicProfile(
  userId: 'u1',
  displayName: 'Anika Rehman',
  followerCount: 12000,
  followingCount: 320,
);

const _items = [
  WardrobeItem(id: 'w1', title: 'Blouse', category: 'tops'),
  WardrobeItem(id: 'w2', title: 'Trousers', category: 'bottoms'),
];

class _FakeProfileRepo implements ProfileRepository {
  Map<String, Object?>? lastUpdate;

  @override
  Future<Profile> updateProfile({
    String? displayName,
    String? phone,
    String? avatarUrl,
    String? profilePictureUrl,
    String? avatarObjectKey,
    String? profilePictureObjectKey,
    BodyData? bodyData,
    String? bio,
    List<String>? styleTags,
    bool? isPublic,
    bool? showPublicCloset,
  }) async {
    lastUpdate = {
      'displayName': displayName,
      'bio': bio,
      'styleTags': styleTags,
      'isPublic': isPublic,
    };
    return _profile;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeAccountRepo implements AccountRepository {
  bool deleted = false;
  bool exported = false;

  @override
  Future<void> deleteAccount() async => deleted = true;

  @override
  Future<Map<String, dynamic>> exportData() async {
    exported = true;
    return {'ok': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeAuthRepo implements AuthRepository {
  bool signedOut = false;

  @override
  Future<void> signOut() async => signedOut = true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    final target = finder.first;
    final rect = tester.getRect(target);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    if (rect.center.dy < 0 || rect.center.dy > screen.height - 100) {
      await tester.ensureVisible(target);
      await tester.pump();
    }
    await tester.tap(target);
    await settle(tester);
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    _FakeProfileRepo? profileRepo,
    _FakeAccountRepo? accountRepo,
    _FakeAuthRepo? authRepo,
    String at = AppRoute.wtmProfile,
  }) async {
    // Tall viewport so the lazy profile ListView renders all cards (membership +
    // invite friends) AND the segment grid below them without needing a scroll.
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        profileProvider.overrideWith((ref) => _profile),
        authUserIdProvider.overrideWithValue('u1'),
        publicProfileProvider('u1').overrideWith((ref) => _publicProfile),
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(_items),
        ),
        if (profileRepo != null)
          profileRepositoryProvider.overrideWithValue(profileRepo),
        if (accountRepo != null)
          accountRepositoryProvider.overrideWithValue(accountRepo),
        if (authRepo != null)
          authRepositoryProvider.overrideWithValue(authRepo),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    await settle(tester);
    container.read(goRouterProvider).go(at);
    await settle(tester);
    return container;
  }

  testWidgets('profile shows name, stats, Style DNA and Edit', (tester) async {
    await boot(tester);
    expect(find.byType(WtmProfileScreen), findsOneWidget);
    expect(find.text('Anika Rehman'), findsOneWidget);
    expect(find.text('12000'), findsOneWidget); // follower count
    expect(find.text('STYLE DNA'), findsOneWidget); // EyebrowLabel uppercases
    expect(find.text('EDIT PROFILE'), findsOneWidget); // GoldPill uppercases
  });

  testWidgets('segments switch between Closet, Looks and Posts', (
    tester,
  ) async {
    await boot(tester);
    // Closet default → real closet minis.
    expect(find.byType(FabricTile), findsWidgets);

    await tapAndSettle(tester, find.text('Looks'));
    expect(find.text('No saved looks yet.'), findsOneWidget);

    await tapAndSettle(tester, find.text('Posts'));
    expect(find.text('Share your first look with the community.'),
        findsOneWidget);
  });

  testWidgets('the ⋯ menu opens Settings', (tester) async {
    await boot(tester);
    await tapAndSettle(tester, find.byType(WtmIconButton).first);
    await settle(tester, 300);
    await tapAndSettle(tester, find.text('Settings'));
    expect(find.byType(WtmSettingsScreen), findsOneWidget);
    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('Delete Account'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
  });

  testWidgets('Edit Profile save patches the profile', (tester) async {
    final repo = _FakeProfileRepo();
    await boot(tester, profileRepo: repo);
    await tapAndSettle(tester, find.text('EDIT PROFILE')); // GoldPill
    expect(find.byType(WtmProfileEditScreen), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3)); // data-state form

    await tester.enterText(find.byType(TextField).first, 'Anika R');
    await tester.pump();
    final editScroll = find
        .descendant(
          of: find.byType(WtmProfileEditScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(find.text('Save'), 150,
        scrollable: editScroll);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(repo.lastUpdate, isNotNull);
    expect(repo.lastUpdate!['displayName'], 'Anika R');
  });

  testWidgets('GATE: Delete Account double-confirms then deletes + signs out', (
    tester,
  ) async {
    final account = _FakeAccountRepo();
    final auth = _FakeAuthRepo();
    await boot(
      tester,
      accountRepo: account,
      authRepo: auth,
      at: AppRoute.wtmSettings,
    );
    expect(find.byType(WtmSettingsScreen), findsOneWidget);

    await tapAndSettle(tester, find.text('Delete Account'));
    await tapAndSettle(tester, find.text('Continue')); // first confirm
    await tapAndSettle(tester, find.text('Delete forever')); // second confirm

    expect(account.deleted, isTrue);
    expect(auth.signedOut, isTrue);
  });

  testWidgets('data export pulls the account data', (tester) async {
    final account = _FakeAccountRepo();
    await boot(tester, accountRepo: account, at: AppRoute.wtmSettings);
    await tapAndSettle(tester, find.text('Privacy & data'));
    expect(account.exported, isTrue);
  });

  testWidgets('Saved Looks shows the empty invitation when there are none', (
    tester,
  ) async {
    await boot(tester, at: AppRoute.wtmLooks);
    expect(find.byType(WtmLooksScreen), findsOneWidget);
    expect(find.text('No looks yet'), findsOneWidget);
    expect(find.text('Open MoodMirror'), findsOneWidget);
  });

  testWidgets('Saved Looks renders a grid once looks exist', (tester) async {
    final container = await boot(tester, at: AppRoute.wtmProfile);
    container.read(savedLookRecordsProvider.notifier).add(
          SavedLook(
            id: 'l1',
            imageUrl: 'https://cdn.test/look.png',
            createdAt: DateTime.now(),
          ),
        );
    container.read(goRouterProvider).go(AppRoute.wtmLooks);
    await settle(tester);
    expect(find.byType(WtmLooksScreen), findsOneWidget);
    expect(find.text('No looks yet'), findsNothing);
  });
}
