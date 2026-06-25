import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/tryon_result.dart';
import 'package:app/data/repositories/tryon_repository.dart';
import 'package:app/features/collections/local_collections.dart';
import 'package:app/features/tryon/save_look_service.dart';
import 'package:app/features/tryon/tryon_history_screen.dart';
import 'package:app/features/tryon/two_d/two_d_models.dart';
import 'package:app/l10n/app_localizations.dart';

/// A real 1×1 transparent PNG — decodable, so `Image.memory` in the tile never
/// throws an (uncaught) decode error and fails the test.
final _png1x1 = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54,
  0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, 0x05,
  0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap({
    required List<TwoDResult> twoD,
    required List<TryonResult> ai,
    required _RecordingSaveLookService save,
  }) => ProviderScope(
    overrides: [
      tryOnResultsProvider.overrideWith((ref) async => ai),
      twoDResultsProvider.overrideWith(() => _SeededTwoD(twoD)),
      saveLookServiceProvider.overrideWith((ref) {
        save.bind(ref);
        return save;
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TryOnHistoryScreen(),
    ),
  );

  testWidgets('BUG 2: a forgotten 2D result can be saved later from history', (
    tester,
  ) async {
    final save = _RecordingSaveLookService();
    final twoD = TwoDResult(bytes: _png1x1, id: 't1');
    await tester.pumpWidget(wrap(twoD: [twoD], ai: const [], save: save));
    await tester.pump(); // resolve the AI future

    // An un-saved result shows the outline bookmark.
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pump(); // run _save
    await tester.pump();

    expect(save.savedIds, ['t1']);
    // It now shows the filled (saved) bookmark and is recorded durably.
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TryOnHistoryScreen)),
    );
    expect(container.read(savedLookRecordsProvider).any((l) => l.id == 't1'), isTrue);
  });

  testWidgets('BUG 2: a forgotten AI result can be saved later from history', (
    tester,
  ) async {
    final save = _RecordingSaveLookService();
    final ai = [
      TryonResult(
        id: 'a1',
        resultImageUrl: 'https://x/result.jpg',
        createdAt: DateTime(2026, 6, 1),
      ),
    ];
    await tester.pumpWidget(wrap(twoD: const [], ai: ai, save: save));
    await tester.pump(); // resolve the AI future

    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pump();
    await tester.pump();

    expect(save.savedIds, ['a1']);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
  });

  testWidgets('BUG 2: once saved the control is inert — no double-save', (
    tester,
  ) async {
    final save = _RecordingSaveLookService();
    final twoD = TwoDResult(bytes: _png1x1, id: 'dup');
    await tester.pumpWidget(wrap(twoD: [twoD], ai: const [], save: save));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pump();
    await tester.pump();

    // The outline save control is replaced by the inert filled bookmark, so
    // there's no save affordance left to tap a second time (and one tap = one
    // record). The service is also idempotent on the id as a backstop.
    expect(save.savedIds, ['dup']);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
  });
}

/// Seeds [twoDResultsProvider] with fixed previews (no live capture).
class _SeededTwoD extends TwoDResults {
  _SeededTwoD(this._seed);

  final List<TwoDResult> _seed;

  @override
  List<TwoDResult> build() => _seed;
}

/// Records save calls and reflects them into [savedLookRecordsProvider] so the
/// tile's saved-state indicator flips — without any network upload.
class _RecordingSaveLookService implements SaveLookService {
  Ref? _ref;
  final List<String> savedIds = [];

  void bind(Ref ref) => _ref = ref;

  void _record(String id, String url) {
    savedIds.add(id);
    _ref!
        .read(savedLookRecordsProvider.notifier)
        .add(SavedLook(id: id, imageUrl: url, createdAt: DateTime.now()));
  }

  @override
  Future<void> saveBytes({required String id, required Uint8List bytes}) async =>
      _record(id, 'mem://$id');

  @override
  Future<void> saveFromUrl({required String id, required String url}) async =>
      _record(id, url);
}
