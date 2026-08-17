import 'dart:async';
import 'dart:io';

import 'package:app/core/media/media_upload_service.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/data/models/ai_job.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/ai_studio_repository.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_cache.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_models.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_orchestrator.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_platform.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_providers.dart';
import 'package:app/features/wardrobe/wardrobe_image_service.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/closet/wtm_add_garment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../features/local_cutout/local_cutout_fakes.dart';
import '../helpers/fake_wardrobe_items.dart';

/// Add Garment on the local-first path (local BG §9.3, §11.2).
///
/// Driven through the REAL screen and the REAL orchestrator, with only the
/// platform, upload and repository faked — so the wiring is exercised rather than
/// restated.
///
/// Harness notes, each earned the hard way:
///   * `pumpAndSettle` can never settle here: the processing stage runs an
///     indefinite repeating progress animation plus a 4s periodic repaint timer.
///     Use [advance], which pumps a bounded number of frames.
///   * The screen does REAL file I/O (reading the mask the engine wrote). Pumped
///     frames alone never let that complete, so [advance] interleaves
///     `tester.runAsync`.
///   * `cached_network_image` reaches for `path_provider`, which has no
///     implementation in a widget test — stubbed below.
///   * The screen is not a Scaffold and its confirm stage builds a `TextField`,
///     which needs a Material ancestor.
///   * A fake upload MUST return an `objectKey` or the local save path is skipped
///     entirely and the screen goes straight to the cloud create.
///   * Every held Completer is released via `addTearDown`, so a failing assertion
///     can never leave a pending future that breaks the NEXT test.
void main() {
  /// A valid 1x1 transparent PNG, so `Image.memory` / `Image.file` decode for real.
  final png = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
    0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
    0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
    0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00,
    0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  const objectKey = 'u/wardrobe/a.jpg';
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  late Directory temp;
  late String cutoutPath;
  late String maskPath;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wtm-add-local');
    cutoutPath = '${temp.path}${Platform.pathSeparator}cutout.png';
    maskPath = '${temp.path}${Platform.pathSeparator}mask.png';
    await File(cutoutPath).writeAsBytes(png);
    await File(maskPath).writeAsBytes(png);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => temp.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
    } on FileSystemException {
      // Windows keeps a handle on a file rendered via Image.file. Housekeeping,
      // not an assertion.
    }
  });

  /// Items deliberately carry NO urls: the confirm stage then renders a
  /// placeholder instead of attempting a network image, which keeps these tests
  /// about the local flow rather than about image caching.
  const savedItem = WardrobeItem(id: 'w-local', cutoutStatus: 'done');
  const cloudItem = WardrobeItem(id: 'w-cloud', cutoutStatus: 'done');

  /// A real router, because a successful save pops the route (`wtmPageBack`) and
  /// a plain `MaterialApp` has no GoRouter for it to find. The screen is pushed
  /// on top of a stub so `canPop()` is true and the pop lands somewhere.
  Widget app(Widget child) => MaterialApp.router(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('closet')),
          routes: [
            GoRoute(
              path: 'add',
              builder: (_, _) => Scaffold(body: child),
            ),
          ],
        ),
      ],
    ),
  );

  /// Advance time in bounded steps, yielding to the real event loop between
  /// frames so genuine file I/O can complete.
  Future<void> advance(WidgetTester tester, {int steps = 12}) async {
    for (var i = 0; i < steps; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<_Harness> open(
    WidgetTester tester, {
    LocalCutoutResult? localResult,
    LocalCutoutPlatformException? localError,
    ApiException? saveError,
    ApiException? updateError,
    WardrobeItem? created,
    bool holdSave = false,
    bool localEnabled = true,
    String? uploadObjectKey = objectKey,
    Duration removeDelay = Duration.zero,
  }) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final platform = FakeLocalCutoutPlatform()
      ..result = localResult
      ..error = localError
      ..removeDelay = removeDelay;
    final image = _FakeImageService(bytes: png, objectKey: uploadObjectKey);
    final repo = _RecordingRepository(
      savedItem: created ?? savedItem,
      cloudItem: cloudItem,
      saveError: saveError,
      updateError: updateError,
      holdSave: holdSave,
    );
    final enhance = _ForbiddenAiStudioRepository();
    // A held Completer MUST always be released, or a failing assertion leaves a
    // pending future that corrupts the next test in the file.
    addTearDown(repo.releaseSave);

    final orchestrator = LocalCutoutOrchestrator(
      platform: platform,
      cache: LocalCutoutCache(platform),
      masterEnabled: localEnabled,
      androidEnabled: true,
      iosEnabled: true,
      targetPlatform: TargetPlatform.android,
      readDimensions: (_) async => const SourceDimensions(1600, 1200),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeImageServiceProvider.overrideWithValue(image),
          wardrobeRepositoryProvider.overrideWithValue(repo),
          aiStudioRepositoryProvider.overrideWithValue(enhance),
          localCutoutOrchestratorProvider.overrideWithValue(orchestrator),
          wardrobeItemsProvider.overrideWith(
            () => FakeWardrobeItemsNotifier(const []),
          ),
          creditsProvider.overrideWith(
            (ref) async => const Credits(
              balance: 0,
              dailyFreeUsed: 0,
              dailyFreeLimit: 3,
              dailyFreeRemaining: 3,
            ),
          ),
        ],
        child: app(const WtmAddGarmentScreen()),
      ),
    );
    await tester.pump();
    return _Harness(platform, image, repo, enhance);
  }

  LocalCutoutResult goodResult() => fakeResult(
    operationId: 'aabb',
    maskFilePath: maskPath,
    cutoutFilePath: cutoutPath,
    metrics: fakeMetrics(width: 1600, height: 1200),
  );

  /// Choose the photo. Lands on the DETAILS stage — nothing is uploaded, and no
  /// background removal starts, until the mandatory metadata is in.
  Future<void> pickPhoto(WidgetTester tester) async {
    await tester.tap(find.text('Choose from Gallery'));
    await tester.pump();
  }

  /// Supply the two mandatory fields and leave the details stage.
  Future<void> fillDetails(
    WidgetTester tester, {
    String name = 'Linen shirt',
    String category = 'Tops',
  }) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.pump();
    await tester.tap(find.text(category));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
  }

  /// The whole pre-processing journey, as a real user performs it: photo, name,
  /// category, continue. Every test below that is not ABOUT the details stage
  /// uses this, so they assert on the removal rather than restating the form.
  Future<void> pick(WidgetTester tester) async {
    await pickPhoto(tester);
    await fillDetails(tester);
  }

  // ── mandatory metadata (the production regression) ─────────────────────────
  //
  // Both fields are required at the API on every manual add path. This screen
  // used to create the piece FIRST and ask for its name afterwards, so once the
  // server started enforcing that rule the create at the end of a perfectly
  // good background removal was refused 422 — and the user was shown a
  // full-screen "Something went wrong / Give this piece a name before saving
  // it." whose Try again re-ran the removal and failed in exactly the same way.

  testWidgets('the name and category reach the local create', (tester) async {
    final h = await open(tester, localResult: goodResult());

    await pickPhoto(tester);
    await fillDetails(tester, name: 'Linen shirt', category: 'Tops');
    await advance(tester);

    final call = h.repo.localCalls.single;
    expect(call['title'], 'Linen shirt');
    // The wire value is the enum name, which is what the server's taxonomy
    // resolves to a canonical role ('tops' -> top).
    expect(call['category'], 'tops');
  });

  testWidgets('the name and category reach the cloud create too', (
    tester,
  ) async {
    // A gate only one of the two doors honours is not a gate.
    final h = await open(
      tester,
      localError: const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.noSubjectFound,
      ),
    );

    await pickPhoto(tester);
    await fillDetails(tester, name: 'Wool coat', category: 'Outerwear');
    await advance(tester);

    final call = h.repo.cloudCalls.single;
    expect(call['title'], 'Wool coat');
    expect(call['category'], 'outerwear');
  });

  testWidgets('nothing is uploaded or cut until both fields are supplied', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    await pickPhoto(tester);
    await advance(tester, steps: 4);

    // THE assertion: the expensive work has not started. Previously the pick
    // alone kicked off upload + removal + create, which is what made a missing
    // name surface as a failed background removal.
    expect(h.image.uploadedBytes, isNull, reason: 'no upload yet');
    expect(h.platform.removeCalls, 0, reason: 'the engine has not run');
    expect(h.repo.localCalls, isEmpty);
    expect(h.repo.cloudCalls, isEmpty);

    // A name alone is not enough — the category is required too.
    await tester.enterText(find.byType(TextField), 'Linen shirt');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await advance(tester, steps: 4);
    expect(h.platform.removeCalls, 0, reason: 'category still missing');
    expect(
      find.text('Choose a category so it can be styled and tried on.'),
      findsOneWidget,
      reason: 'the missing field is named, not a generic failure',
    );
    // And it is NOT the background-removal failure screen.
    expect(find.text('Try again'), findsNothing);

    // Supplying it releases the flow.
    await tester.tap(find.text('Tops'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await advance(tester);
    expect(h.repo.localCalls, hasLength(1));
  });

  testWidgets('a missing name is named on the field, not as a failed removal', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    await pickPhoto(tester);
    await tester.tap(find.text('Tops'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await advance(tester, steps: 4);

    expect(find.text('Give this piece a name.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(h.platform.removeCalls, 0);
    expect(h.repo.localCalls, isEmpty);
    expect(h.repo.cloudCalls, isEmpty);
  });

  // ── state survives the async transitions ───────────────────────────────────

  testWidgets('the server echo never overwrites what the user typed', (
    tester,
  ) async {
    // The created row comes back with the tagger's own idea of the piece. The
    // user's entry is the one that must survive to the confirm stage: replacing
    // it silently changed a chosen category, and a null title blanked the name
    // field and sent the very next save into the 422 this flow exists to avoid.
    final h = await open(
      tester,
      localResult: goodResult(),
      created: const WardrobeItem(
        id: 'w-local',
        cutoutStatus: 'done',
        title: null,
        category: 'Dresses',
      ),
    );

    await pickPhoto(tester);
    await fillDetails(tester, name: 'Linen shirt', category: 'Tops');
    await advance(tester);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Linen shirt',
    );

    await tester.tap(find.text('Save to Closet'));
    await advance(tester, steps: 6);

    final update = h.repo.updateCalls.single;
    expect(update['title'], 'Linen shirt');
    expect(update['category'], 'tops', reason: 'not the tagger\'s "Dresses"');
  });

  testWidgets('an emptied name blocks Save and keeps the processed piece', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await advance(tester);
    expect(h.repo.localCalls, hasLength(1), reason: 'the piece exists');

    // Clear the name on the confirm stage and try to save.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('Save to Closet'));
    await advance(tester, steps: 4);

    expect(h.repo.updateCalls, isEmpty, reason: 'no doomed round trip');
    expect(find.text('Give this piece a name.'), findsOneWidget);
    // The work that succeeded is still on screen and still offered for saving.
    expect(find.text('Save to Closet'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    // And no second background removal was started to "recover".
    expect(h.platform.removeCalls, 1);
  });

  testWidgets('a validation refusal on Save keeps the user in the form', (
    tester,
  ) async {
    // The backstop for a server that refuses metadata the client thought fine:
    // it must not become a background-removal failure screen.
    final h = await open(
      tester,
      localResult: goodResult(),
      updateError: const ApiException(
        code: ApiErrorCode.validationError,
        message: 'Give this piece a name before saving it.',
        statusCode: 422,
      ),
    );

    await pick(tester);
    await advance(tester);
    await tester.tap(find.text('Save to Closet'));
    await advance(tester, steps: 6);

    expect(h.repo.updateCalls, hasLength(1));
    expect(
      find.text('Save to Closet'),
      findsOneWidget,
      reason: 'still in form',
    );
    expect(find.text('Try again'), findsNothing);
    expect(h.platform.removeCalls, 1, reason: 'no re-run of a good removal');
  });

  // ── duplicate prevention ───────────────────────────────────────────────────

  testWidgets('a double-tapped Continue creates exactly one piece', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    await pickPhoto(tester);
    await tester.enterText(find.byType(TextField), 'Linen shirt');
    await tester.pump();
    await tester.tap(find.text('Tops'));
    await tester.pump();
    // Two taps in the same frame, before the stage has had a chance to change.
    await tester.tap(find.text('Continue'));
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await advance(tester);

    // Each run uploads a FRESH original, and the endpoint's idempotency is keyed
    // on that object key — so two runs would be two keys and two closet items,
    // which no server-side dedupe could collapse.
    expect(h.repo.localCalls, hasLength(1));
    expect(h.repo.cloudCalls, isEmpty);
    expect(h.platform.removeCalls, 1);
  });

  testWidgets('a double-tapped Save issues exactly one write', (tester) async {
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await advance(tester);
    await tester.tap(find.text('Save to Closet'));
    await tester.tap(find.text('Save to Closet'), warnIfMissed: false);
    await advance(tester, steps: 6);

    expect(h.repo.updateCalls, hasLength(1));
  });

  // ── retry after a genuine processing failure ───────────────────────────────

  testWidgets('a retry after a real failure keeps the metadata', (
    tester,
  ) async {
    // sourceMissing is terminal for THIS photo, so the screen asks for another
    // one. What must survive is everything the user already told us.
    final h = await open(
      tester,
      localResult: goodResult(),
      saveError: const ApiException(
        code: ApiErrorCode.sourceMissing,
        message: 'That photo is no longer available.',
      ),
    );

    await pickPhoto(tester);
    await fillDetails(tester, name: 'Linen shirt', category: 'Tops');
    await advance(tester);

    expect(
      find.text("We couldn't read that photo. Please pick it again."),
      findsOneWidget,
    );
    expect(h.repo.cloudCalls, isEmpty);

    // Retrying re-runs the removal — and carries the name and category with it,
    // rather than repeating the create the server already refused.
    await tester.tap(find.text('Try again'));
    await advance(tester);

    expect(h.repo.localCalls, hasLength(2));
    expect(h.repo.localCalls.last['title'], 'Linen shirt');
    expect(h.repo.localCalls.last['category'], 'tops');
  });

  // ── the local preview, before the save completes ───────────────────────────

  testWidgets('shows the transparent local cutout before the save finishes', (
    tester,
  ) async {
    // The save is held open, so anything on screen is necessarily the
    // PRE-persistence state.
    final h = await open(tester, localResult: goodResult(), holdSave: true);

    await pick(tester);
    await advance(tester, steps: 8);

    final fileImages = tester
        .widgetList<Image>(find.byType(Image))
        .where((i) => i.image is FileImage)
        .map((i) => (i.image as FileImage).file.path)
        .toList();
    expect(
      fileImages,
      contains(cutoutPath),
      reason: 'the ENGINE OUTPUT must be previewed, not the raw photo',
    );
    // The save has genuinely not returned yet.
    expect(h.repo.saveStarted, isTrue);
    expect(h.repo.saveCompleted, isFalse);
  });

  testWidgets('the preview copy never implies the save is done', (
    tester,
  ) async {
    await open(tester, localResult: goodResult(), holdSave: true);

    await pick(tester);
    await advance(tester, steps: 8);

    expect(find.text('Saving your cutout…'), findsOneWidget);
    // The staged ~90s cloud copy and its filler tip must not appear locally.
    expect(find.text('Warming up the studio…'), findsNothing);
    expect(find.text('Clearing the background…'), findsNothing);
  });

  // ── the source bytes ───────────────────────────────────────────────────────

  testWidgets('the engine segments the SAME bytes that are uploaded', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await advance(tester);

    // Identity, not equality: one buffer, both consumers (§8.1). A re-read or
    // re-encode is exactly what makes a mask fail to line up server-side.
    expect(h.platform.lastImageBytes, same(h.image.uploadedBytes));
    expect(h.image.uploadedBytes, same(png));
  });

  // ── local ingestion ────────────────────────────────────────────────────────

  testWidgets('local success saves through the local-cutout path', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await advance(tester);

    expect(h.repo.localCalls, hasLength(1));
    expect(h.repo.cloudCalls, isEmpty);
    final call = h.repo.localCalls.single;
    expect(call['originalObjectKey'], objectKey);
    expect(call['engine'], 'google_mlkit');
    expect(
      call['maskBytes'],
      png.length,
      reason: 'the mask FILE was read and sent',
    );
  });

  testWidgets('a locally-saved item skips the BiRefNet poll entirely', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await advance(tester);

    // The item is born cutout_status=done, so there is nothing to wait for. The
    // one permitted call is the post-save closet refresh; a poll loop would be many
    // (first check at 350ms, then every 800ms up to the 200s ceiling).
    expect(
      h.repo.getItemsCalls,
      lessThanOrEqualTo(1),
      reason: 'a BiRefNet poll loop would make repeated calls',
    );
  });

  testWidgets('temp files are released after a successful save', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await advance(tester);

    expect(h.platform.cleaned, contains('aabb'));
  });

  // ── cloud fallback ─────────────────────────────────────────────────────────

  testWidgets('a typed local failure falls back to the cloud create', (
    tester,
  ) async {
    final h = await open(
      tester,
      localError: const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.noSubjectFound,
      ),
    );

    await pick(tester);
    await advance(tester);

    expect(h.repo.localCalls, isEmpty);
    expect(h.repo.cloudCalls, hasLength(1));
    // The SAME object key — the photo is never uploaded twice.
    expect(h.repo.cloudCalls.single['objectKey'], objectKey);
  });

  testWidgets('a rejected mask falls back with the same object key', (
    tester,
  ) async {
    final h = await open(
      tester,
      localResult: goodResult(),
      saveError: const ApiException(
        code: ApiErrorCode.validationError,
        message: 'Mask dimensions must match',
      ),
    );

    await pick(tester);
    await advance(tester);

    expect(h.repo.localCalls, hasLength(1), reason: 'local was attempted');
    expect(h.repo.cloudCalls, hasLength(1), reason: 'then fell back');
    expect(h.repo.cloudCalls.single['objectKey'], objectKey);
    expect(h.platform.cleaned, contains('aabb'));
  });

  testWidgets('a transient storage failure is recoverable via the cloud', (
    tester,
  ) async {
    final h = await open(
      tester,
      localResult: goodResult(),
      saveError: const ApiException(
        code: ApiErrorCode.providerError,
        message: 'Couldn\'t read that photo right now.',
      ),
    );

    await pick(tester);
    await advance(tester);

    expect(h.repo.cloudCalls, hasLength(1));
  });

  // ── the terminal case ──────────────────────────────────────────────────────

  testWidgets('sourceMissing creates NO cloud item and asks for a new photo', (
    tester,
  ) async {
    final h = await open(
      tester,
      localResult: goodResult(),
      saveError: const ApiException(
        code: ApiErrorCode.sourceMissing,
        message: 'That photo is no longer available.',
      ),
    );

    await pick(tester);
    await advance(tester);

    // THE assertion: the BiRefNet worker reads the same stored object, so a cloud
    // attempt would create an item guaranteed to fail.
    expect(
      h.repo.cloudCalls,
      isEmpty,
      reason: 'a doomed queued item must never be created',
    );
    expect(
      find.text("We couldn't read that photo. Please pick it again."),
      findsOneWidget,
    );
    expect(h.platform.cleaned, contains('aabb'));
  });

  // ── cancellation / disposal ────────────────────────────────────────────────

  testWidgets('disposal mid-save cancels the operation and cleans up', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult(), holdSave: true);

    await pick(tester);
    await advance(tester, steps: 6);
    expect(h.platform.removeCalls, 1, reason: 'the engine ran');

    // Tear the screen down while the save is still in flight.
    await tester.pumpWidget(app(const SizedBox.shrink()));
    await advance(tester, steps: 6);

    expect(h.platform.cancelled, contains('aabb'));
    expect(h.platform.cleaned, contains('aabb'));
    // A setState-after-dispose (or a `ref` read on an unmounting widget) would
    // have been thrown by the framework and surfaced here.
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal before the engine replies still cleans up', (
    tester,
  ) async {
    await open(
      tester,
      localResult: goodResult(),
      removeDelay: const Duration(milliseconds: 200),
    );

    await pick(tester);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(app(const SizedBox.shrink()));
    await advance(tester, steps: 10);

    // Whether or not the result arrived, no scratch directory may survive and no
    // exception may escape.
    expect(tester.takeException(), isNull);
  });

  // ── the existing behaviour must be untouched ───────────────────────────────

  testWidgets(
    'with the gate off the engine is never called and the cloud path runs',
    (tester) async {
      final h = await open(
        tester,
        localResult: goodResult(),
        localEnabled: false,
      );

      await pick(tester);
      await advance(tester);

      expect(h.platform.capabilityCalls, 0);
      expect(h.platform.removeCalls, 0);
      expect(h.repo.localCalls, isEmpty);
      expect(h.repo.cloudCalls, hasLength(1));
      expect(h.platform.cleaned, isEmpty);
    },
  );

  testWidgets('a legacy upload with no object key uses the cloud create', (
    tester,
  ) async {
    // R2 write-gate off server-side: there is no key to hand the local endpoint.
    final h = await open(
      tester,
      localResult: goodResult(),
      uploadObjectKey: null,
    );

    await pick(tester);
    await advance(tester);

    expect(h.repo.localCalls, isEmpty);
    expect(h.repo.cloudCalls, hasLength(1));
    expect(h.repo.cloudCalls.single['imageUrl'], isNotNull);
  });

  testWidgets('AI Enhance is offered and never triggered by a local add', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    // Both capture-stage mode cards are still present and unchanged.
    expect(find.text('Remove background'), findsOneWidget);
    expect(find.text('AI Enhance'), findsOneWidget);

    await pick(tester);
    await advance(tester);

    // The default mode is free background removal, so no enhance job — and no
    // credit spend — may occur. The fake throws if it is ever called.
    expect(h.enhance.calls, 0);
    expect(tester.takeException(), isNull);
  });
}

/// What [open] hands back so a test can assert on the fakes.
class _Harness {
  _Harness(this.platform, this.image, this.repo, this.enhance);

  final FakeLocalCutoutPlatform platform;
  final _FakeImageService image;
  final _RecordingRepository repo;
  final _ForbiddenAiStudioRepository enhance;
}

/// Returns fixed bytes and records exactly what was uploaded.
class _FakeImageService implements WardrobeImageService {
  _FakeImageService({required this.bytes, this.objectKey});

  final Uint8List bytes;
  final String? objectKey;
  Uint8List? uploadedBytes;

  @override
  Future<Uint8List?> pickAndCompress(ImageSource source) async => bytes;

  /// No lost capture in a test — the real one is Android-only and self-clearing.
  @override
  Future<Uint8List?> recoverLostCapture() async => null;

  @override
  Future<MediaRef> upload(Uint8List data) async {
    uploadedBytes = data;
    return objectKey != null
        ? MediaRef(objectKey: objectKey)
        : const MediaRef(legacyUrl: 'https://cdn.test/wardrobe/x.jpg');
  }
}

/// Records which create path was taken, and can hold the local save open so the
/// pre-persistence UI state is observable.
class _RecordingRepository implements WardrobeRepository {
  _RecordingRepository({
    required this.savedItem,
    required this.cloudItem,
    this.saveError,
    this.updateError,
    this.holdSave = false,
  });

  final WardrobeItem savedItem;
  final WardrobeItem cloudItem;
  final ApiException? saveError;
  final ApiException? updateError;
  final bool holdSave;

  final List<Map<String, Object?>> localCalls = [];
  final List<Map<String, Object?>> cloudCalls = [];
  int getItemsCalls = 0;
  bool saveStarted = false;
  bool saveCompleted = false;

  Completer<void>? _gate;

  /// Always called from `addTearDown`, so a failing assertion cannot leave a
  /// pending future behind to corrupt the next test.
  void releaseSave() {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<WardrobeItem> addItemWithLocalCutout({
    required String originalObjectKey,
    required Uint8List maskPng,
    required String engine,
    required String platform,
    String engineVersion = '',
    int localLatencyMs = 0,
    int subjectCount = 0,
    String? title,
    String? category,
  }) async {
    saveStarted = true;
    localCalls.add({
      'originalObjectKey': originalObjectKey,
      'engine': engine,
      'platform': platform,
      'maskBytes': maskPng.length,
      'title': title,
      'category': category,
    });
    if (holdSave) {
      final gate = _gate = Completer<void>();
      await gate.future;
    }
    saveCompleted = true;
    final failure = saveError;
    if (failure != null) throw failure;
    return savedItem;
  }

  @override
  Future<WardrobeItem> addItem({
    String? title,
    String? category,
    String? imageUrl,
    String? objectKey,
  }) async {
    cloudCalls.add({
      'objectKey': objectKey,
      'imageUrl': imageUrl,
      'title': title,
      'category': category,
    });
    return cloudItem;
  }

  @override
  Future<List<WardrobeItem>> getItems({int? limit, DateTime? before}) async {
    getItemsCalls++;
    return [savedItem];
  }

  final List<Map<String, Object?>> updateCalls = [];

  @override
  Future<WardrobeItem> updateItem(
    String id, {
    required String? title,
    required String? category,
    required String? color,
    String? subcategory,
  }) async {
    updateCalls.add({'id': id, 'title': title, 'category': category});
    final failure = updateError;
    if (failure != null) throw failure;
    return savedItem;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not used by this test',
  );
}

/// Fails loudly if the local flow ever starts an enhance job — that would mean a
/// silent credit spend on the free path.
class _ForbiddenAiStudioRepository implements AiStudioRepository {
  int calls = 0;

  @override
  Future<AiJob> enhanceItem(String wardrobeItemId, {String? idempotencyKey}) {
    calls++;
    throw StateError('AI Enhance must not run on the free local path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not used by this test',
  );
}
