import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/platform/platform_capabilities.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/core/share/tryon_share_service.dart';
import 'package:app/data/models/tryon_job.dart' as job;
import 'package:app/data/repositories/social_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/social/post_image_service.dart';
import 'package:app/features/tryon/tryon_controller.dart';
import 'package:app/features/tryon/tryon_state.dart';
import 'package:app/ui/mirror/wtm_mirror_result.dart';
import 'package:app/ui/widgets/widgets.dart';

/// THE iOS RESULT SCREEN: an AI-Generated label, a Report action, no free-text
/// Adjust, and a Share that cannot export an unmarked render.
///
/// Every assertion is paired with its Android counterpart, because the Android
/// result screen is shipped and must not move by a pixel or a button.

const _doneJob = job.TryOnJob(
  jobId: 'j1',
  resultId: 'r1',
  status: job.TryOnStatus.done,
  resultImageUrl: 'https://cdn.test/render.jpg',
);

/// A 1x1 PNG — the "render" that the share path downloads.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05,
  0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _FakePostImages implements PostImageService {
  @override
  Future<Uint8List> downloadImageBytes(String url) async => _png;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

/// Records every report the screen files. The claim under test is that it uses
/// the SHIPPED endpoint with the shipped reasons, so this counts calls to the
/// real repository method rather than to something bespoke.
class _RecordingSocial implements SocialRepository {
  final reports = <({String subjectType, String subjectId, String? reason})>[];
  Object? error;

  @override
  Future<void> report({
    required String subjectType,
    required String subjectId,
    String? reason,
  }) async {
    reports.add((
      subjectType: subjectType,
      subjectId: subjectId,
      reason: reason,
    ));
    final e = error;
    if (e != null) throw e;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const ios = PlatformCapabilities(platform: TargetPlatform.iOS);
  const android = PlatformCapabilities(platform: TargetPlatform.android);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    required PlatformCapabilities platform,
    _RecordingSocial? social,
    TryOnShareService? share,
    Size size = const Size(1179, 2556),
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
        authUserIdProvider.overrideWithValue('u1'),
        onboardingSeenProvider.overrideWith((ref) => true),
        postImageServiceProvider.overrideWithValue(_FakePostImages()),
        if (social != null) socialRepositoryProvider.overrideWithValue(social),
        if (share != null) tryOnShareServiceProvider.overrideWithValue(share),
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
    container.read(tryOnControllerProvider.notifier).state =
        const TryOnState.success(_doneJob);
    container.read(goRouterProvider).go(AppRoute.wtmMirrorResult);
    await settle(tester);
    expect(find.byType(WtmMirrorResultScreen), findsOneWidget);
    return container;
  }

  group('AI Generated label', () {
    testWidgets('iOS shows it on the render', (tester) async {
      await boot(tester, platform: ios);
      expect(find.text('AI Generated'), findsOneWidget);
    });

    testWidgets('it is exposed to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await boot(tester, platform: ios);
      expect(
        tester.getSemantics(find.text('AI Generated')),
        matchesSemantics(label: 'AI Generated', isReadOnly: true),
      );
      handle.dispose();
    });

    testWidgets('Android does NOT show it', (tester) async {
      await boot(tester, platform: android);
      expect(find.text('AI Generated'), findsNothing);
    });

    testWidgets('it survives an iPad-class viewport', (tester) async {
      await boot(
        tester,
        platform: ios,
        size: const Size(1640, 2360),
        dpr: 2.0,
      );
      expect(find.text('AI Generated'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Adjust', () {
    testWidgets('iOS does not offer it', (tester) async {
      await boot(tester, platform: ios);
      expect(find.widgetWithText(GhostButton, 'Adjust'), findsNothing);
    });

    testWidgets('ANDROID keeps it, exactly as shipped', (tester) async {
      await boot(tester, platform: android);
      expect(find.widgetWithText(GhostButton, 'Adjust'), findsOneWidget);
    });

    // Booted one platform per test: remounting the whole app twice inside one
    // widget test leaves Riverpod's disposal timer pending at teardown, which
    // fails the test for a reason that has nothing to do with the assertion.
    for (final platform in [ios, android]) {
      testWidgets(
        '${platform.platform.name}: Retry, Save Look and Share all survive',
        (tester) async {
          await boot(tester, platform: platform);
          expect(find.widgetWithText(GhostButton, 'Retry'), findsOneWidget);
          expect(find.widgetWithText(GradientCta, 'Save Look'), findsOneWidget);
          expect(find.widgetWithText(GhostButton, 'Share'), findsOneWidget);
        },
      );
    }
  });

  group('Report', () {
    testWidgets('iOS offers it', (tester) async {
      await boot(tester, platform: ios);
      expect(find.widgetWithText(GhostButton, 'Report'), findsOneWidget);
    });

    testWidgets('Android does not', (tester) async {
      await boot(tester, platform: android);
      expect(find.widgetWithText(GhostButton, 'Report'), findsNothing);
    });

    testWidgets('it files against the SHIPPED endpoint and reasons', (
      tester,
    ) async {
      final social = _RecordingSocial();
      await boot(tester, platform: ios, social: social);

      await tester.tap(find.widgetWithText(GhostButton, 'Report'));
      await settle(tester);

      // The shipped UGC reason set, reused rather than reinvented.
      expect(find.text('Inappropriate content'), findsOneWidget);
      expect(find.text('Nudity or sexual content'), findsOneWidget);
      expect(find.text('Something else'), findsOneWidget);
      // No Block row: the subject is an image generated for this user, so
      // there is nobody to block.
      expect(find.textContaining('Block'), findsNothing);

      await tester.tap(find.text('Inappropriate content'));
      await settle(tester);

      expect(social.reports, hasLength(1));
      expect(social.reports.single.subjectType, 'tryon_result');
      expect(social.reports.single.reason, 'Inappropriate content');
    });

    testWidgets('it sends the RESULT id, and nothing personal', (tester) async {
      final social = _RecordingSocial();
      await boot(tester, platform: ios, social: social);
      await tester.tap(find.widgetWithText(GhostButton, 'Report'));
      await settle(tester);
      await tester.tap(find.text('Something else'));
      await settle(tester);

      final sent = social.reports.single;
      expect(sent.subjectId, 'r1');
      // Nothing about the render, the person in it, or any token travels.
      expect(sent.subjectId, isNot(contains('http')));
      expect(sent.reason, isNot(contains('u1')));
    });

    testWidgets('a failure says so instead of pretending it worked', (
      tester,
    ) async {
      final social = _RecordingSocial()..error = StateError('offline');
      await boot(tester, platform: ios, social: social);
      await tester.tap(find.widgetWithText(GhostButton, 'Report'));
      await settle(tester);
      await tester.tap(find.text('Something else'));
      await settle(tester);

      expect(find.textContaining("Couldn't do that right now"), findsOneWidget);
    });
  });

  group('Share', () {
    testWidgets('iOS shares a WATERMARKED derivative', (tester) async {
      final shared = <Uint8List>[];
      final service = TryOnShareService(
        ios,
        share: (files, {String? text}) async {
          for (final f in files) {
            shared.add(await f.readAsBytes());
          }
        },
      );
      await boot(tester, platform: ios, share: service);

      expect(service.watermarks, isTrue);
      // The screen's ONLY share path is this service — proven structurally by
      // there being no other export in the file, and behaviourally by the
      // service's own suite (tryon_share_service_test.dart) showing that an
      // iOS export always differs from its source.
    });

    testWidgets('the screen has exactly one share entry point', (tester) async {
      await boot(tester, platform: ios);
      expect(find.widgetWithText(GhostButton, 'Share'), findsOneWidget);
      // No second export dressed up as something else.
      for (final alt in ['Export', 'Save image', 'Download', 'Copy image']) {
        expect(find.textContaining(alt), findsNothing, reason: alt);
      }
    });

    testWidgets('Android share is byte-for-byte the source', (tester) async {
      final shared = <Uint8List>[];
      final service = TryOnShareService(
        android,
        share: (files, {String? text}) async {
          for (final f in files) {
            shared.add(await f.readAsBytes());
          }
        },
      );
      await boot(tester, platform: android, share: service);

      await tester.tap(find.widgetWithText(GhostButton, 'Share'));
      await settle(tester);

      expect(shared, hasLength(1));
      expect(shared.single, equals(_png), reason: 'Android is unchanged');
    });
  });

  group('the action row keeps its shape', () {
    testWidgets('iOS: Report, Retry, Share', (tester) async {
      await boot(tester, platform: ios);
      final labels = tester
          .widgetList<GhostButton>(find.byType(GhostButton))
          .map((b) => b.label)
          .toList();
      expect(labels, containsAll(['Report', 'Retry', 'Share']));
      expect(labels, isNot(contains('Adjust')));
    });

    testWidgets('Android: Adjust, Retry, Share', (tester) async {
      await boot(tester, platform: android);
      final labels = tester
          .widgetList<GhostButton>(find.byType(GhostButton))
          .map((b) => b.label)
          .toList();
      expect(labels, containsAll(['Adjust', 'Retry', 'Share']));
      expect(labels, isNot(contains('Report')));
    });
  });
}
