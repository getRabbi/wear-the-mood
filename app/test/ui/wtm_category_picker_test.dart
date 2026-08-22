import 'dart:io';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:app/features/tryon/garment_role.dart';
import 'package:app/features/tryon/tryon_category_gate.dart';
import 'package:app/features/wardrobe/closet_category.dart';
import 'package:app/features/wardrobe/garment_category.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/theme/wtm_colors.dart';
import 'package:app/ui/closet/wtm_category_picker.dart';
import 'package:app/ui/closet/wtm_category_resolver.dart';
import 'package:app/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_wardrobe_items.dart';

/// The category picker, and the inline repair that stands between a Try On tap
/// and a charge.
///
/// What these are really protecting is a person's own photograph: a garment
/// filed under the wrong role is rendered onto the wrong part of their body,
/// charged for, and looks like the product is broken. So the picker has to make
/// the consequence of a choice visible BEFORE it is committed, and the repair
/// has to be strictly ordered — save, confirm, then continue.
void main() {
  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  // ── the vocabulary ─────────────────────────────────────────────────────────

  group('vocabulary', () {
    test('every choice maps to the canonical role the app claims', () {
      // The app tells somebody "Try-on type: Bottoms" before any round trip.
      // That promise is only honest if the client mirror agrees with the value
      // being stored — and the backend parity test checks the server does too.
      for (final category in kGarmentCategories) {
        expect(
          canonicalRoleOf(category.value),
          category.role,
          reason: category.value,
        );
      }
    });

    test('every renderable role is reachable', () {
      // The defect that started this: a hijab, a watch and a pair of sunglasses
      // all had to be saved as "Accessories", which resolves to no body region
      // at all, so none of them could ever be worn.
      final offered = {for (final c in kGarmentCategories) c.role};
      for (final role in kTryOnCapableRoles) {
        if (role == kLookReferenceCategory) continue; // not a closet category
        expect(offered, contains(role), reason: role);
      }
    });

    test(
      'an unknown or legacy value matches nothing, rather than the closest',
      () {
        // Exact match only. A fuzzy match here is what let the Edit sheet
        // re-affirm a category nobody chose.
        expect(garmentCategoryOf('Party'), isNull);
        expect(garmentCategoryOf('Accessories'), isNull);
        expect(garmentCategoryOf(''), isNull);
        expect(garmentCategoryOf(null), isNull);
        // Case is not meaning, though.
        expect(garmentCategoryOf('tops')?.value, 'Tops');
      },
    );

    test('an unrenderable choice is marked, not hidden', () {
      expect(garmentCategoryOf('Belts')!.isTryOnCapable, isFalse);
      expect(garmentCategoryOf('Other')!.isTryOnCapable, isFalse);
      expect(garmentCategoryOf('Hijab')!.isTryOnCapable, isTrue);
    });
  });

  /// What the tile for [value] declares to a screen reader about selection.
  bool? selectedFlagFor(WidgetTester tester, String value) => tester
      .widget<Semantics>(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').startsWith('$value.'),
        ),
      )
      .properties
      .selected;

  // ── the closet chips ARE the picker categories ─────────────────────────────

  group('closet filters', () {
    test('every picker category has its own chip', () {
      // The bug this pins: the closet used to show a person a DIFFERENT
      // vocabulary from the one they had just chosen from after background
      // removal. Somebody who deliberately saved a piece as "Hijab" then had to
      // know it lived under "Accessories" to find it again.
      for (final category in kGarmentCategories) {
        final chip = ClosetCategoryX.filterFor(category.value);
        expect(chip, isNotNull, reason: '${category.value} has no chip');
        expect(chip!.garment?.value, category.value);
      }
    });

    test('the chips are exactly the twelve, plus All and Favorites', () {
      final real = [
        for (final c in ClosetCategory.values)
          if (c != ClosetCategory.all && c != ClosetCategory.favorites) c,
      ];
      expect(real, hasLength(kGarmentCategories.length));
      // Same list, SAME ORDER — a person's eye should find them in the place
      // the picker put them.
      expect(
        [for (final c in real) c.garment!.value],
        [for (final g in kGarmentCategories) g.value],
      );
    });

    test('every enum name resolves to a picker category', () {
      // `garment` is derived from the enum's own `name`, so a rename on either
      // side would silently empty a chip. This is the test that stops that.
      for (final c in ClosetCategory.values) {
        if (c == ClosetCategory.all || c == ClosetCategory.favorites) {
          expect(c.garment, isNull, reason: c.name);
        } else {
          expect(
            c.garment,
            isNotNull,
            reason: 'no GarmentCategory for "${c.name}"',
          );
        }
      }
    });

    test('a piece belongs to exactly one chip', () {
      for (final category in kGarmentCategories) {
        final matched = [
          for (final c in ClosetCategory.values)
            if (c != ClosetCategory.all &&
                c != ClosetCategory.favorites &&
                c.matches(category.value))
              c,
        ];
        expect(matched, hasLength(1), reason: '${category.value} -> $matched');
      }
    });

    test('the label is the one the picker showed', () {
      // Not a second set of strings that can drift: `closetCatTops` and friends
      // are gone, and the chip reads whatever the tile read.
      expect(ClosetCategory.hijab.garment!.value, 'Hijab');
      expect(ClosetCategory.eyewear.garment!.value, 'Eyewear');
      expect(ClosetCategory.jewelry.garment!.value, 'Jewelry');
      expect(ClosetCategory.other.garment!.value, 'Other');
    });

    test('matching is exact, never a substring', () {
      // The original keyword table asked "does the category contain 'top'",
      // which is the same class of guess this whole rework removed.
      expect(ClosetCategoryX.filterFor('laptop bag'), isNull);
      expect(ClosetCategoryX.filterFor('Party'), isNull);
      expect(ClosetCategoryX.filterFor('Activewear'), isNull);
      expect(ClosetCategoryX.filterFor(''), isNull);
      expect(ClosetCategoryX.filterFor(null), isNull);
      // Case and padding are not meaning.
      expect(ClosetCategoryX.filterFor('  tops '), ClosetCategory.tops);
    });

    test('a legacy value is filtered by nothing but All', () {
      // It stays fully visible, and the review banner offers to repair it — it
      // is never guessed into a chip its owner did not choose. "accessories" is
      // the live example: 7 pieces in production carry it.
      for (final legacy in const ['Party', 'accessories', 'Activewear']) {
        expect(ClosetCategory.all.matches(legacy), isTrue);
        for (final c in ClosetCategory.values) {
          if (c == ClosetCategory.all || c == ClosetCategory.favorites)
            continue;
          expect(c.matches(legacy), isFalse, reason: '$legacy -> ${c.name}');
        }
      }
    });

    test('Hijab and Jewelry have their own chips and are renderable', () {
      // The two the old picker could not express at all, and which the old
      // filter row then buried under "Accessories".
      expect(ClosetCategory.hijab.matches('Hijab'), isTrue);
      expect(ClosetCategory.jewelry.matches('Jewelry'), isTrue);
      expect(garmentCategoryOf('Hijab')!.role, kRoleHijabScarf);
      expect(garmentCategoryOf('Jewelry')!.role, kRoleJewelry);
      expect(garmentCategoryOf('Hijab')!.isTryOnCapable, isTrue);
      expect(garmentCategoryOf('Jewelry')!.isTryOnCapable, isTrue);
    });
  });

  // ── the picker ─────────────────────────────────────────────────────────────

  group('picker', () {
    testWidgets('nothing is selected until somebody taps', (tester) async {
      await tester.pumpWidget(
        host(WtmCategoryPicker(selected: null, onChanged: (_) {})),
      );

      // No tile carries the selected state. Read straight off the widget's own
      // `Semantics.properties` rather than the composed semantics tree: the
      // tree encodes selection as a tristate whose spelling has already moved
      // once, and what is being asserted is what this picker declares.
      for (final category in kGarmentCategories) {
        expect(
          selectedFlagFor(tester, category.value),
          isFalse,
          reason: category.value,
        );
      }
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('each choice shows concrete examples', (tester) async {
      await tester.pumpWidget(
        host(WtmCategoryPicker(selected: null, onChanged: (_) {})),
      );
      expect(find.text('T-shirt, shirt, blouse, sweater'), findsOneWidget);
      expect(find.text('Pants, jeans, skirt, shorts'), findsOneWidget);
      expect(find.text('Dress, jumpsuit, saree, abaya'), findsOneWidget);
      expect(find.text('Necklace, earrings, watch, ring'), findsOneWidget);
    });

    testWidgets('a selected tile is marked by more than colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(WtmCategoryPicker(selected: 'Bottoms', onChanged: (_) {})),
      );
      // A check glyph, so the state survives for somebody who cannot separate
      // the gold border from the hairline one (§4.4).
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(selectedFlagFor(tester, 'Bottoms'), isTrue);
      expect(selectedFlagFor(tester, 'Tops'), isFalse);
    });

    testWidgets('a screen reader hears the example, not just the label', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(WtmCategoryPicker(selected: null, onChanged: (_) {})),
      );
      expect(
        find.bySemanticsLabel('Bottoms. Pants, jeans, skirt, shorts'),
        findsOneWidget,
      );
    });

    testWidgets('a legacy value is stated, never silently re-selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          WtmCategoryPicker(
            selected: null,
            legacyValue: 'Party',
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('Currently saved as "Party"'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('the summary names the consequence of the choice', (
      tester,
    ) async {
      await tester.pumpWidget(host(const WtmTryOnTypeSummary(selected: null)));
      expect(find.text('Try-on type: not chosen yet'), findsOneWidget);

      await tester.pumpWidget(
        host(const WtmTryOnTypeSummary(selected: 'Bottoms')),
      );
      expect(find.text('Try-on type: Bottoms'), findsOneWidget);

      // An unrenderable choice does not pretend otherwise.
      await tester.pumpWidget(
        host(const WtmTryOnTypeSummary(selected: 'Belts')),
      );
      expect(
        find.text('Belts — saved to your closet, not worn in try-ons'),
        findsOneWidget,
      );
    });

    testWidgets('tiles are disabled while a save is in flight', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          WtmCategoryPicker(
            selected: 'Tops',
            enabled: false,
            onChanged: (_) => taps++,
          ),
        ),
      );
      await tester.tap(find.text('Bottoms'), warnIfMissed: false);
      await tester.pump();
      // The value cannot move under the request that is carrying it.
      expect(taps, 0);
    });

    testWidgets('the required-field error only appears once asked for', (
      tester,
    ) async {
      const message = 'Choose a category so it can be styled and tried on.';
      await tester.pumpWidget(
        host(WtmCategoryPicker(selected: null, onChanged: (_) {})),
      );
      expect(find.text(message), findsNothing, reason: 'untouched form');

      await tester.pumpWidget(
        host(
          WtmCategoryPicker(selected: null, showError: true, onChanged: (_) {}),
        ),
      );
      expect(find.text(message), findsOneWidget);
    });

    testWidgets('renders on the dark WTM ground', (tester) async {
      // The picker only ever appears over WtmColors.panel/bg, so the selected
      // state has to be legible there rather than on a default light Scaffold.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(brightness: Brightness.dark),
            home: const Scaffold(
              backgroundColor: WtmColors.bg,
              body: SingleChildScrollView(
                child: WtmCategoryPicker(selected: 'Hijab', onChanged: _noop),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Hijab, scarf, shawl, dupatta'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });

  // ── the legacy repair ──────────────────────────────────────────────────────

  group('resolver', () {
    // No image urls: `cached_network_image` reaches for `path_provider`, which
    // has no implementation in a widget test, so a sheet holding one never
    // settles. These tests are about the ORDER of save-then-continue; the
    // thumbnail requirement has its own test below.
    const legacy = WardrobeItem(
      id: 'w1',
      title: 'Old piece',
      classificationStatus: 'needs_review',
    );
    const ready = WardrobeItem(
      id: 'w2',
      title: 'Linen shirt',
      category: 'Tops',
      canonicalCategory: 'top',
      classificationStatus: 'valid',
      tryOnReady: true,
    );

    Future<_Harness> open(
      WidgetTester tester,
      WardrobeItem item, {
      ApiException? error,
    }) async {
      final repo = _FakeRepo(error: error);
      late BuildContext ctx;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wardrobeRepositoryProvider.overrideWithValue(repo),
            wardrobeItemsProvider.overrideWith(
              () => FakeWardrobeItemsNotifier([item]),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                ctx = context;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        ),
      );
      return _Harness(repo, ctx);
    }

    testWidgets('an already-readable piece is never interrupted', (
      tester,
    ) async {
      final h = await open(tester, ready);
      final result = await wtmEnsureCategory(h.context, ready);
      await tester.pump();

      expect(result, ready, reason: 'passes straight through');
      expect(h.repo.updates, isEmpty, reason: 'nothing to repair');
      expect(find.text('What kind of piece is this?'), findsNothing);
    });

    testWidgets('a cached item from an older build is never nagged', (
      tester,
    ) async {
      // `try_on_ready` defaults to false on a payload that predates the field,
      // so "needs a category" has to require a POSITIVE `needs_review` verdict
      // rather than the absence of a positive one. Otherwise every item in a
      // closet cached by 1.0.23+28 would start asking to be identified.
      const cached = WardrobeItem(id: 'w8', title: 'From an old cache');
      expect(cached.needsCategory, isFalse);
      expect(cached.tryOnReady, isFalse);

      final h = await open(tester, cached);
      final result = await wtmEnsureCategory(h.context, cached);
      await tester.pump();

      expect(result, cached);
      expect(find.text('What kind of piece is this?'), findsNothing);
      expect(h.repo.updates, isEmpty);
    });

    testWidgets('a legacy piece is asked about, then continues', (
      tester,
    ) async {
      final h = await open(tester, legacy);
      final pending = wtmEnsureCategory(h.context, legacy);
      await tester.pumpAndSettle();

      expect(find.text('What kind of piece is this?'), findsOneWidget);
      // Save is unavailable until an answer exists.
      expect(
        tester
            .widget<GradientCta>(
              find.widgetWithText(GradientCta, 'Save & Try On'),
            )
            .onPressed,
        isNull,
      );

      await tester.ensureVisible(find.text('Dresses'));
      await tester.tap(find.text('Dresses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & Try On'));
      await tester.pumpAndSettle();

      // The category was saved FIRST, and the caller is handed the item the
      // SERVER returned — not a locally patched guess.
      expect(h.repo.updates.single['category'], 'Dresses');
      final result = await pending;
      expect(result?.category, 'Dresses');
      expect(result?.tryOnReady, isTrue);
    });

    testWidgets('the button does not promise a try-on that is not coming', (
      tester,
    ) async {
      // Found on a real device. Opened from the closet's review banner, the
      // sheet saved the category, closed, and returned to the closet — exactly
      // as designed, and not at all as labelled: the button read "Save & Try
      // On". Tidying a closet is not starting a render, and the copy has to
      // say which one is about to happen.
      final h = await open(tester, legacy);

      unawaited_(showWtmCategoryResolver(h.context, item: legacy));
      await tester.pumpAndSettle();
      expect(find.text('Save & Try On'), findsOneWidget);
      Navigator.of(h.context).pop();
      await tester.pumpAndSettle();

      unawaited_(
        showWtmCategoryResolver(
          h.context,
          item: legacy,
          continuesToTryOn: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save category'), findsOneWidget);
      expect(find.text('Save & Try On'), findsNothing);
    });

    testWidgets('backing out starts nothing', (tester) async {
      final h = await open(tester, legacy);
      final pending = wtmEnsureCategory(h.context, legacy);
      await tester.pumpAndSettle();

      Navigator.of(h.context).pop();
      await tester.pumpAndSettle();

      // Null is the caller's instruction to stop: no job, no credit.
      expect(await pending, isNull);
      expect(h.repo.updates, isEmpty);
    });

    testWidgets('a failed update starts no try-on and says why', (
      tester,
    ) async {
      final h = await open(
        tester,
        legacy,
        error: const ApiException(
          code: ApiErrorCode.network,
          // Raw transport text — exactly what must NOT reach a person.
          message: 'Connection closed before full header was received',
        ),
      );
      final pending = wtmEnsureCategory(h.context, legacy);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Tops'));
      await tester.tap(find.text('Tops'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & Try On'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "You're offline. Reconnect and try again — nothing was saved.",
        ),
        findsOneWidget,
      );
      expect(
        find.text('Connection closed before full header was received'),
        findsNothing,
        reason: 'never a transport error',
      );
      // The sheet stays open, so the answer is not lost — and crucially the
      // caller has not been told to proceed.
      expect(find.text('What kind of piece is this?'), findsOneWidget);

      Navigator.of(h.context).pop();
      await tester.pumpAndSettle();
      expect(await pending, isNull);
    });

    testWidgets('an expired session is named as one', (tester) async {
      final h = await open(
        tester,
        legacy,
        error: const ApiException(
          code: ApiErrorCode.unauthenticated,
          message: 'Missing bearer token.',
        ),
      );
      unawaited_(wtmEnsureCategory(h.context, legacy));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tops'));
      await tester.tap(find.text('Tops'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & Try On'));
      await tester.pumpAndSettle();

      expect(
        find.text('Your session expired. Sign in again to save this.'),
        findsOneWidget,
      );
    });

    testWidgets("a server's own validation copy is kept", (tester) async {
      // The backend authored this sentence for exactly this case; replacing it
      // with something generic would be worse, and would freeze the wording to
      // whatever shipped in the client.
      final h = await open(
        tester,
        legacy,
        error: const ApiException(
          code: ApiErrorCode.validationError,
          message:
              "That category isn't supported any more. Please choose another.",
          statusCode: 422,
        ),
      );
      unawaited_(wtmEnsureCategory(h.context, legacy));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tops'));
      await tester.tap(find.text('Tops'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & Try On'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "That category isn't supported any more. Please choose another.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a double-tapped Save updates once', (tester) async {
      final h = await open(tester, legacy);
      unawaited_(wtmEnsureCategory(h.context, legacy));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Tops'));
      await tester.tap(find.text('Tops'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & Try On'));
      await tester.tap(find.text('Save & Try On'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // One PATCH — and, because the caller continues a try-on on success, one
      // "go ahead" for one question.
      expect(h.repo.updates, hasLength(1));
    });

    testWidgets('the real garment is shown, not a placeholder', (tester) async {
      // Somebody asked to identify a piece has to be looking at the piece.
      const withImage = WardrobeItem(
        id: 'w9',
        title: 'Old piece',
        classificationStatus: 'needs_review',
        cutoutUrl: 'https://cdn.test/a.png',
      );
      final h = await open(tester, withImage);
      unawaited_(wtmEnsureCategory(h.context, withImage));
      // Bounded pumps rather than pumpAndSettle: the image never resolves here.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final tile = tester.widget<FabricTile>(find.byType(FabricTile));
      expect(tile.imageUrl, 'https://cdn.test/a.png');
      expect(find.text('What kind of piece is this?'), findsOneWidget);
    });

    testWidgets('a multi-piece look asks once per unknown garment', (
      tester,
    ) async {
      const other = WardrobeItem(
        id: 'w3',
        title: 'Another old piece',
        classificationStatus: 'needs_review',
      );
      final repo = _FakeRepo();
      late BuildContext ctx;
      late WidgetRef widgetRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wardrobeRepositoryProvider.overrideWithValue(repo),
            wardrobeItemsProvider.overrideWith(
              () => FakeWardrobeItemsNotifier([legacy, other]),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                ctx = context;
                widgetRef = ref;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        ),
      );

      final pending = resolveCategoriesForTryOn(ctx, widgetRef, [
        legacy,
        ready,
        other,
      ]);
      for (var i = 0; i < 2; i++) {
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Tops'));
        await tester.tap(find.text('Tops'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save & Try On'));
        await tester.pumpAndSettle();
      }

      final resolved = await pending;
      expect(resolved, hasLength(3));
      expect(
        repo.updates,
        hasLength(2),
        reason: 'the readable piece is skipped',
      );
    });
  });
  // ── nothing here asks a model ──────────────────────────────────────────────

  group('no classifier', () {
    /// The whole category path, as source. A garment's category is what its
    /// owner said it is, and this is the check that keeps it that way: an
    /// Anthropic call, an OpenAI Vision call, an ML Kit label or a
    /// guess-from-the-title added to any of these files is a category decided by
    /// something other than the person who owns the garment.
    const paths = [
      'lib/features/wardrobe/garment_category.dart',
      'lib/features/wardrobe/category_error.dart',
      'lib/features/tryon/tryon_category_gate.dart',
      'lib/ui/closet/wtm_category_picker.dart',
      'lib/ui/closet/wtm_category_resolver.dart',
    ];

    test('the category path names no AI provider', () {
      const forbidden = [
        'anthropic',
        'openai',
        'gpt',
        'claude',
        'vision',
        'classif',
        'imagelabel',
        'mlkit',
        'autotag',
      ];
      for (final path in paths) {
        // Comments only, stripped: these files EXPLAIN at length why no
        // classifier is involved, and scanning the prose would flag the
        // documentation of the very rule being enforced.
        final source = File(path)
            .readAsLinesSync()
            .where((line) => !line.trimLeft().startsWith('//'))
            .join(' ')
            .toLowerCase();
        for (final needle in forbidden) {
          expect(
            source.contains(needle),
            isFalse,
            reason: '$path mentions "$needle"',
          );
        }
      }
    });

    test('the category comes from the picker, never from a title', () {
      // `garmentCategoryOf` is an EXACT lookup by design. A phrase or keyword
      // match here would be title guessing wearing a different hat.
      expect(garmentCategoryOf('Summer Dress Shirt'), isNull);
      expect(garmentCategoryOf('my favourite tops'), isNull);
      expect(garmentCategoryOf('Tops'), isNotNull);
    });
  });
}

void _noop(String _) {}

/// `unawaited` without pulling in dart:async at every call site.
void unawaited_(Future<void> future) {}

class _Harness {
  _Harness(this.repo, this.context);
  final _FakeRepo repo;
  final BuildContext context;
}

class _FakeRepo implements WardrobeRepository {
  _FakeRepo({this.error});

  final ApiException? error;
  final List<Map<String, Object?>> updates = [];

  @override
  Future<WardrobeItem> updateItem(
    String id, {
    required String? title,
    required String? category,
    String? subcategory,
    String? color,
  }) async {
    updates.add({'id': id, 'title': title, 'category': category});
    final failure = error;
    if (failure != null) throw failure;
    // The SERVER's version of the row, including the role it derived — which is
    // the only thing the caller is allowed to continue on.
    return WardrobeItem(
      id: id,
      title: title,
      category: category,
      canonicalCategory: canonicalRoleOf(category),
      classificationStatus: 'valid',
      tryOnReady: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
