import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/repositories/social_repository.dart';
import 'package:app/features/social/feed_screen.dart';
import 'package:app/l10n/app_localizations.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _post(String id, {int likes = 2, bool liked = false}) => {
  'id': id,
  'user_id': 'u1',
  'author_name': 'Mim',
  'caption': 'my best look',
  'image_url': '$id.jpg',
  'like_count': likes,
  'comment_count': 0,
  'liked_by_me': liked,
  'created_at': '2026-06-11T10:00:00Z',
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap(Object feedBody) {
    final (dio, _) = fakeDio((_) => jsonResponse(feedBody));
    return ProviderScope(
      overrides: [
        socialRepositoryProvider.overrideWithValue(SocialRepository(dio)),
        currentUserProvider.overrideWithValue(null),
        // The feed now refetches per signed-in identity; give it one so it
        // loads in tests (the real provider would hit uninitialized Supabase).
        authUserIdProvider.overrideWithValue('u1'),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FeedScreen(),
      ),
    );
  }

  testWidgets('shows the empty state when there are no posts', (tester) async {
    await tester.pumpWidget(wrap(<Object>[]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No posts yet'), findsOneWidget);
  });

  testWidgets('renders posts with author and caption', (tester) async {
    // Tall surface so both 4:5 post cards are realized (not off-screen).
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap([_post('p1'), _post('p2')]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Mim'), findsNWidgets(2));
    expect(find.text('my best look'), findsNWidgets(2));
  });

  testWidgets('tapping like optimistically increments the count', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap([_post('p1', likes: 2, liked: false)]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump(); // optimistic state update (synchronous)

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Let the backing like request complete so no dio timer is left pending.
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('never renders a raw email as the author name', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final post = _post('p1');
    post['author_name'] = 'wearthemood24@gmail.com';
    await tester.pumpWidget(wrap([post]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('wearthemood24@gmail.com'), findsNothing);
    expect(find.text('Someone'), findsOneWidget);
  });

  testWidgets("another user's post offers report + block in the menu", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap([_post('p1')]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Report post'), findsOneWidget);
    expect(find.text('Block user'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
  });
}
