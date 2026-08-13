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
  const InAppLinkDecision(this.action, {this.route, this.url});

  final InAppLinkAction action;

  /// The `go_router` path for [InAppLinkAction.routeInApp]; null otherwise.
  final String? route;

  /// The URL to actually load for [InAppLinkAction.loadInApp] — NORMALIZED, so
  /// it is not always the string that came in (see [normalizeArticleUrl]). Null
  /// for every other action.
  ///
  /// Callers must load THIS rather than their own input: loading the raw string
  /// would re-open the cleartext page the normalization exists to avoid, and
  /// would hand `Uri.parse` an untrimmed value that the check already rejected.
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is InAppLinkDecision &&
      other.action == action &&
      other.route == route &&
      other.url == url;

  @override
  int get hashCode => Object.hash(action, route, url);

  @override
  String toString() =>
      'InAppLinkDecision(${action.name}, route: $route, url: $url)';
}

/// The URL the in-app reader should load for [raw], or null when there is not
/// one worth trying.
///
/// Two operations, both deliberately conservative:
///
///   * **Trim.** A syndicated feed hands out URLs with stray whitespace, and
///     `Uri.parse` on an untrimmed string produces something that is not the
///     link the publisher meant.
///   * **Upgrade `http:` to `https:`.** This is the one rewrite performed, and
///     it only ever moves in the safe direction. Refusing a cleartext article
///     outright is what the reader used to do, and it reads to the user as
///     "this story is broken" for a link that is perfectly good over TLS; a
///     DOWNGRADE is never performed, and if the host genuinely has no https the
///     load fails and the reader offers Retry rather than quietly falling back.
///
/// Everything else is left exactly as the publisher wrote it — query,
/// fragment, port and case are load-bearing for paywalls and deep links, and
/// this is not the place to normalize identity (that is the backend's
/// `canonical_url`, which is a different question with a different answer).
String? normalizeArticleUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.isScheme('https')) return uri.toString();
  if (uri.isScheme('http')) return uri.replace(scheme: 'https').toString();
  return null;
}

/// Whether refusing [url] is worth putting a message on screen for.
///
/// A publisher page performs a constant stream of navigations the reader will
/// never follow — `javascript:void(0)` on every decorative anchor, `about:blank`
/// for a JS-opened window, `blob:`/`data:` for inline assets. Those are page
/// mechanics, not a user asking to go somewhere, and announcing each one is
/// what put "That link isn't safe to open." on screen while somebody was
/// reading an article that had loaded perfectly.
///
/// True only for a refusal a person could plausibly have asked for: a named
/// scheme with a real host — an app deep link, a store link, a bare `ftp:`.
bool isNotifiableBlock(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return false;
  const mechanics = {'about', 'blob', 'data', 'javascript', ''};
  return !mechanics.contains(uri.scheme.toLowerCase());
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
///   * plain `http:` is UPGRADED to https rather than blocked, and the upgraded
///     URL is what the caller loads. Nothing cleartext is ever fetched; see
///     [normalizeArticleUrl] for why refusing outright was the wrong answer.
///   * `https://real.shop@evil.test/` is blocked on the userinfo rule, because
///     it reads as the publisher and resolves to the attacker.
///
/// Nothing here bypasses TLS. Certificate failures are the platform WebView's
/// business and its default — cancel the load — is what we want; the viewer
/// deliberately installs no certificate-error handler.
InAppLinkDecision decideInAppLink(String url) {
  // Normalize FIRST, so every rule below judges the URL that would actually be
  // used. Doing the referral check on the raw string meant a cleartext invite
  // — `http://wearthemood.com/r/CODE` — was not recognised as ours and got
  // rendered as a web page instead of opening the referral screen. Upgrading it
  // first grants nothing an attacker did not already have (they could write the
  // https form just as easily) and gets the user to the native screen.
  final normalized = normalizeArticleUrl(url);
  if (normalized == null) {
    return const InAppLinkDecision(InAppLinkAction.block);
  }

  // A Wear The Mood link wins over the generic rules: an invite opened inside
  // an article should land on the real referral screen, not on our marketing
  // page inside a WebView. Reuses the same extractor the native App Link
  // handler uses, so the two can never disagree about what a WTM link is.
  if (referralCodeFromLink(normalized) != null) {
    return const InAppLinkDecision(
      InAppLinkAction.routeInApp,
      route: AppRoute.wtmReferral,
    );
  }

  // `isSafe` is still the gate, and it is applied to what would ACTUALLY be
  // loaded rather than to the raw string — otherwise the upgrade would be a
  // hole rather than a fix.
  if (!LinkLauncher.isSafe(normalized)) {
    return const InAppLinkDecision(InAppLinkAction.block);
  }
  return InAppLinkDecision(InAppLinkAction.loadInApp, url: normalized);
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
