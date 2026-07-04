import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/profile.dart';
import 'package:app/data/repositories/profile_repository.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/onboarding/onboarding_repository.dart';
import 'package:app/ui/auth/wtm_auth_screen.dart';
import 'package:app/ui/auth/wtm_onboarding_screen.dart';
import 'package:app/ui/home/wtm_mood.dart';

/// P10 gate coverage: the WTM auth/onboarding entry flow — splash routing,
/// email sign-in through the shipped controller, and onboarding completion.

class _FakeAuth extends AuthController {
  String? signedInEmail;

  @override
  Future<void> build() async {}

  @override
  Future<bool> signInEmail(String email, String password) async {
    signedInEmail = email;
    return true;
  }
}

class _FakeMoodRepo implements WtmMoodRepository {
  @override
  Future<double?> read() async => null;
  @override
  Future<void> write(double v) async {}
}

class _FakeOnboarding implements OnboardingRepository {
  bool marked = false;
  @override
  Future<bool> isComplete() async => false;
  @override
  Future<void> markComplete() async => marked = true;
}

class _FakeProfileRepo implements ProfileRepository {
  List<String>? savedTags;

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
    savedTags = styleTags;
    return const Profile(id: 'u1');
  }

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
    await tester.tap(finder.first);
    await settle(tester);
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    AuthController Function()? auth,
    _FakeOnboarding? onboarding,
    _FakeProfileRepo? profileRepo,
    String at = AppRoute.wtmSplash,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(false),
        onboardingSeenProvider.overrideWith((ref) => false),
        wtmMoodRepositoryProvider.overrideWithValue(_FakeMoodRepo()),
        if (auth != null) authControllerProvider.overrideWith(auth),
        if (onboarding != null)
          onboardingRepositoryProvider.overrideWithValue(onboarding),
        if (profileRepo != null)
          profileRepositoryProvider.overrideWithValue(profileRepo),
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

  testWidgets('splash routes a signed-out visitor to auth', (tester) async {
    await boot(tester, at: AppRoute.wtmSplash);
    // The splash waits ~700ms then routes; settle past it.
    await settle(tester);
    expect(find.byType(WtmAuthScreen), findsOneWidget);
  });

  testWidgets('email sign-in calls the auth controller', (tester) async {
    final auth = _FakeAuth();
    await boot(tester, auth: () => auth, at: AppRoute.wtmAuth);
    expect(find.byType(WtmAuthScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'me@wtm.test');
    await tester.enterText(find.byType(TextField).last, 'secret123');
    await tapAndSettle(tester, find.text('Sign In'));
    expect(auth.signedInEmail, 'me@wtm.test');
  });

  testWidgets('onboarding steps through and completes', (tester) async {
    final onboarding = _FakeOnboarding();
    final profile = _FakeProfileRepo();
    await boot(
      tester,
      onboarding: onboarding,
      profileRepo: profile,
      at: AppRoute.wtmOnboarding,
    );
    expect(find.byType(WtmOnboardingScreen), findsOneWidget);
    expect(find.text('How do you feel today?'), findsOneWidget);

    await tapAndSettle(tester, find.text('Next')); // → style tags
    await tapAndSettle(tester, find.text('Romantic')); // pick a tag
    await tapAndSettle(tester, find.text('Next')); // → body photo
    await tapAndSettle(tester, find.text('Enter Wear The Mood'));
    expect(onboarding.marked, isTrue);
    expect(profile.savedTags, contains('Romantic'));
  });
}
