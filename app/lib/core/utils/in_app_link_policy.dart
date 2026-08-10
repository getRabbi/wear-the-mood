import 'package:flutter/foundation.dart';

import '../referral/app_link_channel.dart';
import '../router/routes.dart';
import 'link_launcher.dart';

/// What the in-app article viewer must do with one navigation request.
enum InAppLinkAction {
  /// Load it in the same in-app WebView — the reader never leaves the app.
  loadInApp,

  /// Hand it to `go_router`: it is a Wear The Mood destination, and the native
  /// screen is always better than our own site rendered in a WebView.
  routeInApp,

  /// Refuse. The caller stays where it is and says so.
  block,
}

/// The verdict for one URL, plus the in-app route when there is one.
@immutable
class InAppLinkDecision {
  const InAppLinkDecision(this.action, {this.route});

  final InAppLinkAction action;

  /// The `go_router` path for [InAppLinkAction.routeInApp]; null otherwise.
  final String? route;

  @override
  bool operator ==(Object other) =>
      other is InAppLinkDecision &&
      other.action == action &&
      other.route == route;

  @override
  int get hashCode => Object.hash(action, route);

  @override
  String toString() => 'InAppLinkDecision(${action.name}, route: $route)';
}

/// The single policy the in-app article viewer applies to EVERY navigation —
/// the first load, a tap inside the page, and any redirect the page performs.
///
/// It deliberately delegates the safety question to [LinkLauncher.isSafe] rather
/// than re-deriving it. That predicate is already the audited gate for every
/// outbound link in the app (https only, host required, no userinfo), it is
/// covered by its own tests, and having a WebView answer the same question a
/// second way is how the two answers drift apart.
///
/// Consequences worth stating plainly, because they are all deliberate:
///
///   * `javascript:`, `file:`, `intent:`, `data:`, `tel:`, `mailto:` and every
///     vendor scheme are blocked — none of them are https.
///   * plain `http:` is blocked too. A syndicated feed link in the clear is a
///     downgrade we do not perform on the user's behalf, and the existing
///     launcher has refused it since it was written.
///   * `https://real.shop@evil.test/` is blocked on the userinfo rule, because
///     it reads as the publisher and resolves to the attacker.
///
/// Nothing here bypasses TLS. Certificate failures are the platform WebView's
/// business and its default — cancel the load — is what we want; the viewer
/// deliberately installs no certificate-error handler.
InAppLinkDecision decideInAppLink(String url) {
  // A Wear The Mood link wins before the generic rules: an invite opened inside
  // an article should land on the real referral screen, not on our marketing
  // page inside a WebView. Reuses the same extractor the native App Link
  // handler uses, so the two can never disagree about what a WTM link is.
  if (referralCodeFromLink(url) != null) {
    return const InAppLinkDecision(
      InAppLinkAction.routeInApp,
      route: AppRoute.wtmReferral,
    );
  }
  if (!LinkLauncher.isSafe(url)) {
    return const InAppLinkDecision(InAppLinkAction.block);
  }
  return const InAppLinkDecision(InAppLinkAction.loadInApp);
}

/// A short, non-identifying label for the article's publisher: the host with a
/// leading `www.` removed. Used as the reader's subtitle so the user can always
/// see whose page they are on — which is the honest replacement for the browser
/// address bar we are deliberately not showing.
///
/// Returns null when [url] is not something we would ever load.
String? displayDomain(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}
