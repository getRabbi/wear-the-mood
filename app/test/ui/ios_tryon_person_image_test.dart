import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/auth/pending_auth_intent.dart';
import 'package:app/core/auth/protected_action.dart';
import 'package:app/core/media/media_source_policy.dart';
import 'package:app/core/platform/platform_capabilities.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/profile.dart';
import 'package:app/data/models/studio_model_preset.dart';
import 'package:app/data/models/tryon_photo.dart';
import 'package:app/data/repositories/ai_studio_repository.dart';
import 'package:app/data/repositories/profile_repository.dart';
import 'package:app/data/repositories/tryon_photos_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/profile/avatar_service.dart';
import 'package:app/features/wardrobe/wardrobe_image_service.dart';
import 'package:app/ui/mirror/capture/wtm_live_capture_screen.dart';
import 'package:app/ui/mirror/wtm_body_photo_screen.dart';

/// THE GATE: on iOS/iPadOS a Try-On person image can only be a fresh live
/// front-camera capture.
///
/// Every counter in this file that names the Photo Library asserts **zero**.
/// That is the whole claim — not "the button is hidden", but "the picker is
/// never invoked, so iOS is never asked for Photo Library permission, so no
/// file is copied, no upload starts, no job is created and no credit moves".
///
/// The counterweight tests matter just as much: Android's Try-On is unchanged,
/// and iOS Closet still has its gallery upload.

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Counts EVERY call, whatever the source. The point of the iOS assertions is
/// that this number stays at zero, so it must not quietly succeed.
class _CountingPicker implements ImagePicker {
  int calls = 0;
  final sources = <ImageSource>[];

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    calls++;
    sources.add(source);
    return XFile('picked.jpg');
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeProfileRepo implements ProfileRepository {
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
  }) async => const Profile(id: 'u1', biometricConsent: true);

  @override
  Future<void> recordConsent({
    required String type,
    required String version,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName}');
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

  const ios = PlatformCapabilities(platform: TargetPlatform.iOS);
  const android = PlatformCapabilities(platform: TargetPlatform.android);

  // -------------------------------------------------------------------------
  // LAYER 3 — the controller / media service.
  //
  // The last line of defence and the most important one: it holds even if a
  // caller gets past the UI and the navigation gates.
  // -------------------------------------------------------------------------
  group('service layer — AvatarService.pick', () {
    AvatarService build(PlatformCapabilities platform, _CountingPicker picker) =>
        AvatarService(
          // The Supabase client is never touched: the refusal happens before
          // any I/O, which is precisely what is being asserted.
          _NullSupabase(),
          picker: picker,
          sourcePolicy: MediaSourcePolicy(platform),
        );

    test('iOS refuses a GALLERY person image before the picker is opened', () {
      final picker = _CountingPicker();
      final service = build(ios, picker);

      expect(
        () => service.pick(ImageSource.gallery),
        throwsA(isA<UnsupportedImageSourceException>()),
      );
      expect(picker.calls, 0, reason: 'the Photo Library was never invoked');
    });

    test('iOS ALSO refuses the system camera sheet', () {
      // Not pedantry: the system sheet cannot carry the full-body guide or the
      // countdown, so accepting it would let a forgotten call site silently
      // downgrade the experience while still looking correct.
      final picker = _CountingPicker();
      final service = build(ios, picker);

      expect(
        () => service.pick(ImageSource.camera),
        throwsA(isA<UnsupportedImageSourceException>()),
      );
      expect(picker.calls, 0);
    });

    test('the refusal names the purpose and the rule', () {
      final service = build(ios, _CountingPicker());
      try {
        service.pick(ImageSource.gallery);
        fail('expected a refusal');
      } on UnsupportedImageSourceException catch (e) {
        expect(e.purpose, ImagePurpose.tryOnPersonImage);
        expect(e.rule, MediaSourceRule.liveFrontCameraOnly);
        expect(e.code, 'UNSUPPORTED_IMAGE_SOURCE');
      }
    });

    test('iOS reports that it requires a live capture', () {
      expect(build(ios, _CountingPicker()).requiresLiveCapture, isTrue);
    });

    test('ANDROID passes both sources straight through, unchanged', () async {
      final picker = _CountingPicker();
      final service = build(android, picker);

      expect(await service.pick(ImageSource.gallery), isNotNull);
      expect(await service.pick(ImageSource.camera), isNotNull);
      expect(picker.calls, 2);
      expect(picker.sources, [ImageSource.gallery, ImageSource.camera]);
      expect(service.requiresLiveCapture, isFalse);
    });

    test('no other platform is restricted', () async {
      for (final platform in TargetPlatform.values) {
        if (platform == TargetPlatform.iOS) continue;
        final picker = _CountingPicker();
        final service = build(
          PlatformCapabilities(platform: platform),
          picker,
        );
        expect(
          await service.pick(ImageSource.gallery),
          isNotNull,
          reason: '${platform.name} must be unchanged',
        );
        expect(picker.calls, 1);
      }
    });
  });

  // -------------------------------------------------------------------------
  // LAYER 1 — the UI / source selection.
  // -------------------------------------------------------------------------
  group('Body & Try-On page', () {
    Future<ProviderContainer> boot(
      WidgetTester tester, {
      required PlatformCapabilities platform,
      _CountingPicker? picker,
      Size size = const Size(1179, 2556), // iPhone 15 Pro
      double dpr = 3.0,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(platform),
          isAuthenticatedProvider.overrideWithValue(true),
          onboardingSeenProvider.overrideWith((ref) => true),
          profileProvider.overrideWith(
            (ref) async => const Profile(id: 'u1', biometricConsent: true),
          ),
          tryonPhotosProvider.overrideWith((ref) => const [_photo]),
          studioModelsProvider.overrideWith((ref) async => const [_model]),
          profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
          if (picker != null)
            avatarServiceProvider.overrideWith(
              (ref) => AvatarService(
                _NullSupabase(),
                picker: picker,
                sourcePolicy: ref.watch(mediaSourcePolicyProvider),
              ),
            ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FashionOsApp(),
        ),
      );
      await _settle(tester);
      container.read(goRouterProvider).go(AppRoute.wtmBodyPhoto);
      await _settle(tester);
      return container;
    }

    testWidgets('iOS: tapping Add opens the LIVE CAMERA, never a source sheet', (
      tester,
    ) async {
      final picker = _CountingPicker();
      await boot(tester, platform: ios, picker: picker);
      expect(find.byType(WtmBodyPhotoScreen), findsOneWidget);

      await tester.tap(_addTile, warnIfMissed: false);
      await _settle(tester);

      // The live capture screen, on its preparation step.
      expect(find.byType(WtmLiveCaptureScreen), findsOneWidget);
      expect(find.text('Set up your shot'), findsOneWidget);
      // No sheet, therefore no Gallery row and no Camera row.
      expect(find.text('Gallery'), findsNothing);
      expect(find.text('Camera'), findsNothing);
      expect(picker.calls, 0);
    });

    testWidgets('iOS: the page says WHY there is no gallery option', (
      tester,
    ) async {
      await boot(tester, platform: ios);
      expect(
        find.textContaining('taken live with the front camera'),
        findsOneWidget,
      );
    });

    testWidgets('iOS: no Gallery affordance exists anywhere on the page', (
      tester,
    ) async {
      await boot(tester, platform: ios);
      expect(find.text('Gallery'), findsNothing);
      expect(find.text('Select from Gallery'), findsNothing);
      expect(find.textContaining('Browse'), findsNothing);
      expect(find.textContaining('Import'), findsNothing);
      expect(find.textContaining('Files'), findsNothing);
    });

    testWidgets('ANDROID: the Camera/Gallery sheet is exactly as it was', (
      tester,
    ) async {
      final picker = _CountingPicker();
      await boot(tester, platform: android, picker: picker);

      await tester.tap(_addTile, warnIfMissed: false);
      await _settle(tester);

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.byType(WtmLiveCaptureScreen), findsNothing);
    });

    testWidgets('ANDROID: the iOS explainer is absent', (tester) async {
      await boot(tester, platform: android);
      expect(
        find.textContaining('taken live with the front camera'),
        findsNothing,
      );
    });

    testWidgets('CONSENT still gates the camera — the gate did not move', (
      tester,
    ) async {
      // Consent v2 is frozen, and the live camera must sit BEHIND it exactly
      // where the picker did. Without consent the manager never builds, so
      // there is no Add tile to tap and no camera to open.
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final picker = _CountingPicker();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(ios),
          isAuthenticatedProvider.overrideWithValue(true),
          onboardingSeenProvider.overrideWith((ref) => true),
          profileProvider.overrideWith(
            // NOT consented.
            (ref) async => const Profile(id: 'u1', biometricConsent: false),
          ),
          tryonPhotosProvider.overrideWith((ref) => const [_photo]),
          studioModelsProvider.overrideWith((ref) async => const [_model]),
          profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
          avatarServiceProvider.overrideWith(
            (ref) => AvatarService(
              _NullSupabase(),
              picker: picker,
              sourcePolicy: ref.watch(mediaSourcePolicyProvider),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FashionOsApp(),
        ),
      );
      await _settle(tester);
      container.read(goRouterProvider).go(AppRoute.wtmBodyPhoto);
      await _settle(tester);

      // The shipped consent gate, unchanged.
      expect(find.text('I agree & continue'), findsOneWidget);
      expect(_addTile, findsNothing);
      expect(find.byType(WtmLiveCaptureScreen), findsNothing);
      expect(picker.calls, 0);
    });

    testWidgets('rapid taps open ONE camera, not a stack of them', (
      tester,
    ) async {
      // The gallery tile is a plain GestureDetector and the push is an await,
      // so a double tap is the obvious way to end up with two capture screens
      // — and, downstream, two uploads of two different photos.
      final picker = _CountingPicker();
      await boot(tester, platform: ios, picker: picker);

      await tester.tap(_addTile, warnIfMissed: false);
      await tester.tap(_addTile, warnIfMissed: false);
      await tester.tap(_addTile, warnIfMissed: false);
      await _settle(tester);

      expect(find.byType(WtmLiveCaptureScreen), findsOneWidget);
      expect(picker.calls, 0);
    });

    testWidgets('iPad-class viewport reaches the same live camera', (
      tester,
    ) async {
      // iPad Air 11-inch, portrait — the reviewer's environment.
      final picker = _CountingPicker();
      await boot(
        tester,
        platform: ios,
        picker: picker,
        size: const Size(1640, 2360),
        dpr: 2.0,
      );

      await tester.tap(_addTile, warnIfMissed: false);
      await _settle(tester);

      expect(find.byType(WtmLiveCaptureScreen), findsOneWidget);
      expect(find.text('Gallery'), findsNothing);
      expect(picker.calls, 0);
    });
  });

  // -------------------------------------------------------------------------
  // MoodMirror Step 1 — the OTHER place that used to say "Gallery".
  // -------------------------------------------------------------------------
  group('MoodMirror step 1', () {
    Future<void> boot(
      WidgetTester tester,
      PlatformCapabilities platform,
    ) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(platform),
          isAuthenticatedProvider.overrideWithValue(true),
          onboardingSeenProvider.overrideWith((ref) => true),
          profileProvider.overrideWith(
            (ref) async => const Profile(id: 'u1', biometricConsent: true),
          ),
          // NO photos: this is the state that offered "Select from Gallery".
          tryonPhotosProvider.overrideWith((ref) => const <TryonPhoto>[]),
          studioModelsProvider.overrideWith((ref) async => const [_model]),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FashionOsApp(),
        ),
      );
      await _settle(tester);
      container.read(goRouterProvider).go(AppRoute.wtmMirror);
      await _settle(tester);
    }

    testWidgets('iOS offers "Take a live photo" and NOT "Select from Gallery"', (
      tester,
    ) async {
      await boot(tester, ios);
      expect(find.text('Take a live photo'), findsOneWidget);
      expect(find.text('Select from Gallery'), findsNothing);
    });

    testWidgets('Android keeps Upload Photo AND Select from Gallery', (
      tester,
    ) async {
      await boot(tester, android);
      expect(find.text('Upload Photo'), findsOneWidget);
      expect(find.text('Select from Gallery'), findsOneWidget);
      expect(find.text('Take a live photo'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // LAYER 2 — navigation and pending intents.
  // -------------------------------------------------------------------------
  group('deep links and post-auth resume cannot restore a gallery photo', () {
    test('a pending intent carries an action and a public id, nothing else', () {
      // Structural: there is no field on the intent that could hold a file
      // path, a picked photo or a draft, so "resume restores the old gallery
      // selection" is not expressible rather than merely not implemented.
      const intent = PendingAuthIntent(action: ProtectedAction.bodyPhoto);
      expect(intent.toJson().keys, ['action']);

      const withId = PendingAuthIntent(
        action: ProtectedAction.saveProduct,
        resourceId: 'p1',
      );
      expect(withId.toJson().keys.toSet(), {'action', 'id'});
    });

    test('a hand-crafted intent carrying a path is stripped on read', () {
      final restored = PendingAuthIntent.fromJson({
        'action': 'bodyPhoto',
        'id': '/var/mobile/Media/DCIM/IMG_0001.HEIC',
        'photoPath': '/var/mobile/Media/DCIM/IMG_0001.HEIC',
      });
      // The unknown key is ignored outright, and `bodyPhoto` does not take a
      // resource id — so nothing about a device photo survives.
      expect(restored, isNotNull);
      expect(restored!.action, ProtectedAction.bodyPhoto);
      expect(restored.toJson().containsKey('photoPath'), isFalse);
    });

    test('resuming a person-image intent lands on the PAGE, not a submit', () {
      // The page then applies the platform policy like any other entry: on iOS
      // that is the live camera, so a resume cannot reach a picker either.
      expect(
        ProtectedAction.bodyPhoto.resumeRoute,
        AppRoute.wtmBodyPhoto,
      );
      expect(ProtectedAction.tryOn.resumeRoute, AppRoute.wtmMirror);
      expect(ProtectedAction.bodyPhoto.resumeNeedsResourceId, isFalse);
    });

    testWidgets('an authenticated deep link to the page still has no gallery', (
      tester,
    ) async {
      // The exact shape of a post-auth resume: land on the body-photo route
      // directly, with a session, on iOS.
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final picker = _CountingPicker();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(ios),
          isAuthenticatedProvider.overrideWithValue(true),
          onboardingSeenProvider.overrideWith((ref) => true),
          profileProvider.overrideWith(
            (ref) async => const Profile(id: 'u1', biometricConsent: true),
          ),
          tryonPhotosProvider.overrideWith((ref) => const [_photo]),
          studioModelsProvider.overrideWith((ref) async => const [_model]),
          profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
          avatarServiceProvider.overrideWith(
            (ref) => AvatarService(
              _NullSupabase(),
              picker: picker,
              sourcePolicy: ref.watch(mediaSourcePolicyProvider),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FashionOsApp(),
        ),
      );
      await _settle(tester);
      container.read(goRouterProvider).go(AppRoute.wtmBodyPhoto);
      await _settle(tester);

      expect(find.byType(WtmBodyPhotoScreen), findsOneWidget);
      expect(find.text('Gallery'), findsNothing);
      expect(picker.calls, 0);
    });
  });

  // -------------------------------------------------------------------------
  // CLOSET REGRESSION — the thing that must NOT have changed.
  // -------------------------------------------------------------------------
  group('closet garment upload is untouched', () {
    test('the garment service has no source policy at all', () {
      // Structural proof, and the strongest kind available: WardrobeImageService
      // takes no policy, so no platform rule can reach it. A future change that
      // tried to restrict garments would have to alter this constructor, which
      // is a visible diff rather than a silent behaviour change.
      final picker = _CountingPicker();
      final service = WardrobeImageService(_NullSupabase(), picker: picker);
      expect(service, isA<WardrobeImageService>());
    });

    test('iOS closet garments may still use the Photo Library', () async {
      final picker = _CountingPicker();
      final service = WardrobeImageService(_NullSupabase(), picker: picker);
      // Compression is a platform channel, so the call is expected to fail
      // AFTER the pick. What is asserted is that the pick happened at all.
      try {
        await service.pickAndCompress(ImageSource.gallery);
      } catch (_) {
        /* flutter_image_compress has no test implementation */
      }
      expect(picker.calls, 1);
      expect(picker.sources.single, ImageSource.gallery);
    });

    test('the policy says so too, on both platforms', () {
      for (final platform in [ios, android]) {
        final policy = MediaSourcePolicy(platform);
        expect(
          policy.allowsPhotoLibrary(ImagePurpose.closetGarmentImage),
          isTrue,
          reason: '${platform.platform.name} closet must keep its gallery',
        );
      }
    });

    test('a closet file is a GARMENT purpose, never a person purpose', () {
      // The two purposes are distinct enum values, so a garment can never be
      // classified into the restricted branch by accident.
      expect(
        ImagePurpose.closetGarmentImage,
        isNot(ImagePurpose.tryOnPersonImage),
      );
      expect(
        MediaSourcePolicy(ios).forPurpose(ImagePurpose.closetGarmentImage),
        MediaSourceRule.deviceCameraAndLibrary,
      );
    });
  });
}

/// The gallery's "Add photo" tile — the one control that starts a person
/// capture. Found by its semantic label rather than its widget type, so the
/// test breaks if the affordance is renamed rather than silently tapping
/// whatever happens to be last on screen.
final _addTile = find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Add photo',
  ),
  matching: find.byType(GestureDetector),
);

Future<void> _settle(WidgetTester tester, [int ms = 900]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump();
}

/// A Supabase client that throws on any use. Every test here asserts the
/// refusal happens BEFORE storage is touched, so any call is a failed test.
class _NullSupabase implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('storage must not be reached: ${i.memberName}');
}
