import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../platform/platform_capabilities.dart';
import 'ai_disclosure_watermark.dart';

/// How the share sheet is invoked. Injected so a test can count calls and read
/// the bytes that were actually handed to the OS, which is the only way to
/// prove "no path exports an unwatermarked render".
typedef ShareFiles =
    Future<void> Function(List<XFile> files, {String? text});

Future<void> _defaultShare(List<XFile> files, {String? text}) =>
    Share.shareXFiles(files, text: text);

/// THE way a generated try-on render leaves the app.
///
/// Every result-screen share funnels through [shareResult] so the disclosure
/// rule has exactly one implementation. A second share call site that
/// "just needs to send some bytes" is how an unwatermarked copy escapes, so
/// there is deliberately no lower-level export here for one to reach for.
class TryOnShareService {
  TryOnShareService(this._platform, {ShareFiles? share})
    : _share = share ?? _defaultShare;

  final PlatformCapabilities _platform;
  final ShareFiles _share;

  /// True when this platform requires the burned-in AI disclosure.
  bool get watermarks => _platform.requiresWatermarkedShare;

  /// Shares a rendered try-on result.
  ///
  /// On iOS/iPadOS the exported file is a DERIVATIVE with the disclosure burned
  /// into its pixels. The privately stored original is never touched — it is
  /// not even opened for writing — because a share must not be able to damage
  /// the render it came from.
  ///
  /// Android is byte-for-byte unchanged: the same bytes, the same mime type,
  /// the same sheet.
  ///
  /// The derivative is written to the app's own temporary directory and
  /// deleted after the sheet returns. It is written to disk rather than passed
  /// in memory so the receiving app gets a real file with a real name, which
  /// is what makes the share reliable across Messages, Mail and Photos.
  Future<void> shareResult(
    Uint8List bytes, {
    required String text,
    required String watermarkLabel,
    required String watermarkAiTag,
    String name = 'wear-the-mood-look',
  }) async {
    if (!watermarks) {
      await _share([
        XFile.fromData(bytes, mimeType: 'image/png', name: '$name.png'),
      ], text: text);
      return;
    }

    final stamped = await burnAiDisclosure(
      bytes,
      label: watermarkLabel,
      aiTag: watermarkAiTag,
    );

    File? temp;
    try {
      final dir = await getTemporaryDirectory();
      temp = File(
        '${dir.path}/${name}_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await temp.writeAsBytes(stamped, flush: true);
      await _share([
        XFile(temp.path, mimeType: 'image/png', name: '$name.png'),
      ], text: text);
    } finally {
      // Best-effort, and deliberately AFTER the sheet has returned: deleting
      // while the receiving app is still reading is how a share arrives empty.
      final file = temp;
      if (file != null) {
        try {
          if (file.existsSync()) await file.delete();
        } catch (_) {
          /* the OS clears its own temp directory */
        }
      }
    }
  }
}

final tryOnShareServiceProvider = Provider<TryOnShareService>(
  (ref) => TryOnShareService(ref.watch(platformCapabilitiesProvider)),
);
