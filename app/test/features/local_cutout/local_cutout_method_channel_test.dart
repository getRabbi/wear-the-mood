import 'package:app/features/wardrobe/local_cutout/local_cutout_method_channel.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_models.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `wtm/background_removal` channel wrapper (local BG §11.2, §11.3).
///
/// Driven through Flutter's real channel plumbing with a scripted native side, so
/// codec behaviour and error mapping are exercised rather than mocked away.
///
/// The property that matters most: NOTHING here throws anything other than a
/// typed [LocalCutoutPlatformException]. An engine-less build, a hostile reply, a
/// native code this build has never heard of — all must degrade to a fallback
/// reason so Add Garment quietly uses the cloud path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kLocalCutoutChannel);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];
  late MethodChannelLocalCutoutPlatform platform;

  void handle(Future<Object?>? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  Map<Object?, Object?> resultMap({
    String engine = 'google_mlkit',
    Object? operationId = 'a1b2c3',
    Object? mask = '/cache/wtm-local-cutout/a1b2c3/mask.png',
  }) => <Object?, Object?>{
    'engine': engine,
    'engineVersion': '16.0.0-beta1',
    'operationId': operationId,
    'maskFilePath': mask,
    'cutoutFilePath': '/cache/wtm-local-cutout/a1b2c3/cutout.png',
    'latencyMs': 1234,
    'metrics': <Object?, Object?>{
      'width': 1600,
      'height': 1200,
      'subjectCount': 1,
      'foregroundAreaRatio': 0.42,
      'borderForegroundRatio': 0.03,
      'uncertainPixelRatio': 0.11,
      'meanForegroundConfidence': 0.88,
      'foregroundBounds': <Object?, Object?>{
        'left': 10.0,
        'top': 20.0,
        'right': 900.0,
        'bottom': 1000.0,
      },
    },
  };

  setUp(() {
    calls.clear();
    platform = MethodChannelLocalCutoutPlatform(channel: channel);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<LocalCutoutFallbackReason?> reasonOf(Future<Object?> future) async {
    try {
      await future;
      return null;
    } on LocalCutoutPlatformException catch (e) {
      return e.reason;
    }
  }

  group('capability', () {
    test('decodes an available engine', () async {
      handle((_) async => <Object?, Object?>{
        'availability': 'available',
        'engine': 'google_mlkit',
        'engineVersion': '16.0.0-beta1',
      });

      final capability = await platform.capability();

      expect(capability.isAvailable, isTrue);
      expect(capability.engine, LocalCutoutEngine.googleMlKit);
      expect(calls.single.method, LocalCutoutMethod.capability);
    });

    test('a missing plugin is channelUnavailable, never a crash', () async {
      // Exactly what an engine-less build (or iOS before Phase 4) produces.
      handle((_) => throw MissingPluginException('no impl'));

      expect(
        await reasonOf(platform.capability()),
        LocalCutoutFallbackReason.channelUnavailable,
      );
    });

    test('an unrecognised availability is treated as transient', () async {
      handle((_) async => <Object?, Object?>{'availability': 'something_new'});

      final capability = await platform.capability();
      expect(capability.availability, LocalCutoutAvailability.temporarilyUnavailable);
      expect(capability.isAvailable, isFalse);
    });

    test('a null reply is unsupported rather than an error', () async {
      handle((_) async => null);
      expect((await platform.capability()).isAvailable, isFalse);
    });
  });

  group('prepare', () {
    test('forwards the timeout and asks for a DEFERRED install', () async {
      // Urgent installs block on a download; app start must never do that.
      handle((_) async => <Object?, Object?>{'availability': 'model_not_installed'});

      await platform.prepare(timeout: const Duration(seconds: 12));

      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(calls.single.method, LocalCutoutMethod.prepare);
      expect(args['timeoutMs'], 12000);
      expect(args['urgent'], isFalse);
    });

    test('maps a download failure through', () async {
      handle((_) async => <Object?, Object?>{'availability': 'model_download_failed'});

      final capability = await platform.prepare(timeout: const Duration(seconds: 5));
      expect(capability.availability, LocalCutoutAvailability.modelDownloadFailed);
    });
  });

  group('removeBackground', () {
    test('sends the exact bytes and decodes the result', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      handle((_) async => resultMap());

      final result = await platform.removeBackground(
        imageBytes: bytes,
        timeout: const Duration(seconds: 20),
      );

      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['imageBytes'], bytes);
      expect(args['timeoutMs'], 20000);
      expect(result.engine, LocalCutoutEngine.googleMlKit);
      expect(result.operationId, 'a1b2c3');
      expect(result.metrics.width, 1600);
      expect(result.latency, const Duration(milliseconds: 1234));
    });

    test('every native error code maps to its reason', () async {
      const cases = {
        LocalCutoutErrorCode.unsupported: LocalCutoutFallbackReason.unsupportedOs,
        LocalCutoutErrorCode.missingPlayServices:
            LocalCutoutFallbackReason.missingGooglePlayServices,
        LocalCutoutErrorCode.modelNotInstalled:
            LocalCutoutFallbackReason.modelNotInstalled,
        LocalCutoutErrorCode.modelDownloadFailed:
            LocalCutoutFallbackReason.modelDownloadFailed,
        LocalCutoutErrorCode.noSubject: LocalCutoutFallbackReason.noSubjectFound,
        LocalCutoutErrorCode.invalidOutput: LocalCutoutFallbackReason.invalidOutput,
        LocalCutoutErrorCode.timeout: LocalCutoutFallbackReason.timeout,
        LocalCutoutErrorCode.cancelled: LocalCutoutFallbackReason.cancelled,
        LocalCutoutErrorCode.busy: LocalCutoutFallbackReason.temporarilyUnavailable,
        LocalCutoutErrorCode.cacheUnavailable:
            LocalCutoutFallbackReason.temporarilyUnavailable,
        LocalCutoutErrorCode.internal: LocalCutoutFallbackReason.nativeError,
      };

      for (final entry in cases.entries) {
        handle((_) => throw PlatformException(code: entry.key));
        final reason = await reasonOf(
          platform.removeBackground(
            imageBytes: Uint8List(4),
            timeout: const Duration(seconds: 5),
          ),
        );
        expect(reason, entry.value, reason: entry.key);
      }
    });

    test('a code this build has never seen is a generic native error', () async {
      handle((_) => throw PlatformException(code: 'invented_in_a_later_release'));

      expect(
        await reasonOf(
          platform.removeBackground(
            imageBytes: Uint8List(4),
            timeout: const Duration(seconds: 5),
          ),
        ),
        LocalCutoutFallbackReason.nativeError,
      );
    });

    test('a null reply is invalidOutput, never a fake success', () async {
      handle((_) async => null);

      expect(
        await reasonOf(
          platform.removeBackground(
            imageBytes: Uint8List(4),
            timeout: const Duration(seconds: 5),
          ),
        ),
        LocalCutoutFallbackReason.invalidOutput,
      );
    });

    test('a reply missing required fields is invalidOutput', () async {
      for (final broken in [
        resultMap(operationId: null),
        resultMap(mask: ''),
        resultMap(engine: 'some_other_engine'),
        <Object?, Object?>{'engine': 'google_mlkit'},
      ]) {
        handle((_) async => broken);
        expect(
          await reasonOf(
            platform.removeBackground(
              imageBytes: Uint8List(4),
              timeout: const Duration(seconds: 5),
            ),
          ),
          LocalCutoutFallbackReason.invalidOutput,
        );
      }
    });

    test('a hung native side times out with a typed reason', () async {
      handle((_) => Future<Object?>.delayed(const Duration(seconds: 30)));

      expect(
        await reasonOf(
          platform.removeBackground(
            imageBytes: Uint8List(4),
            // Total wait = timeout + the wrapper's grace, so keep it tiny here.
            timeout: Duration.zero,
          ),
        ),
        LocalCutoutFallbackReason.timeout,
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a missing plugin degrades to channelUnavailable', () async {
      handle((_) => throw MissingPluginException('no impl'));

      expect(
        await reasonOf(
          platform.removeBackground(
            imageBytes: Uint8List(4),
            timeout: const Duration(seconds: 5),
          ),
        ),
        LocalCutoutFallbackReason.channelUnavailable,
      );
    });
  });

  group('cleanup and cancel are id-based and never throw', () {
    test('cleanup sends the operation ID, not a path', () async {
      handle((_) async => null);

      await platform.cleanup('a1b2c3');

      expect(calls.single.method, LocalCutoutMethod.cleanup);
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['operationId'], 'a1b2c3');
      // There is no path-shaped argument in the contract at all (R10b).
      expect(args.keys, ['operationId']);
    });

    test('cleanup swallows a native failure', () async {
      handle((_) => throw PlatformException(code: 'internal'));
      await platform.cleanup('a1b2c3'); // must not throw
    });

    test('cancel forwards the id and swallows failures', () async {
      handle((_) => throw PlatformException(code: 'internal'));
      await platform.cancel('a1b2c3');
      expect(calls.single.method, LocalCutoutMethod.cancel);
    });
  });

  group('sweepCache', () {
    test('returns the count the native side swept', () async {
      handle((_) async => 4);
      expect(await platform.sweepCache(maxAge: const Duration(hours: 3)), 4);

      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['maxAgeMs'], const Duration(hours: 3).inMilliseconds);
    });

    test('a failure or null sweeps zero rather than throwing', () async {
      handle((_) => throw PlatformException(code: 'internal'));
      expect(await platform.sweepCache(maxAge: const Duration(hours: 1)), 0);

      handle((_) async => null);
      expect(await platform.sweepCache(maxAge: const Duration(hours: 1)), 0);
    });
  });
}
