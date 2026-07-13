import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/share/share_service.dart';
import 'package:app/data/models/referral_summary.dart';
import 'package:app/data/repositories/referral_rewards_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/referral/wtm_referral_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

class _FakeShare implements ShareService {
  String? sharedText;

  @override
  Future<void> shareText(String text) async => sharedText = text;

  @override
  Future<void> shareImageBytes(
    Uint8List bytes, {
    String? text,
    bool watermark = false,
    String name = 'wearthemood_look.png',
  }) async {}
}

ReferralSummary _summary({
  bool enabled = true,
  int successful = 2,
  int total = 20,
  int bonus = 10,
}) => ReferralSummary(
  code: 'AB2CD3EF',
  url: 'https://wearthemood.com/r/AB2CD3EF',
  bonus: bonus,
  successfulCount: successful,
  totalEarned: total,
  enabled: enabled,
);

Future<_FakeShare> _pump(WidgetTester tester, ReferralSummary summary) async {
  final share = _FakeShare();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        referralSummaryProvider.overrideWith((ref) async => summary),
        shareServiceProvider.overrideWithValue(share),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WtmReferralScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return share;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    // Make secure storage resolve (empty) in tests so the "last seen" load
    // completes — the reward banner depends on it.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => call.method == 'readAll' ? <String, String>{} : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  testWidgets('renders code, link, share/copy, and stats', (tester) async {
    await _pump(tester, _summary());
    expect(find.text('AB2CD3EF'), findsOneWidget);
    expect(find.text('https://wearthemood.com/r/AB2CD3EF'), findsOneWidget);
    expect(find.widgetWithText(GradientCta, 'Invite friends'), findsOneWidget);
    expect(find.text('Copy link'), findsWidgets);
    expect(find.text('2'), findsOneWidget); // friends joined
    expect(find.text('20'), findsOneWidget); // credits earned
  });

  testWidgets('share uses the native invite text with the referral link', (
    tester,
  ) async {
    final share = await _pump(tester, _summary());
    await tester.tap(find.widgetWithText(GradientCta, 'Invite friends'));
    await tester.pump();
    expect(share.sharedText, contains('https://wearthemood.com/r/AB2CD3EF'));
    expect(share.sharedText, contains('Wear The Mood'));
  });

  testWidgets('shows the one-time reward banner when new referrals exist', (
    tester,
  ) async {
    // Secure storage is unavailable in tests → seen count defaults to 0, so 2
    // successful referrals surface as a fresh "you earned 20" banner.
    await _pump(tester, _summary(successful: 2, bonus: 10));
    expect(find.textContaining('You earned 20 referral credits'), findsOneWidget);
  });

  testWidgets('disabled program shows a calm notice, not the sell', (
    tester,
  ) async {
    await _pump(tester, _summary(enabled: false));
    expect(find.widgetWithText(GradientCta, 'Invite friends'), findsNothing);
    expect(find.textContaining('short break'), findsOneWidget);
  });

  testWidgets('referred-user confirmation never implies a personal reward', (
    tester,
  ) async {
    // The referred user's confirmation copy must not claim they earned credits.
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SizedBox.shrink(),
      ),
    );
    final context = tester.element(find.byType(SizedBox));
    final l10n = AppLocalizations.of(context);
    expect(l10n.wtmReferralApplied, 'Referral applied successfully.');
    expect(l10n.wtmReferralApplied.contains('10'), isFalse);
    expect(l10n.wtmReferralApplied.toLowerCase().contains('earn'), isFalse);
  });
}
