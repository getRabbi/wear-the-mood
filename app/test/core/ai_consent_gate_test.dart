import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/privacy/ai_consent_gate.dart';
import 'package:app/core/privacy/ai_consent_repository.dart';
import 'package:app/core/privacy/ai_input_privacy.dart';
import 'package:app/data/models/studio_model_preset.dart';
import 'package:app/data/models/tryon_photo.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/mirror/wtm_body_source.dart';

/// The privacy gate (§10, Apple 5.1.1(i)).
///
/// The assertions that matter are the negative ones: a decline must submit
/// nothing, and a flow that carries no personal photo must never see the sheet.

/// A repository whose every call is observable and individually failable.
class _FakeConsentRepo implements AiConsentRepository {
  _FakeConsentRepo({
    this.stored = const AiConsentState.unknown(),
    this.readThrows = false,
    this.grantThrows = false,
  });

  AiConsentState stored;
  bool readThrows;
  bool grantThrows;

  int reads = 0;
  int grants = 0;
  int revokes = 0;

  @override
  Future<AiConsentState> read() async {
    reads++;
    if (readThrows) throw Exception('offline');
    return stored;
  }

  @override
  Future<AiConsentState> grant() async {
    grants++;
    if (grantThrows) throw Exception('write failed');
    stored = const AiConsentState(
      granted: true,
      isCurrent: true,
      version: aiConsentVersion,
    );
    return stored;
  }

  @override
  Future<AiConsentState> revoke() async {
    revokes++;
    stored = const AiConsentState(
      granted: false,
      isCurrent: false,
      version: aiConsentVersion,
    );
    return stored;
  }
}

/// Pumps a screen with one button that runs the gate and records the answer.
Future<({List<bool> results, BuildContext context})> _pumpGate(
  WidgetTester tester,
  _FakeConsentRepo repo, {
  required AiInputPrivacy privacy,
}) async {
  final results = <bool>[];
  late BuildContext captured;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [aiConsentRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            captured = context;
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async => results.add(
                    await ensureAiConsent(context, ref, privacy: privacy),
                  ),
                  child: const Text('generate'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  return (results: results, context: captured);
}

void main() {
  group('ensureAiConsent', () {
    testWidgets('a personal photo with no consent shows the disclosure', (
      tester,
    ) async {
      final repo = _FakeConsentRepo();
      await _pumpGate(tester, repo, privacy: AiInputPrivacy.personalImage);

      await tester.tap(find.text('generate'));
      await tester.pumpAndSettle();

      expect(find.text('AI Photo Processing'), findsOneWidget);
      expect(find.text('Allow & Continue'), findsOneWidget);
      expect(find.text('Not Now'), findsOneWidget);
      // Every party that actually receives the photo is named on the sheet
      // itself, not buried behind the policy link.
      expect(find.textContaining('FASHN.ai'), findsOneWidget);
      expect(find.textContaining('OpenAI'), findsOneWidget);
    });

    testWidgets('Not Now proceeds with nothing — no grant, no go-ahead', (
      tester,
    ) async {
      final repo = _FakeConsentRepo();
      final harness = await _pumpGate(
        tester,
        repo,
        privacy: AiInputPrivacy.personalImage,
      );

      await tester.tap(find.text('generate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();

      expect(harness.results, [false], reason: 'the caller must not proceed');
      expect(repo.grants, 0, reason: 'declining must record no consent');
    });

    testWidgets('dismissing the sheet is a decline, never a grant', (
      tester,
    ) async {
      final repo = _FakeConsentRepo();
      final harness = await _pumpGate(
        tester,
        repo,
        privacy: AiInputPrivacy.personalImage,
      );

      await tester.tap(find.text('generate'));
      await tester.pumpAndSettle();
      // Tap the scrim — the same escape a back gesture takes.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(harness.results, [false]);
      expect(repo.grants, 0, reason: 'silence is never consent');
    });

    testWidgets('Allow & Continue records consent, then proceeds', (
      tester,
    ) async {
      final repo = _FakeConsentRepo();
      final harness = await _pumpGate(
        tester,
        repo,
        privacy: AiInputPrivacy.personalImage,
      );

      await tester.tap(find.text('generate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow & Continue'));
      await tester.pumpAndSettle();

      expect(repo.grants, 1);
      expect(repo.stored.version, aiConsentVersion);
      expect(harness.results, [true]);
    });

    testWidgets('the second personal-photo request shows no sheet', (
      tester,
    ) async {
      final repo = _FakeConsentRepo(
        stored: const AiConsentState(
          granted: true,
          isCurrent: true,
          version: aiConsentVersion,
        ),
      );
      final harness = await _pumpGate(
        tester,
        repo,
        privacy: AiInputPrivacy.personalImage,
      );

      await tester.tap(find.text('generate'));
      await tester.pumpAndSettle();

      expect(find.text('AI Photo Processing'), findsNothing);
      expect(harness.results, [true]);
      expect(repo.grants, 0, reason: 'already granted — nothing to re-record');
    });

    testWidgets('a stale consent version asks exactly once more', (
      tester,
    ) async {
      // granted, but the server says it no longer satisfies the requirement.
      final repo = _FakeConsentRepo(
        stored: const AiConsentState(
          granted: true,
          isCurrent: false,
          version: aiConsentVersion - 1,
        ),
      );
      final harness = await _pumpGate(
        tester,
        repo,
        privacy: AiInputPrivacy.personalImage,
      );

      await tester.tap(find.text('generate'));
      await tester.pumpAndSettle();
      expect(find.text('AI Photo Processing'), findsOneWidget);

      await tester.tap(find.text('Allow & Continue'));
      await tester.pumpAndSettle();
      expect(harness.results, [true]);
      expect(repo.stored.version, aiConsentVersion);
    });

    testWidgets('2D never sees the sheet and never calls the consent API', (
      tester,
    ) async {
      final repo = _FakeConsentRepo();
      final harness = await _pumpGate(
        tester,
        repo,
        privacy: AiInputPrivacy.localOnly,
      );

      await tester.tap(find.text('generate'));
      await tester.pumpAndSettle();

      expect(find.text('AI Photo Processing'), findsNothing);
      expect(harness.results, [true]);
      expect(repo.reads, 0, reason: 'local work must not touch the network');
      expect(repo.grants, 0);
    });

    testWidgets('a studio model carries no personal photo, so no sheet', (
      tester,
    ) async {
      final repo = _FakeConsentRepo();
      final harness = await _pumpGate(
        tester,
        repo,
        privacy: AiInputPrivacy.nonPersonalProductImage,
      );

      await tester.tap(find.text('generate'));
      await tester.pumpAndSettle();

      expect(find.text('AI Photo Processing'), findsNothing);
      expect(harness.results, [true]);
      expect(repo.reads, 0);
    });

    testWidgets('an unreachable consent API asks rather than assumes', (
      tester,
    ) async {
      // Fail closed: not knowing must never become implied permission.
      final repo = _FakeConsentRepo(readThrows: true);
      await _pumpGate(tester, repo, privacy: AiInputPrivacy.personalImage);

      await tester.tap(find.text('generate'));
      await tester.pumpAndSettle();

      expect(find.text('AI Photo Processing'), findsOneWidget);
    });

    testWidgets('a failed consent WRITE stops the request', (tester) async {
      // The user allowed, but we could not record it. Proceeding would leave a
      // render with no record of the permission it ran under.
      final repo = _FakeConsentRepo(readThrows: true, grantThrows: true);
      final harness = await _pumpGate(
        tester,
        repo,
        privacy: AiInputPrivacy.personalImage,
      );

      await tester.tap(find.text('generate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow & Continue'));
      await tester.pumpAndSettle();

      expect(harness.results, [false]);
    });
  });

  group('body classification', () {
    const photo = TryonPhoto(
      id: 'p1',
      storagePath: 'avatars/u/p1.jpg',
      signedUrl: 'https://cdn.test/p1.png?token=secret-signature',
      isSelected: true,
    );
    const model = StudioModelPreset(
      id: 'm1',
      name: 'Studio A',
      imageUrl: 'https://cdn.test/model.png',
    );

    test('the user own photo is personal data', () {
      final body = resolveWtmBodyFrom(const WtmBodyPhoto(), const [photo]);
      expect(aiPrivacyOfBody(body), AiInputPrivacy.personalImage);
      expect(modelSourceOfBody(body), 'own_photo');
      expect(presetIdOfBody(body), isNull);
    });

    test('a studio model is ours, not theirs', () {
      final body = resolveWtmBodyFrom(const WtmBodyModel(model), const []);
      expect(aiPrivacyOfBody(body), AiInputPrivacy.nonPersonalProductImage);
      // The server re-resolves the preset and applies its own gating; telling it
      // the truth is what lets it make the privacy decision itself.
      expect(modelSourceOfBody(body), 'studio_model');
      expect(presetIdOfBody(body), 'm1');
    });

    test('the mannequin never leaves the device', () {
      final body = resolveWtmBodyFrom(const WtmBodyMannequin(), const []);
      expect(aiPrivacyOfBody(body), AiInputPrivacy.localOnly);
    });

    test('an empty gallery is not "a personal photo"', () {
      // No photo means nothing personal is in the request, so there is nothing
      // to ask permission for. The flow blocks earlier for want of a body.
      final body = resolveWtmBodyFrom(const WtmBodyPhoto(), const []);
      expect(aiPrivacyOfBody(body), AiInputPrivacy.localOnly);
    });
  });

  group('redactUrl', () {
    test('strips the presigned signature from a debug log line', () {
      final body = resolveWtmBodyFrom(const WtmBodyPhoto(), const [
        TryonPhoto(
          id: 'p1',
          storagePath: 'avatars/u/p1.jpg',
          signedUrl: 'https://cdn.test/u/p1.png?X-Amz-Signature=deadbeef',
          isSelected: true,
        ),
      ]);
      final line = describeWtmBody(body);
      // A signed body-photo URL in a device log is a working key to that photo
      // for as long as the signature lasts.
      expect(line, contains('cdn.test/u/p1.png'));
      expect(line, isNot(contains('deadbeef')));
      expect(line, isNot(contains('X-Amz-Signature')));
    });
  });
}
