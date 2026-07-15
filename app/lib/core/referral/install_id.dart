import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A stable, random per-INSTALLATION id (§24). Generated once and persisted in
/// the project's secure storage. It is attribution/anti-abuse data — NOT an
/// advertising id, device fingerprint, or anything PII — and the backend HMACs
/// it before storage. A reinstall yields a new id (acceptable: it's one
/// reasonable duplicate-install control, not perfect anti-fraud).
class InstallIdStore {
  InstallIdStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'wtm.referral.install_id';

  Future<String> getOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _randomUuidV4();
    await _storage.write(key: _key, value: id);
    return id;
  }

  static String _randomUuidV4() {
    final rng = Random.secure();
    final b = List<int>.generate(16, (_) => rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

final installIdStoreProvider = Provider<InstallIdStore>((ref) => InstallIdStore());
