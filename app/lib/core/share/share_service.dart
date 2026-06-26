import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'watermark.dart';

/// Thin wrapper over the OS share sheet (`share_plus`). Keeps all share_plus
/// usage in one place so screens just call a method. Callers wrap in try/catch
/// and show a friendly message — sharing must never crash the app.
class ShareService {
  const ShareService();

  /// Share plain text (caption, invite/offer link, look summary).
  Future<void> shareText(String text) => Share.share(text);

  /// Share an in-memory image (e.g. a try-on result), with optional text. When
  /// [watermark] is true the brand badge is composited first (free / standard
  /// looks); HD/premium passes false so its shares stay clean (the paywall
  /// promise). share_plus writes the bytes to a temp file for the OS share sheet.
  Future<void> shareImageBytes(
    Uint8List bytes, {
    String? text,
    bool watermark = false,
    String name = 'wearthemood_look.png',
  }) async {
    final out = watermark ? await addWatermark(bytes) : bytes;
    // A watermarked image is PNG (the compositor's output); otherwise pass the
    // original bytes through as JPEG (try-on results are JPEG).
    final mime = watermark ? 'image/png' : 'image/jpeg';
    final fileName = watermark ? name : name.replaceAll('.png', '.jpg');
    await Share.shareXFiles(
      [XFile.fromData(out, mimeType: mime, name: fileName)],
      text: text,
    );
  }
}

final shareServiceProvider = Provider<ShareService>(
  (ref) => const ShareService(),
);
