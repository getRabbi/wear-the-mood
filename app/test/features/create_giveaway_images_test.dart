import 'dart:async';
import 'dart:typed_data';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/giveaway.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/giveaway_repository.dart';
import 'package:app/features/giveaway/create_giveaway_screen.dart';
import 'package:app/features/social/post_image_service.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/ui/widgets/widgets.dart';

/// Giveaway image publishing.
///
/// The two real defects covered here:
///   * the "Give it away" prefill stored the closet item's DISPLAY url, which for
///     a private R2 object is a short-lived SIGNED url — so a published listing's
///     photo 403'd as soon as the signature expired;
///   * Publish was tappable while an upload was still in flight, quietly dropping
///     that image from an otherwise successful listing.
class _FakeImages implements PostImageService {
  _FakeImages({this.failDownload = false});

  final bool failDownload;
  final List<String> uploadedSectors = [];
  final List<String> downloaded = [];

  /// Completed by the test to control when an upload finishes.
  Completer<String>? gate;

  @override
  Future<Uint8List?> pickAndCompress(ImageSource source) async =>
      Uint8List.fromList([1, 2, 3]);

  @override
  Future<String> upload(Uint8List bytes, {String sector = 'post'}) async {
    uploadedSectors.add(sector);
    if (gate != null) return gate!.future;
    return 'https://cdn.test/durable-${uploadedSectors.length}.webp';
  }

  @override
  Future<Uint8List> downloadImageBytes(String url) async {
    downloaded.add(url);
    if (failDownload) throw StateError('gone');
    return Uint8List.fromList([9, 9, 9]);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeGiveaways implements GiveawayRepository {
  final List<List<String>> published = [];

  @override
  Future<Giveaway> create({
    required String title,
    String? description,
    List<String> images = const [],
    String? size,
    String? category,
    String? condition,
    String? areaLabel,
    String? wardrobeItemId,
  }) async {
    published.add(images);
    return Giveaway(
      id: 'g1',
      ownerId: 'u1',
      title: title,
      status: 'available',
      images: images,
      createdAt: DateTime.now(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

WardrobeItem _item() => WardrobeItem(
  id: 'w1',
  title: 'Linen shirt',
  category: 'tops',
  // A signed, expiring private-object url — exactly what must NOT be published.
  cutoutUrl: 'https://r2.test/u1/cutout/x.webp?X-Amz-Expires=900&sig=abc',
  cutoutStatus: 'done',
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap({
    required _FakeImages images,
    required _FakeGiveaways repo,
    WardrobeItem? item,
  }) {
    return ProviderScope(
      overrides: [
        postImageServiceProvider.overrideWithValue(images),
        giveawayRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CreateGiveawayScreen(item: item),
      ),
    );
  }

  testWidgets(
    'a prefilled closet photo is COPIED to durable storage, never published '
    'as the expiring signed url',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final images = _FakeImages();
      final repo = _FakeGiveaways();
      await tester.pumpWidget(wrap(images: images, repo: repo, item: _item()));
      await tester.pumpAndSettle();

      // The item's own signed url was fetched, then re-uploaded as giveaway media.
      expect(images.downloaded.single, contains('X-Amz-Expires'));
      expect(images.uploadedSectors, ['giveaway']);

      await tester.enterText(find.byType(TextField).first, 'Linen shirt');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish listing'));
      await tester.pumpAndSettle();

      expect(repo.published, hasLength(1));
      final published = repo.published.single;
      expect(published, hasLength(1));
      expect(published.single, 'https://cdn.test/durable-1.webp');
      expect(published.single, isNot(contains('X-Amz-Expires')));
    },
  );

  testWidgets('publishing is blocked while an upload is still in flight', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final images = _FakeImages()..gate = Completer<String>();
    final repo = _FakeGiveaways();
    await tester.pumpWidget(wrap(images: images, repo: repo, item: _item()));
    await tester.pump(); // let the prefill start, but not finish

    await tester.enterText(find.byType(TextField).first, 'Linen shirt');
    await tester.pump();

    // The CTA is disabled, so the listing cannot be published without its photo.
    final cta = tester.widget<GradientCta>(find.byType(GradientCta));
    expect(cta.onPressed, isNull);

    images.gate!.complete('https://cdn.test/durable-1.webp');
    await tester.pumpAndSettle();

    final ready = tester.widget<GradientCta>(find.byType(GradientCta));
    expect(ready.onPressed, isNotNull);
  });

  testWidgets(
    'a failed prefill copy is reported, never published as a broken image',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final images = _FakeImages(failDownload: true);
      final repo = _FakeGiveaways();
      await tester.pumpWidget(wrap(images: images, repo: repo, item: _item()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't copy that closet photo"),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).first, 'Linen shirt');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish listing'));
      await tester.pumpAndSettle();

      // Published with NO image rather than with a url that will 403.
      expect(repo.published.single, isEmpty);
      expect(images.uploadedSectors, isEmpty);
    },
  );
}
