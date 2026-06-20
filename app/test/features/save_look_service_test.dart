import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/features/collections/local_collections.dart';
import 'package:app/features/social/post_image_service.dart';
import 'package:app/features/tryon/save_look_service.dart';

/// Fake upload/download so the test never touches Supabase storage or the
/// network — it just records how many uploads/downloads happened and hands back
/// a "durable" URL.
class _FakePostImageService extends PostImageService {
  _FakePostImageService()
    : super(SupabaseClient('https://stub.supabase.co', 'stub-anon-key'));

  int uploads = 0;
  int downloads = 0;

  @override
  Future<String> upload(Uint8List bytes) async {
    uploads++;
    return 'https://cdn.example/durable_$uploads.jpg';
  }

  @override
  Future<Uint8List> downloadImageBytes(String url) async {
    downloads++;
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    // No-op the encrypted store so saved-look persistence stays in memory.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  test('saveBytes uploads a durable URL, records the look, and is idempotent',
      () async {
    final fake = _FakePostImageService();
    final container = ProviderContainer(
      overrides: [postImageServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container
        .read(saveLookServiceProvider)
        .saveBytes(id: 'look-1', bytes: Uint8List.fromList([9]));

    final looks = container.read(savedLookRecordsProvider);
    expect(looks, hasLength(1));
    expect(looks.first.id, 'look-1');
    expect(looks.first.imageUrl, contains('durable'));
    expect(fake.uploads, 1);

    // Re-saving the same id is a no-op (§9): no duplicate record, no re-upload.
    await container
        .read(saveLookServiceProvider)
        .saveBytes(id: 'look-1', bytes: Uint8List.fromList([9]));
    expect(container.read(savedLookRecordsProvider), hasLength(1));
    expect(fake.uploads, 1);
  });

  test('saveFromUrl re-uploads to a durable URL (never stores the signed one)',
      () async {
    final fake = _FakePostImageService();
    final container = ProviderContainer(
      overrides: [postImageServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(saveLookServiceProvider).saveFromUrl(
          id: 'job-7',
          url: 'https://signed.example/expiring?token=abc',
        );

    final looks = container.read(savedLookRecordsProvider);
    expect(looks, hasLength(1));
    expect(looks.first.imageUrl, contains('durable'));
    expect(looks.first.imageUrl, isNot(contains('signed')));
    expect(fake.downloads, 1);
    expect(fake.uploads, 1);
  });
}
