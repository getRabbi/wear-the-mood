import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens external links (legal pages, affiliate links later). Behind a provider
/// so screens stay testable — fakes record the opened URL without a platform.
class LinkLauncher {
  const LinkLauncher();

  /// Opens [url] in the external browser. Returns false if it couldn't launch.
  Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

final linkLauncherProvider = Provider<LinkLauncher>(
  (ref) => const LinkLauncher(),
);
