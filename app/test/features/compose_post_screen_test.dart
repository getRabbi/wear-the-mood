import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/flags/feature_flags.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/outfit.dart';
import 'package:app/data/repositories/social_repository.dart';
import 'package:app/features/outfits/outfit_providers.dart';
import 'package:app/features/social/compose_post_screen.dart';
import 'package:app/l10n/app_localizations.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _createdPost() => {
  'id': 'new1',
  'user_id': 'u1',
  'author_name': 'Mim',
  'like_count': 0,
  'comment_count': 0,
  'liked_by_me': false,
  'created_at': '2026-06-21T10:00:00Z',
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
    'a poll-only post (no photo) shares with its poll attached (Issue 1)',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Mocked backend: capture the create-post body; everything else (the
      // post-create feed refresh) returns an empty list.
      Map<String, dynamic>? created;
      final (dio, _) = fakeDio((opts) {
        if (opts.method == 'POST' && opts.path.contains('/social/posts')) {
          created = Map<String, dynamic>.from(opts.data as Map);
          return jsonResponse(_createdPost(), status: 201);
        }
        return jsonResponse(<Object>[]);
      });

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('home'))),
          ),
          GoRoute(
            path: '/compose',
            builder: (_, _) => const ComposePostScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            socialRepositoryProvider.overrideWithValue(SocialRepository(dio)),
            outfitsProvider.overrideWith((ref) async => const <Outfit>[]),
            // Polls are flag-gated — turn the flag on for this test.
            enabledFeatureFlagsProvider.overrideWith(
              (ref) async => {FeatureFlags.postPolls},
            ),
            currentUserProvider.overrideWithValue(null),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      router.push('/compose');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // No photo, no poll → Share is disabled (a tap does nothing).
      await tester.tap(find.text('Share'));
      await tester.pump();
      expect(created, isNull);

      // Attach a valid poll: a question + two options.
      await tester.tap(find.text('Add a poll'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Poll question'),
        'Which fit?',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Option 1'), 'A');
      await tester.enterText(find.widgetWithText(TextField, 'Option 2'), 'B');
      await tester.pump();

      // A valid poll is shareable content on its own — Share now works.
      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(created, isNotNull, reason: 'a valid poll-only post should share');
      final poll = created!['poll'] as Map;
      expect(poll['question'], 'Which fit?');
      expect(poll['options'], ['A', 'B']);
      // Poll-only: no image / outfit was sent (null-aware entries omitted).
      expect(created!.containsKey('image_url'), isFalse);
      expect(created!.containsKey('outfit_id'), isFalse);

      // The composer popped back home on success.
      expect(find.text('home'), findsOneWidget);
    },
  );
}
