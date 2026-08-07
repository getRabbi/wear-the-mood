import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens external links — legal pages, news articles, affiliate destinations.
/// Behind a provider so screens stay testable: fakes record the opened URL
/// without a platform.
class LinkLauncher {
  const LinkLauncher();

  /// Whether [url] is safe to hand to the platform.
  ///
  /// **https only.** Every outbound link the app opens comes from somewhere it
  /// does not control — a syndicated news feed, a merchant's affiliate URL, a
  /// row in the offers table — and `launchUrl` will happily dispatch
  /// `intent:`, `file:`, `tel:` or a vendor scheme to whatever app claims it.
  /// A plain http link is refused too: an affiliate hop in the clear is a
  /// tracking token on the wire.
  ///
  /// Userinfo is rejected as well, because `https://real.shop@evil.test/` reads
  /// as the merchant in a preview and resolves to the attacker.
  static bool isSafe(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    if (!uri.isScheme('https')) return false;
    if (uri.host.isEmpty) return false;
    if (uri.userInfo.isNotEmpty) return false;
    return true;
  }

  /// Opens [url] in the external browser. Returns false when it is not safe to
  /// open or the platform could not launch it — callers stay where they are and
  /// say so, rather than appearing to have done something.
  Future<bool> open(String url) async {
    if (!isSafe(url)) return false;
    try {
      return await launchUrl(
        Uri.parse(url.trim()),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}

final linkLauncherProvider = Provider<LinkLauncher>(
  (ref) => const LinkLauncher(),
);
