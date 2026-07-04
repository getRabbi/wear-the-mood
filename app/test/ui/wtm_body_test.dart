import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/profile.dart';
import 'package:app/data/models/studio_model_preset.dart';
import 'package:app/data/models/tryon_photo.dart';
import 'package:app/data/repositories/ai_studio_repository.dart';
import 'package:app/data/repositories/profile_repository.dart';
import 'package:app/data/repositories/tryon_photos_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/ui/mirror/wtm_body_photo_screen.dart';
import 'package:app/ui/mirror/wtm_body_source.dart';

/// Fix 2 + Fix 5 coverage: the WTM Atelier Body & Try-On manager — the consent
/// gate, the gallery + studio-model / mannequin picker, choosing the mannequin as
/// the body source, and Save persisting body data. All backends are faked so the
/// screen is deterministic and offline.

class _FakeProfileRepo implements ProfileRepository {
  BodyData? savedBody;
  ({String type, String version})? consent;

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
    if (bodyData != null) savedBody = bodyData;
    return const Profile(id: 'u1', biometricConsent: true);
  }

  @override
  Future<void> recordConsent({
    required String type,
    required String version,
  }) async {
    consent = (type: type, version: version);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _photo = TryonPhoto(
  id: 'p1',
  storagePath: 'avatars/u1/p1.jpg',
  signedUrl: 'https://cdn.test/body.png',
  qualityScore: 88,
  isSelected: true,
);

const _model = StudioModelPreset(
  id: 'm1',
  name: 'Runway Ava',
  imageUrl: 'https://cdn.test/model.png',
);

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
    required bool consented,
    List<TryonPhoto> photos = const [_photo],
    List<StudioModelPreset> models = const [_model],
    _FakeProfileRepo? repo,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(false),
        onboardingSeenProvider.overrideWith((ref) => true),
        profileProvider.overrideWith(
          (ref) async => Profile(
            id: 'u1',
            biometricConsent: consented,
            bodyData: const BodyData(gender: 'female', heightCm: 165),
          ),
        ),
        tryonPhotosProvider.overrideWith((ref) => photos),
        studioModelsProvider.overrideWith((ref) async => models),
        if (repo != null)
          profileRepositoryProvider.overrideWithValue(repo),
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
    container.read(goRouterProvider).go(AppRoute.wtmBodyPhoto);
    await settle(tester);
    return container;
  }

  testWidgets('consent gate records biometric consent (§10)', (tester) async {
    final repo = _FakeProfileRepo();
    await boot(tester, consented: false, repo: repo);
    expect(find.byType(WtmBodyPhotoScreen), findsOneWidget);
    // Gate is up: the agree CTA is shown.
    expect(find.text('I agree & continue'), findsOneWidget);

    await tapAndSettle(tester, find.text('I agree & continue'));
    expect(repo.consent, isNotNull);
    expect(repo.consent!.type, 'biometric');
  });

  testWidgets('manager renders gallery + model + mannequin body options',
      (tester) async {
    await boot(tester, consented: true);
    expect(find.byType(WtmBodyPhotoScreen), findsOneWidget);
    // The studio model + the always-available mannequin are both offered (Fix 5).
    expect(find.text('Runway Ava'), findsOneWidget);
    expect(find.text('Mannequin'), findsOneWidget);
  });

  testWidgets('choosing the mannequin sets the body source (Fix 5)',
      (tester) async {
    final container = await boot(tester, consented: true);
    expect(container.read(wtmBodyChoiceProvider), isA<WtmBodyPhoto>());

    await tapAndSettle(tester, find.text('Mannequin'));
    expect(container.read(wtmBodyChoiceProvider), isA<WtmBodyMannequin>());
  });

  testWidgets('Save persists body data', (tester) async {
    final repo = _FakeProfileRepo();
    await boot(tester, consented: true, repo: repo);

    await tapAndSettle(tester, find.text('Save'));
    expect(repo.savedBody, isNotNull);
    expect(repo.savedBody!.gender, 'female');
    expect(repo.savedBody!.heightCm, 165);
  });
}
