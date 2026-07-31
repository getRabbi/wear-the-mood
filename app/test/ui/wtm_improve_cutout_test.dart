import 'dart:convert';
import 'dart:io';

import 'package:app/core/config/feature_gates.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/closet/wtm_cutout_gate.dart';
import 'package:app/ui/closet/wtm_garment_detail_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_dio.dart';

/// "Improve edges" — the free automatic BiRefNet re-run (local BG §6.4, §9.4, §9.5).
///
/// Two things are easy to get wrong and are pinned here:
///
///  * **Improve edges and Fix cutout are different features.** One re-runs the
///    server cutout; the other opens the manual editor. They have separate gates on
///    both sides of the wire, and enabling one must never surface the other.
///  * **A previous valid cutout survives everything.** It stays displayed while an
///    improvement is queued or processing, and it is still displayed if the
///    improvement fails — a user must not lose a good cutout by asking for better.
void main() {
  WardrobeItem item({
    String? cutoutUrl = 'https://cdn/c.png',
    String? status = 'done',
    String? thumbnailUrl,
    String? imageUrl = 'https://cdn/o.jpg',
  }) => WardrobeItem(
    id: 'w1',
    cutoutUrl: cutoutUrl,
    cutoutStatus: status,
    thumbnailUrl: thumbnailUrl,
    imageUrl: imageUrl,
  );

  group('canImproveCutout is a distinct rule from canFixCutout', () {
    test('needs the gate on and a cutout to improve', () {
      expect(canImproveCutout(item(), enabled: true), isTrue);
      expect(canImproveCutout(item(), enabled: false), isFalse);
      expect(canImproveCutout(item(cutoutUrl: null), enabled: true), isFalse);
      expect(canImproveCutout(null, enabled: true), isFalse);
    });

    test('is hidden while an attempt is already in flight', () {
      // Offering it mid-attempt would invite the duplicate tap the server rejects.
      for (final status in ['queued', 'processing']) {
        expect(
          canImproveCutout(item(status: status), enabled: true),
          isFalse,
          reason: status,
        );
      }
    });

    test('is offered again for a FAILED item — the likeliest reason to tap it', () {
      expect(canImproveCutout(item(status: 'failed'), enabled: true), isTrue);
    });

    test('the two gates are independent', () {
      final piece = item();
      // Editor on, local off: Fix cutout only.
      expect(canFixCutout(piece, enabled: true), isTrue);
      expect(canImproveCutout(piece, enabled: false), isFalse);
      // Local on, editor off: Improve edges only.
      expect(canFixCutout(piece, enabled: false), isFalse);
      expect(canImproveCutout(piece, enabled: true), isTrue);
    });

    test('neither is offered for a piece with no cutout at all', () {
      final raw = item(cutoutUrl: null, status: 'queued');
      expect(canFixCutout(raw, enabled: true), isFalse);
      expect(canImproveCutout(raw, enabled: true), isFalse);
    });
  });

  group('the display keeps the old cutout through an improvement (§9.5)', () {
    test('a queued improvement still renders the existing cutout', () {
      final improving = item(status: 'queued');
      expect(improving.displayImageUrl, 'https://cdn/c.png');
      expect(improving.isProcessingCutout, isTrue);
    });

    test('a processing improvement still renders the existing cutout', () {
      expect(item(status: 'processing').displayImageUrl, 'https://cdn/c.png');
    });

    test('a FAILED improvement does not fall back to the original', () {
      // The server never clears cutout_url on failure, and displayImageUrl does not
      // consult cutoutStatus — so the good cutout stays on screen.
      final failed = item(status: 'failed');
      expect(failed.displayImageUrl, 'https://cdn/c.png');
      expect(failed.displayImageUrl, isNot('https://cdn/o.jpg'));
    });

    test('a thumbnail is preferred once the replacement lands', () {
      // Signed-URL refresh after an atomic asset replacement arrives as a new
      // thumbnail/cutout pair; the display picks the thumbnail first.
      final replaced = item(thumbnailUrl: 'https://cdn/t2.webp');
      expect(replaced.displayImageUrl, 'https://cdn/t2.webp');
    });

    test('a fresh cloud item with no cutout yet still shows its processing state', () {
      final fresh = item(cutoutUrl: null, status: 'queued', thumbnailUrl: null);
      expect(fresh.isProcessingCutout, isTrue);
      expect(fresh.displayImageUrl, 'https://cdn/o.jpg');
    });
  });

  group('requestBiRefNetImprovement', () {
    test('POSTs to the improvement route and returns the item', () async {
      final (dio, adapter) = fakeDio(
        (_) => jsonResponse({
          'id': 'w1',
          'cutout_status': 'queued',
          // The server hands back the CURRENT cutout, not a cleared field.
          'cutout_url': 'https://cdn/c.png',
        }, status: 202),
      );

      final updated = await WardrobeRepository(dio).requestBiRefNetImprovement('w1');

      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.path, '/v1/wardrobe/w1/improve-cutout');
      expect(updated.cutoutStatus, 'queued');
      expect(
        updated.cutoutUrl,
        'https://cdn/c.png',
        reason: 'the existing cutout must survive the request',
      );
    });

    test('sends no body — it costs nothing and configures nothing', () async {
      final (dio, adapter) = fakeDio(
        (_) => jsonResponse({'id': 'w1', 'cutout_status': 'queued'}, status: 202),
      );

      await WardrobeRepository(dio).requestBiRefNetImprovement('w1');

      expect(adapter.lastRequest!.data, isNull);
    });

    test('a duplicate tap returns the unchanged in-flight item', () async {
      // The server no-ops a second request for a row already queued/processing.
      final (dio, _) = fakeDio(
        (_) => jsonResponse({
          'id': 'w1',
          'cutout_status': 'processing',
          'cutout_url': 'https://cdn/c.png',
        }, status: 202),
      );

      final updated = await WardrobeRepository(dio).requestBiRefNetImprovement('w1');

      expect(updated.cutoutStatus, 'processing');
      expect(updated.cutoutUrl, 'https://cdn/c.png');
    });

    test('a gated-off endpoint surfaces as ApiException, not a raw DioException', () async {
      final (dio, _) = fakeDio(
        (_) => jsonResponse({
          'error': {'code': 'NOT_FOUND', 'message': 'Not found.'},
        }, status: 404),
      );

      await expectLater(
        WardrobeRepository(dio).requestBiRefNetImprovement('w1'),
        throwsA(isA<ApiException>()),
      );
    });

    test('a rate limit surfaces its message', () async {
      final (dio, _) = fakeDio(
        (_) => jsonResponse({
          'error': {'code': 'RATE_LIMITED', 'message': 'Too many requests.'},
        }, status: 429),
      );

      await expectLater(
        WardrobeRepository(dio).requestBiRefNetImprovement('w1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Too many'),
          ),
        ),
      );
    });

    test('it is NOT the editor route', () async {
      // Guards against the two free cutout tools ever being wired to each other.
      final paths = <String>[];
      final (dio, _) = fakeDio((options) {
        paths.add(options.path);
        return jsonResponse({'id': 'w1', 'cutout_status': 'queued'}, status: 202);
      });

      await WardrobeRepository(dio).requestBiRefNetImprovement('w1');

      expect(paths.single, isNot(contains('cutout-mask')));
      expect(paths.single, contains('improve-cutout'));
    });

    test('a network failure is a typed ApiException', () async {
      final (dio, _) = fakeDio(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        ),
      );

      await expectLater(
        WardrobeRepository(dio).requestBiRefNetImprovement('w1'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('the button reads ITS OWN gate, not the local-BG master (regression)', () {
    // Shipped defect: this affordance was gated on `kLocalBgRemovalEnabled`
    // ("segment on device"), while the server gates the endpoint on its own
    // LOCAL_CUTOUT_IMPROVE_ENABLED. Turning on Android local background removal
    // therefore made the button appear against an endpoint that was still off,
    // and every real tap answered 404 -> "not found" on a production build.
    test('the provider is wired to the improve gate', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(improveCutoutEnabledProvider),
        kLocalCutoutImproveEnabled,
      );
    });

    test('it stays OFF by default, because the server gate is off by default', () {
      // Both sides default false. A build that has not deliberately enabled BOTH
      // must not render the button at all.
      expect(kLocalCutoutImproveEnabled, isFalse);
      expect(canImproveCutout(item(), enabled: kLocalCutoutImproveEnabled), isFalse);
    });

    Future<void> pumpDetail(WidgetTester tester, {required bool enabled}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [improveCutoutEnabledProvider.overrideWithValue(enabled)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: WtmGarmentDetailScreen(item: item()),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('gate off -> no Improve edges button to tap', (tester) async {
      await pumpDetail(tester, enabled: false);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.wardrobeImproveEdges), findsNothing);
    });

    testWidgets('gate on -> the button renders', (tester) async {
      // Proves the screen reads THIS provider: overriding it changes what shows.
      await pumpDetail(tester, enabled: true);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.wardrobeImproveEdges), findsOneWidget);
    });
  });

  group('the build config carries the gate to every platform', () {
    // The authority moved. It used to be a Codemagic env group plus a
    // hand-maintained, git-ignored `env/prod.json` — two places, neither of them
    // reviewed, and a gate absent from either compiled OFF without failing
    // anything. It is now ONE committed file that both the local build and every
    // CI workflow render from, so this test reads that file.
    test('the committed production policy states this gate explicitly', () {
      final policy =
          jsonDecode(File('env/feature_policy.prod.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(
        policy['gates'] as Map<String, dynamic>,
        containsPair('LOCAL_CUTOUT_IMPROVE_ENABLED', 'false'),
        reason:
            'shipping this on while the server gate is off is the exact '
            '"not found" defect; it must be stated, not left to a default',
      );
    });

    test('the prod dart-define example documents it as off', () {
      expect(
        jsonDecode(File('env/prod.json.example').readAsStringSync()),
        containsPair('LOCAL_CUTOUT_IMPROVE_ENABLED', 'false'),
      );
    });

    test('CI renders prod.json from that policy rather than from env vars', () {
      // A gate left out of a hand-written generator silently compiled OFF in CI
      // even when it was set locally. That is what hid "Fix cutout" on iOS: the
      // Android APK is built on Windows where the flag was appended by hand,
      // while every iOS build comes through Codemagic.
      final codemagic = File('../codemagic.yaml').readAsStringSync();
      expect(codemagic, contains('scripts/render_app_env.py'));
      expect(
        codemagic,
        contains('scripts/verify_local_cutout_release.py'),
        reason: 'the rendered config must be asserted before anything is built',
      );
    });

    test('the release verifier is what enforces it, on every platform', () {
      expect(
        File('../scripts/verify_local_cutout_release.py').readAsStringSync(),
        contains('check_policy_matches_config'),
        reason:
            'a generated config that disagrees with the committed policy — from '
            'a CI env group, a stale local file or a restored .bak — must not ship',
      );
    });
  });
}
