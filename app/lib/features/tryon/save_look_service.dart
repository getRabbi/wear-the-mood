import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../collections/local_collections.dart';
import '../social/post_image_service.dart';

/// Persists a try-on result as a saved [SavedLook] with a **durable**,
/// publicly-readable image URL (§8): the bytes are uploaded to durable storage
/// first, then a local record is added so the look appears in Looks across
/// restarts. The save is **idempotent** on its id (§9) — re-saving the same
/// result is a no-op that still succeeds — and it **throws on failure** so the
/// UI can surface a real error instead of a silent no-op.
class SaveLookService {
  SaveLookService(this._ref);

  final Ref _ref;

  /// Save from raw image bytes (the free 2D editor result is in-memory).
  Future<void> saveBytes({
    required String id,
    required Uint8List bytes,
  }) async {
    final store = _ref.read(savedLookRecordsProvider.notifier);
    if (store.contains(id)) return; // already saved — idempotent
    final url = await _ref.read(postImageServiceProvider).upload(bytes);
    store.add(SavedLook(id: id, imageUrl: url, createdAt: DateTime.now()));
  }

  /// Save from a (possibly short-lived, signed) result URL (the AI try-on
  /// result): download the bytes, then re-upload to durable storage before
  /// recording — never store the expiring URL itself (§8).
  Future<void> saveFromUrl({required String id, required String url}) async {
    final store = _ref.read(savedLookRecordsProvider.notifier);
    if (store.contains(id)) return; // already saved — idempotent
    final service = _ref.read(postImageServiceProvider);
    final bytes = await service.downloadImageBytes(url);
    final durable = await service.upload(bytes);
    store.add(SavedLook(id: id, imageUrl: durable, createdAt: DateTime.now()));
  }
}

final saveLookServiceProvider = Provider<SaveLookService>(
  (ref) => SaveLookService(ref),
);
