import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Thin wrapper over the OS share sheet (`share_plus`). Keeps all share_plus
/// usage in one place so screens just call a method. Callers wrap in try/catch
/// and show a friendly message — sharing must never crash the app.
class ShareService {
  const ShareService();

  /// Share plain text (caption, link, look summary).
  Future<void> shareText(String text) => Share.share(text);

  /// Share an in-memory image (e.g. a 2D try-on composite), with optional text.
  /// share_plus writes the bytes to a temp file for the OS share sheet.
  Future<void> shareImageBytes(
    Uint8List bytes, {
    String? text,
    String name = 'wearthemood_look.jpg',
  }) {
    return Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'image/jpeg', name: name)],
      text: text,
    );
  }
}

final shareServiceProvider = Provider<ShareService>(
  (ref) => const ShareService(),
);
