import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/wardrobe_analytics.dart';
import 'package:app/data/models/wardrobe_gap.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:app/features/wardrobe/add_wardrobe_item_screen.dart';
import 'package:app/features/wardrobe/wardrobe_image_service.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/widgets.dart';

// A valid 1x1 transparent PNG so Image.memory decodes without throwing.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
  0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _FakeImageService implements WardrobeImageService {
  _FakeImageService({this.pickResult});

  final Uint8List? pickResult;
  Uint8List? uploaded;

  @override
  Future<Uint8List?> pickAndCompress(ImageSource source) async => pickResult;

  @override
  Future<String> upload(Uint8List bytes) async {
    uploaded = bytes;
    return 'https://cdn.test/wardrobe/x.jpg';
  }
}

class _FakeWardrobeRepository implements WardrobeRepository {
  int addCalls = 0;
  String? addedImageUrl;
  String? addedTitle;
  String? addedCategory;

  @override
  Future<List<WardrobeItem>> getItems() async => const [];

  @override
  Future<List<WardrobeItem>> search({
    required String query,
    int limit = 20,
  }) async => const [];

  @override
  Future<WardrobeItem> addItem({
    String? title,
    String? category,
    required String imageUrl,
  }) async {
    addCalls++;
    addedTitle = title;
    addedCategory = category;
    addedImageUrl = imageUrl;
    return WardrobeItem(id: 'new', title: title, imageUrl: imageUrl);
  }

  @override
  Future<void> deleteItem(String id) async {}

  @override
  Future<WardrobeItem> updateItem(
    String id, {
    required String? title,
    required String? category,
    required String? color,
    String? subcategory,
  }) async => WardrobeItem(id: id, title: title, category: category);

  @override
  Future<WardrobeAnalytics> getAnalytics() async => const WardrobeAnalytics();

  @override
  Future<void> markWorn(String id) async {}

  @override
  Future<List<WardrobeGap>> getGaps() async => const [];
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  GoRouter router() => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Center(child: Text('home'))),
      ),
      GoRoute(path: '/add', builder: (_, _) => const AddWardrobeItemScreen()),
    ],
  );

  Widget app(GoRouter r) => MaterialApp.router(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: r,
  );

  Future<void> openAdd(
    WidgetTester tester, {
    required _FakeImageService image,
    required _FakeWardrobeRepository repo,
  }) async {
    // Taller than the default 800x600 so the 3:4 photo area + buttons fit.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final r = router();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeImageServiceProvider.overrideWithValue(image),
          wardrobeRepositoryProvider.overrideWithValue(repo),
        ],
        child: app(r),
      ),
    );
    await tester.pump();
    r.push('/add');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('pick a photo, then save uploads and posts it', (tester) async {
    final image = _FakeImageService(pickResult: _png);
    final repo = _FakeWardrobeRepository();
    await openAdd(tester, image: image, repo: repo);

    // Save is disabled until a photo is chosen.
    expect(
      tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
      isNull,
    );

    // Pick from the gallery → preview renders, Save enables.
    await tester.tap(find.text('Gallery'));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(
      tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Add to closet'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(repo.addCalls, 1);
    expect(repo.addedImageUrl, 'https://cdn.test/wardrobe/x.jpg');
    expect(image.uploaded, isNotNull);
    expect(find.text('home'), findsOneWidget); // popped back
  });

  testWidgets('cancelling the picker keeps save disabled', (tester) async {
    final image = _FakeImageService(pickResult: null); // user cancelled
    final repo = _FakeWardrobeRepository();
    await openAdd(tester, image: image, repo: repo);

    await tester.tap(find.text('Gallery'));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(
      tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
      isNull,
    );
    expect(repo.addCalls, 0);
  });
}
