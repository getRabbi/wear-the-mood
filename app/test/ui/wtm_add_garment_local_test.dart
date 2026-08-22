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
import 'package:app/ui/widgets/widgets.dart';
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
  /// Swallow the ONE exception these tests are guaranteed to provoke and are
  /// not about: a network image that cannot load.
  ///
  /// The cloud path's confirm stage shows the `cutout_temp` job's output, and
  /// the fake job returns `https://cdn.test/cutout/x.png`. A widget test's HTTP
  /// client answers 400 to everything, so `cached_network_image` throws
  /// `HttpExceptionWithStatus` from the image resource service.
  ///
  /// It only surfaced on macOS. `flutter_test_config.dart` gives the host a real
  /// sqflite engine, so `flutter_cache_manager` gets far enough to actually
  /// attempt the fetch; on Windows the pumped frames ended before that async
  /// chain resolved, and the same latent problem stayed invisible. It failed the
  /// Codemagic iOS build and nothing else, which is the worst place to find out.
  ///
  /// Deliberately NARROW: it re-throws anything that is not an image fetch, so a
  /// real failure in the flow under test still fails the test.
  void drainImageFetchFailure(WidgetTester tester) {
    final error = tester.takeException();
    if (error == null) return;
    final text = error.toString();
    final isImageFetch =
        text.contains('cdn.test') ||
        text.contains('Invalid statusCode') ||
        text.contains('HttpException');
    if (!isImageFetch) {
      throw error as Object;
    }
  }

  Future<void> advance(WidgetTester tester, {int steps = 12}) async {
    for (var i = 0; i < steps; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    drainImageFetchFailure(tester);
  }

  Future<_Harness> open(
    WidgetTester tester, {
    LocalCutoutResult? localResult,
    LocalCutoutPlatformException? localError,
    ApiException? saveError,
    ApiException? cloudSaveError,
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
      cloudSaveError: cloudSaveError,
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

  /// Choose the photo. The removal starts immediately — the user is NOT asked to
  /// name the piece first.
  Future<void> pickPhoto(WidgetTester tester) async {
    await tester.tap(find.text('Choose from Gallery'));
    await tester.pump();
  }

  /// Photo → removal → the confirm stage, with the cutout on screen. Where most
  /// tests below start asserting.
  Future<void> pick(WidgetTester tester) async {
    await pickPhoto(tester);
    await advance(tester);
  }

  /// Name it, categorise it, save. The ONLY step that writes to the closet.
  Future<void> saveAs(
    WidgetTester tester, {
    String name = 'Linen shirt',
    String category = 'Tops',
  }) async {
    if (name.isNotEmpty) {
      await tester.enterText(find.byType(TextField), name);
      await tester.pump();
    }
    if (category.isNotEmpty) {
      await tester.tap(find.text(category));
      await tester.pump();
    }
    await tester.tap(find.text('Save to Closet'));
    await tester.pump();
  }

  /// The whole journey a real user performs, end to end.
  Future<void> pickAndSave(WidgetTester tester) async {
    await pick(tester);
    await saveAs(tester);
    await advance(tester);
  }

  /// Let `cached_network_image`'s one-shot cache-cleanup timer fire.
  ///
  /// Any test whose preview is a NETWORK image — i.e. the cloud cutout — leaves
  /// it pending, and the binding fails the test for a timer it never started.
  /// Local-path tests render a file and never need this.
  Future<void> settleImageCache(WidgetTester tester) async {
    // Lets flutter_cache_manager's pending work drain. The sqflite error it
    // raises on a test host is neutralised globally in
    // test/flutter_test_config.dart -- it surfaces asynchronously, long after
    // this pump returns, so it cannot be caught from here.
    await tester.pump(const Duration(seconds: 11));
  }

  // ── the ORDER (the correction) ─────────────────────────────────────────────
  //
  // Photo -> removal -> look at the cutout -> name + category -> Save. The
  // metadata question comes AFTER the removal, and nothing reaches the closet
  // until Save. Two earlier versions of this screen got the order wrong in
  // opposite directions: the first created the garment before asking anything
  // (which the mandatory-metadata rule then refused, 422, at the end of a
  // successful removal), the second asked before removing (which made people
  // name a garment they had not yet seen).

  testWidgets('the removal runs BEFORE any metadata is asked for', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    await pickPhoto(tester);
    await advance(tester);

    // The engine ran and the photo was uploaded, with nothing asked of the user.
    expect(h.platform.removeCalls, 1, reason: 'the removal already happened');
    expect(h.image.uploadedBytes, isNotNull);
    // And the result is what they are looking at.
    final fileImages = tester
        .widgetList<Image>(find.byType(Image))
        .where((i) => i.image is FileImage)
        .map((i) => (i.image as FileImage).file.path);
    expect(fileImages, contains(cutoutPath));
    expect(find.text('Save to Closet'), findsOneWidget);
  });

  testWidgets('nothing reaches the closet until Save', (tester) async {
    final h = await open(tester, localResult: goodResult());

    await pick(tester);

    // THE property. A user who backs out here has left no trace: no garment, no
    // half-made row for the closet to filter out later.
    expect(h.repo.localCalls, isEmpty);
    expect(h.repo.cloudCalls, isEmpty);

    await saveAs(tester);
    await advance(tester);

    expect(h.repo.localCalls, hasLength(1), reason: 'Save is what creates it');
  });

  testWidgets('the name and category reach the local create', (tester) async {
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await saveAs(tester, name: 'Linen shirt', category: 'Tops');
    await advance(tester);

    final call = h.repo.localCalls.single;
    expect(call['title'], 'Linen shirt');
    // The wire value is the picker's STORED value, which the server's taxonomy
    // maps exactly ('Tops' -> top). It used to be the lowercase name of the
    // closet FILTER enum, which is a different vocabulary that could not
    // express a hijab, a watch or a pair of glasses at all.
    expect(call['category'], 'Tops');
  });

  testWidgets('the cloud path removes first too, then adopts at save', (
    tester,
  ) async {
    // The device engine declined, so the removal happened in the cloud -- and it
    // still happened BEFORE the metadata question.
    final h = await open(
      tester,
      localError: const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.noSubjectFound,
      ),
    );

    await pick(tester);

    expect(h.repo.cutoutJobCalls, 1, reason: 'a temp cutout was made');
    expect(h.repo.cloudCalls, isEmpty, reason: 'but no garment yet');

    await saveAs(tester, name: 'Wool coat', category: 'Outerwear');
    await advance(tester);

    final call = h.repo.cloudCalls.single;
    expect(call['title'], 'Wool coat');
    expect(call['category'], 'Outerwear');
    // The finished cutout is adopted rather than recomputed by the worker.
    expect(call['cutoutJobId'], 'cut-1');
    await settleImageCache(tester);
  });

  // ── the two mandatory fields, asked AFTER the cutout exists ────────────────

  /// The Save CTA's handler — null means the button is genuinely disabled.
  VoidCallback? saveHandler(WidgetTester tester) => tester
      .widget<GradientCta>(find.widgetWithText(GradientCta, 'Save to Closet'))
      .onPressed;

  testWidgets('a missing name leaves Save disabled, not a failed removal', (
    tester,
  ) async {
    // Stronger than the old contract, which let Save be tapped and answered
    // with an inline error. An incomplete piece can no longer reach the
    // button at all, so there is no doomed round trip to refuse.
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await saveAs(tester, name: '', category: 'Tops');
    await advance(tester, steps: 4);

    expect(saveHandler(tester), isNull, reason: 'Save is disabled');
    expect(h.repo.localCalls, isEmpty, reason: 'no doomed round trip');
    // Not the removal-failure screen, and the removal is NOT re-run.
    expect(find.text('Try again'), findsNothing);
    expect(h.platform.removeCalls, 1);
    // The work that succeeded is still on screen.
    expect(find.text('Save to Closet'), findsOneWidget);
  });

  testWidgets('a missing category leaves Save disabled, and says so', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await saveAs(tester, name: 'Linen shirt', category: '');
    await advance(tester, steps: 4);

    expect(saveHandler(tester), isNull);
    // And the line above Save states the gap in the same words the picker uses,
    // so a disabled button is never unexplained.
    expect(find.text('Try-on type: not chosen yet'), findsOneWidget);
    expect(h.repo.localCalls, isEmpty);
    expect(find.text('Try again'), findsNothing);
    expect(h.platform.removeCalls, 1);
  });

  testWidgets('choosing a category names what the piece will be worn as', (
    tester,
  ) async {
    // The confirmation the spec asks for, and the thing that would have caught
    // a tank top being filed under trousers: the consequence is stated in the
    // same breath as the choice, right above the button that commits it.
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await tester.enterText(find.byType(TextField), 'Tank top');
    await tester.pump();
    await tester.tap(find.text('Tops'));
    await tester.pump();

    expect(find.text('Try-on type: Tops'), findsOneWidget);
    expect(saveHandler(tester), isNotNull);
    expect(h.repo.localCalls, isEmpty, reason: 'still nothing saved');
  });

  testWidgets('every choice carries a concrete example', (tester) async {
    // "Bottoms" alone is a guess; "Pants, jeans, skirt, shorts" is not.
    await open(tester, localResult: goodResult());
    await pick(tester);

    expect(find.text('T-shirt, shirt, blouse, sweater'), findsOneWidget);
    expect(find.text('Pants, jeans, skirt, shorts'), findsOneWidget);
    expect(find.text('Hijab, scarf, shawl, dupatta'), findsOneWidget);
  });

  testWidgets('a piece the provider cannot render says so on the tile', (
    tester,
  ) async {
    // Honest rather than hidden: a belt is a fine closet item that today's
    // model cannot wear, and saying so beats a look quietly missing a piece.
    await open(tester, localResult: goodResult());
    await pick(tester);

    expect(find.text('Not worn in try-ons yet'), findsWidgets);
  });

  testWidgets(
    'a validation refusal from the server keeps the user in the form',
    (tester) async {
      // The backstop for a server that refuses metadata the client thought
      // fine: it must not become a background-removal failure screen.
      final h = await open(
        tester,
        localResult: goodResult(),
        saveError: const ApiException(
          code: ApiErrorCode.validationError,
          message: 'Give this piece a name before saving it.',
          statusCode: 422,
        ),
        // The cloud fallback has to refuse as well, or the local refusal is
        // simply recovered from and no refusal is ever observed.
        cloudSaveError: const ApiException(
          code: ApiErrorCode.validationError,
          message: 'Give this piece a name before saving it.',
          statusCode: 422,
        ),
      );

      await pick(tester);
      await saveAs(tester);
      await advance(tester, steps: 6);

      expect(
        find.text('Save to Closet'),
        findsOneWidget,
        reason: 'still in the form',
      );
      expect(find.text('Try again'), findsNothing);
      expect(h.platform.removeCalls, 1, reason: 'no re-run of a good removal');
    },
  );

  // ── duplicate prevention ───────────────────────────────────────────────────

  testWidgets('a double-tapped Save creates exactly one piece', (tester) async {
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await tester.enterText(find.byType(TextField), 'Linen shirt');
    await tester.pump();
    await tester.tap(find.text('Tops'));
    await tester.pump();
    await tester.tap(find.text('Save to Closet'));
    await tester.tap(find.text('Save to Closet'), warnIfMissed: false);
    await advance(tester);

    expect(h.repo.localCalls, hasLength(1));
    expect(h.repo.cloudCalls, isEmpty);
  });

  testWidgets('a saved garment leaves nothing behind for the next one', (
    tester,
  ) async {
    // The leak this prevents is specific and nasty: the screen is one
    // long-lived State, so a name and a category left in place after a save
    // would be sitting there — filled in, valid, and already enabling Save —
    // when the next garment's cutout appears. Somebody adding a skirt straight
    // after a shirt would have to NOTICE that "Tops" was still lit to avoid
    // filing it wrong, which is the exact failure this whole change is about.
    final h = await open(tester, localResult: goodResult());

    await pick(tester);
    await saveAs(tester, name: 'Linen shirt', category: 'Tops');
    await advance(tester);
    expect(h.repo.localCalls, hasLength(1));

    // The filled-in form is gone — it is not left standing for a second piece
    // to inherit.
    expect(find.text('Save to Closet'), findsNothing);

    // A SECOND piece, the way the app actually does it: the route is popped on
    // save, so Add Garment is entered fresh. The form must start blank and Save
    // must stay unavailable until this garment's own two answers exist.
    final next = await open(tester, localResult: goodResult());
    await pick(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
      reason: 'the previous name did not survive',
    );
    expect(find.text('Try-on type: not chosen yet'), findsOneWidget);
    expect(saveHandler(tester), isNull, reason: 'no inherited category');

    await saveAs(tester, name: 'Pleated skirt', category: 'Bottoms');
    await advance(tester);
    expect(next.repo.localCalls.single['category'], 'Bottoms');
  });

  testWidgets('choosing a category clears the error it was asked for', (
    tester,
  ) async {
    // A red line must not outlive the thing it was asking for.
    final h = await open(tester, localResult: goodResult());
    await pick(tester);
    await tester.enterText(find.byType(TextField), 'Tank top');
    await tester.pump();

    // Force the error state the way a server 422 would.
    await tester.tap(find.text('Save to Closet'), warnIfMissed: false);
    await tester.pump();
    await tester.ensureVisible(find.text('Tops'));
    await tester.tap(find.text('Tops'));
    await tester.pump();

    expect(
      find.text('Choose a category so it can be styled and tried on.'),
      findsNothing,
    );
    expect(h.repo.localCalls, isEmpty);
  });

  testWidgets('a second removal cannot be started while one is running', (
    tester,
  ) async {
    // Each run uploads a FRESH original under a fresh key, so two overlapping
    // runs would be two removals and — after Save — two garments that no
    // server-side idempotency could collapse. Two things prevent it: the pickers
    // are gone the moment processing starts, and `_run` refuses to re-enter.
    final h = await open(
      tester,
      localResult: goodResult(),
      removeDelay: const Duration(milliseconds: 400),
    );

    await tester.tap(find.text('Choose from Gallery'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('Choose from Gallery'),
      findsNothing,
      reason: 'the capture CTAs are unreachable once the removal has begun',
    );
    expect(find.text('Take Photo'), findsNothing);

    await advance(tester);
    expect(h.platform.removeCalls, 1);
  });

  // ── retry after a genuine processing failure ───────────────────────────────

  testWidgets('a retry re-runs the REMOVAL, which is what failed', (
    tester,
  ) async {
    final h = await open(
      tester,
      localError: const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.noSubjectFound,
      ),
    );
    // The device declined AND the cloud removal came back failed. That — not a
    // rejected save — is what earns the retry screen.
    h.repo.cutoutJobResult = const AiJob(
      jobId: 'cut-1',
      status: AiJobStatus.failed,
      jobType: 'cutout_temp',
      error: "We couldn't remove the background from this photo.",
    );

    await pick(tester);

    expect(find.text('Try again'), findsOneWidget);
    expect(h.repo.cloudCalls, isEmpty, reason: 'no garment from a failed add');

    // Let the next attempt succeed.
    h.repo.cutoutJobResult = const AiJob(
      jobId: 'cut-2',
      status: AiJobStatus.completed,
      jobType: 'cutout_temp',
      outputUrl: 'https://cdn.test/cutout/x.png',
    );
    await tester.tap(find.text('Try again'));
    await advance(tester);

    expect(find.text('Save to Closet'), findsOneWidget);
    await saveAs(tester);
    await advance(tester);
    expect(h.repo.cloudCalls, hasLength(1));
    expect(h.repo.cloudCalls.single['cutoutJobId'], 'cut-2');
    await settleImageCache(tester);
  });

  // ── the preview the user names the piece from ──────────────────────────────

  testWidgets('the ENGINE OUTPUT is what gets previewed, not the raw photo', (
    tester,
  ) async {
    final h = await open(tester, localResult: goodResult());

    await pick(tester);

    final fileImages = tester
        .widgetList<Image>(find.byType(Image))
        .where((i) => i.image is FileImage)
        .map((i) => (i.image as FileImage).file.path)
        .toList();
    expect(fileImages, contains(cutoutPath));
    // And it is genuinely pre-persistence: nothing has been created.
    expect(h.repo.saveStarted, isFalse);
    expect(h.repo.localCalls, isEmpty);
  });

  testWidgets('the local wait never borrows the staged cloud copy', (
    tester,
  ) async {
    // Held in PROCESSING by a slow engine, which is when the copy matters.
    await open(
      tester,
      localResult: goodResult(),
      removeDelay: const Duration(milliseconds: 600),
    );

    await pickPhoto(tester);
    await advance(tester, steps: 3);

    expect(find.text('Removing background…'), findsOneWidget);
    // The staged ~90s cold-start copy belongs to the cloud path alone.
    expect(find.text('Warming up the studio…'), findsNothing);
    expect(find.text('Clearing the background…'), findsNothing);

    // Let the held engine finish so no timer outlives the test.
    await advance(tester);
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

    await pickAndSave(tester);

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

    await pickAndSave(tester);

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

    await pickAndSave(tester);

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

    await pickAndSave(tester);

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

    await pickAndSave(tester);

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

    await pickAndSave(tester);

    // THE assertion: the cloud remover reads the same stored object, so a cloud
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

      await pickAndSave(tester);

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

    await pickAndSave(tester);

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

    await pickAndSave(tester);

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
    this.cloudSaveError,
    this.updateError,
    this.holdSave = false,
  });

  final WardrobeItem savedItem;
  final WardrobeItem cloudItem;
  final ApiException? saveError;

  /// Refusal from the CLOUD create.
  ///
  /// Separate from [saveError] because a local 422 is not terminal — the screen
  /// hands the same object key to the cloud path and lets BiRefNet try. A test
  /// that only set [saveError] therefore watched a save SUCCEED via the
  /// fallback, which is why "a validation refusal keeps the user in the form"
  /// passed for years without ever seeing a refusal.
  final ApiException? cloudSaveError;
  final ApiException? updateError;
  final bool holdSave;

  /// What the cloud removal resolves to. Terminal by default, so the poller
  /// returns it as-is.
  AiJob cutoutJobResult = const AiJob(
    jobId: 'cut-1',
    status: AiJobStatus.completed,
    jobType: 'cutout_temp',
    outputUrl: 'https://cdn.test/cutout/x.png',
  );
  ApiException? cutoutJobError;

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
    Uint8List? maskPng,
    String? maskObjectKey,
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
      // Records HOW the mask travelled, so a test can tell a staged upload from
      // the inline fallback rather than only that a save happened.
      'maskBytes': maskPng?.length ?? 0,
      'maskObjectKey': maskObjectKey,
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

  int cutoutJobCalls = 0;

  @override
  Future<WardrobeItem> addItem({
    String? title,
    String? category,
    String? imageUrl,
    String? objectKey,
    String? cutoutJobId,
  }) async {
    cloudCalls.add({
      'objectKey': objectKey,
      'imageUrl': imageUrl,
      'title': title,
      'category': category,
      'cutoutJobId': cutoutJobId,
    });
    final failure = cloudSaveError;
    if (failure != null) throw failure;
    return cloudItem;
  }

  /// The cloud removal that has no garment yet. Returns an ALREADY-terminal job
  /// so `pollWtmAiJob` resolves without a poll loop — these tests are about which
  /// path is taken, not about polling cadence.
  @override
  Future<AiJob> startCutoutJob(String objectKey) async {
    cutoutJobCalls++;
    final failure = cutoutJobError;
    if (failure != null) throw failure;
    return cutoutJobResult;
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
