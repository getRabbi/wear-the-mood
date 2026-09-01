import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/auth/auth_required.dart';
import 'package:app/core/auth/guest_capabilities.dart';
import 'package:app/core/auth/guest_session.dart';
import 'package:app/core/auth/protected_action.dart';
import 'package:app/core/media/media_source_policy.dart';
import 'package:app/core/media/media_upload_service.dart';
import 'package:app/core/platform/platform_capabilities.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/profile/avatar_service.dart';
import 'package:app/ui/auth/wtm_guest_preview.dart';
import 'package:app/ui/mirror/capture/live_camera.dart';
import 'package:app/ui/mirror/capture/wtm_live_capture_screen.dart';
import 'package:app/ui/mirror/wtm_body_photo_screen.dart';

import '../helpers/fake_dio.dart';

/// GUEST MODE IS UNCHANGED — and the new camera does not become a way around it.
///
/// Guest Mode itself is not touched by this work; these tests exist to prove
/// that, and to prove the one genuinely new question: a guest must not be able
/// to reach the live camera, and refusing them must cost ZERO — no camera
/// opened, no permission requested, no upload, no AI job, no credit.

/// Counts opens and enumerations. BOTH must stay at zero for a guest —
/// enumerating the lenses is itself a camera-stack call, and a guest must not
/// reach even that.
class _CountingOpener implements LiveCameraOpener {
  int opens = 0;
  int enumerations = 0;

  @override
  Future<Set<CameraLens>> availableLenses() async {
    enumerations++;
    throw StateError('a guest must never touch the camera stack');
  }

  @override
  Future<LiveCamera> open(CameraLens lens) async {
    opens++;
    throw StateError('a guest must never open the camera');
  }
}

class _CountingPicker implements ImagePicker {
  int calls = 0;

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
    throw StateError('a guest must never reach a picker');
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

/// Exercises the REAL guard with a REAL `Ref`, from inside the container under
/// test — the production wiring rather than a restatement of it.
final _bodyPhotoGuard = Provider<void Function()>(
  (ref) =>
      () => requireAuthenticatedUser(ref, ProtectedAction.bodyPhoto),
);

class _NullSupabase implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const ios = PlatformCapabilities(platform: TargetPlatform.iOS);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  group('the shipped guest policy is byte-for-byte what it was', () {
    test('the capability allowlist has not grown a capture entry', () {
      // If this work had loosened Guest Mode, it would show up here first.
      expect(GuestCapabilities.allowed, {
        GuestCapability.viewHome,
        GuestCapability.previewMood,
        GuestCapability.browseShop,
        GuestCapability.searchProducts,
        GuestCapability.viewProductDetail,
        GuestCapability.openMerchantLink,
        GuestCapability.readNewsroom,
        GuestCapability.viewGiveawayInfo,
        GuestCapability.viewLegal,
        GuestCapability.viewTryOnExplainer,
      });
    });

    test('the body-photo route is still denied to a guest', () {
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmBodyPhoto), isFalse);
      expect(
        GuestCapabilities.allowsRoute(AppRoute.wtmMirrorGarments),
        isFalse,
      );
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmMirrorMode), isFalse);
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmMirrorResult), isFalse);
      // The branch ROOT stays allowed — it shows the honest explainer, which
      // is the whole 5.1.1(v) argument and is unchanged.
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmMirror), isTrue);
    });

    test('a person image is still a bodyPhoto protected action', () {
      expect(
        ProtectedAction.forRoute(AppRoute.wtmBodyPhoto),
        ProtectedAction.bodyPhoto,
      );
      expect(
        ProtectedAction.forRoute(AppRoute.wtmMirrorGarments),
        ProtectedAction.tryOn,
      );
    });
  });

  group('a guest cannot reach the live camera', () {
    Future<ProviderContainer> bootGuest(
      WidgetTester tester, {
      required _CountingOpener opener,
      required _CountingPicker picker,
      String at = AppRoute.wtmMirror,
    }) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(ios),
          appSessionProvider.overrideWithValue(AppSessionState.guest),
          onboardingSeenProvider.overrideWith((ref) => true),
          liveCameraOpenerProvider.overrideWithValue(opener),
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
      await settle(tester);
      container.read(goRouterProvider).go(at);
      await settle(tester);
      return container;
    }

    testWidgets('the Try-On tab still shows the honest explainer', (
      tester,
    ) async {
      final opener = _CountingOpener();
      final picker = _CountingPicker();
      await bootGuest(tester, opener: opener, picker: picker);

      // The SHIPPED guest preview, unchanged — never a camera, never a
      // fabricated result.
      expect(find.byType(WtmGuestTryOnPreview), findsOneWidget);
      expect(find.byType(WtmLiveCaptureScreen), findsNothing);
      expect(find.byType(WtmBodyPhotoScreen), findsNothing);
      expect(opener.opens, 0);
      expect(opener.enumerations, 0, reason: 'not even a lens enumeration');
      expect(picker.calls, 0);
    });

    testWidgets('a deep link to the body-photo page opens no camera', (
      tester,
    ) async {
      final opener = _CountingOpener();
      final picker = _CountingPicker();
      await bootGuest(
        tester,
        opener: opener,
        picker: picker,
        at: AppRoute.wtmBodyPhoto,
      );

      expect(find.byType(WtmBodyPhotoScreen), findsNothing);
      expect(find.byType(WtmLiveCaptureScreen), findsNothing);
      expect(opener.opens, 0, reason: 'no camera permission is requested');
      expect(opener.enumerations, 0, reason: 'not even a lens enumeration');
      expect(picker.calls, 0, reason: 'no photo permission is requested');
    });

    testWidgets('a deep link to a mirror step opens no camera either', (
      tester,
    ) async {
      final opener = _CountingOpener();
      final picker = _CountingPicker();
      await bootGuest(
        tester,
        opener: opener,
        picker: picker,
        at: AppRoute.wtmMirrorGarments,
      );

      expect(opener.opens, 0);
      expect(opener.enumerations, 0, reason: 'not even a lens enumeration');
      expect(picker.calls, 0);
    });
  });

  group('a guest refusal costs nothing', () {
    ProviderContainer guest() {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(ios),
          appSessionProvider.overrideWithValue(AppSessionState.guest),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'the upload funnel refuses before ANY request reaches the wire',
      () async {
        final container = guest();
        var signRequests = 0;
        final (dio, _) = fakeDio((options) {
          signRequests++;
          return jsonResponse(const <String, Object?>{});
        });
        // The REAL service, wired exactly as `mediaUploadServiceProvider` wires
        // it in production: the guard runs ahead of BOTH the signing call and
        // the legacy fallback.
        final upload = MediaUploadService(
          dio,
          ensureAccount: container.read(_bodyPhotoGuard),
        );

        var legacyRuns = 0;
        await expectLater(
          upload.upload(
            bytes: Uint8List(4),
            sector: 'tryon_photo',
            legacy: () async {
              legacyRuns++;
              return 'never';
            },
          ),
          throwsA(isA<AuthRequiredException>()),
        );

        expect(signRequests, 0, reason: 'no bytes and no signature request');
        expect(legacyRuns, 0, reason: 'the legacy fallback is closed too');
      },
    );

    test('the denial names the body-photo action, for the right sheet', () {
      final container = guest();
      try {
        container.read(_bodyPhotoGuard)();
        fail('expected AuthRequiredException');
      } on AuthRequiredException catch (e) {
        expect(e.action, ProtectedAction.bodyPhoto);
        // And resuming after sign-in lands on the body-photo page, not on a
        // submit — no auto-capture, no auto-consent, no credit.
        expect(e.action.resumeRoute, AppRoute.wtmBodyPhoto);
      }
    });

    test('an authenticated user is NOT refused', () {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(ios),
          appSessionProvider.overrideWithValue(AppSessionState.authenticated),
          authUserIdProvider.overrideWithValue('u1'),
        ],
      );
      addTearDown(container.dispose);
      expect(() => container.read(_bodyPhotoGuard)(), returnsNormally);
    });
  });
}
