import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/push/push_messaging.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/notifications/wtm_notification_explainer.dart';

/// "Enable Notifications" must be idempotent against the OS, not against a
/// device flag.
///
/// Reproduced on a physical iPhone: enable notifications, use the app, sign
/// out, sign back into the SAME account — and the explainer is back. It gated
/// solely on a secure-storage "seen" marker, so the marker was the only thing
/// standing between an already-subscribed user and being asked again, and a
/// marker is device state that can go missing (a reinstall, a keychain that
/// answers late, a write that failed and was swallowed).
///
/// A new authentication session is not "notification permission not
/// configured". The OS knows the answer; ask it.
class _FakePush extends PushMessaging {
  _FakePush(super.ref, this._status);

  final PushPermissionStatus _status;
  int prompts = 0;
  int statusReads = 0;

  @override
  Future<PushPermissionStatus> permissionStatus() async {
    statusReads++;
    return _status;
  }

  @override
  Future<void> promptPermission() async => prompts++;
}

/// In-memory keychain. `write` can be made to fail, because a swallowed write
/// failure is one of the ways the marker goes missing in the first place.
class _MemoryStorage implements FlutterSecureStorage {
  _MemoryStorage({this.writesFail = false});

  final Map<String, String> store = {};
  final bool writesFail;

  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async => store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (writesFail) throw StateError('keychain unavailable');
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

const _seenKey = 'wtm.notif.explainer_seen';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Runs one `maybeShow` against a given OS state and returns what happened.
  Future<(_FakePush, _MemoryStorage, bool shown)> run(
    WidgetTester tester,
    PushPermissionStatus status, {
    _MemoryStorage? storage,
    bool tapEnable = false,
  }) async {
    final store = storage ?? _MemoryStorage();
    late _FakePush push;
    final container = ProviderContainer(
      overrides: [
        pushMessagingProvider.overrideWith(
          (ref) => push = _FakePush(ref, status),
        ),
        notificationExplainerStorageProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    // Materialise the push fake before the explainer reads it.
    container.read(pushMessagingProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              // A frame later, exactly as Home schedules it.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                container
                    .read(notificationExplainerProvider)
                    .maybeShow(context);
              });
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shown = find.text('Enable notifications').evaluate().isNotEmpty;
    if (shown && tapEnable) {
      await tester.tap(find.text('Enable notifications'));
      await tester.pumpAndSettle();
    } else if (shown) {
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
    }
    return (push, store, shown);
  }

  testWidgets('never asked → the explainer is shown', (tester) async {
    final (push, store, shown) = await run(
      tester,
      PushPermissionStatus.notDetermined,
      tapEnable: true,
    );

    expect(shown, isTrue);
    expect(push.prompts, 1, reason: 'Enable triggers the real OS prompt');
    expect(store.store[_seenKey], 'true');
  });

  testWidgets('already granted → never asked again', (tester) async {
    // The reported bug: signing out and back in is not a reason to re-ask
    // somebody who already said yes.
    final (push, store, shown) = await run(
      tester,
      PushPermissionStatus.granted,
    );

    expect(shown, isFalse);
    expect(push.prompts, 0);
    expect(push.statusReads, 1, reason: 'the OS is consulted, not just a flag');
    expect(
      store.store[_seenKey],
      'true',
      reason:
          'recorded, so a device that later loses the OS answer does not '
          'treat the silence as a fresh install',
    );
  });

  testWidgets('granted with a MISSING marker → still never asked', (
    tester,
  ) async {
    // The heart of it. Even with the device flag gone — reinstall, keychain
    // miss, a write that failed — an authorized user is not asked again.
    final store = _MemoryStorage();
    expect(store.store[_seenKey], isNull);

    final (push, _, shown) = await run(
      tester,
      PushPermissionStatus.granted,
      storage: store,
    );

    expect(shown, isFalse);
    expect(push.prompts, 0);
  });

  testWidgets('denied → no misleading request that cannot succeed', (
    tester,
  ) async {
    // A denied OS toggle cannot be flipped from in-app. The honest place for it
    // is the preferences screen's Open Settings action, so this stays quiet
    // rather than presenting a request that is guaranteed to do nothing.
    final (push, store, shown) = await run(tester, PushPermissionStatus.denied);

    expect(shown, isFalse);
    expect(push.prompts, 0);
    expect(store.store[_seenKey], 'true');
  });

  testWidgets('Not now on a fresh device is respected next time', (
    tester,
  ) async {
    final store = _MemoryStorage();
    final (_, _, first) = await run(
      tester,
      PushPermissionStatus.notDetermined,
      storage: store,
    );
    expect(first, isTrue);
    expect(store.store[_seenKey], 'true');

    // A second session on the same device, still un-prompted at the OS level.
    final (push, _, second) = await run(
      tester,
      PushPermissionStatus.notDetermined,
      storage: store,
    );
    expect(second, isFalse, reason: 'Not now is an answer, not a deferral');
    expect(push.prompts, 0);
  });

  testWidgets('a keychain that cannot write never breaks the launch', (
    tester,
  ) async {
    final store = _MemoryStorage(writesFail: true);
    final (_, _, shown) = await run(
      tester,
      PushPermissionStatus.notDetermined,
      storage: store,
    );

    // Best-effort: it still shows, and the failure is swallowed rather than
    // taking Home down over a persistence detail.
    expect(shown, isTrue);
  });

  testWidgets('Firebase absent → treated as unknown, not as "never asked"', (
    tester,
  ) async {
    // `unavailable` means we cannot tell. The explainer still runs its marker
    // check, so a device that has already answered is not re-asked.
    final store = _MemoryStorage()..store[_seenKey] = 'true';
    final (push, _, shown) = await run(
      tester,
      PushPermissionStatus.unavailable,
      storage: store,
    );

    expect(shown, isFalse);
    expect(push.prompts, 0);
  });
}
