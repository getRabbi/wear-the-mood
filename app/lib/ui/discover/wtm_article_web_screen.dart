import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/utils/in_app_link_policy.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// What the reader needs to open one article. Passed as go_router `extra` — the
/// route is only ever reached from the article screen, never from a push payload
/// or a cold deep link, so there is nothing to reconstruct from a URL.
@immutable
class WtmArticleWebArgs {
  const WtmArticleWebArgs({required this.url, this.title, this.source});

  final String url;
  final String? title;
  final String? source;
}

/// Builds the controller for [WtmArticleWebScreen].
///
/// Behind a provider for one reason: `WebViewController` needs a registered
/// platform implementation, which a widget test does not have. Tests override
/// this to return null and get the reader's chrome + unavailable state instead
/// of a platform exception, so the app bar, back behaviour and error copy stay
/// testable without a real browser engine.
typedef WebViewControllerBuilder = WebViewController? Function();

final webViewControllerBuilderProvider = Provider<WebViewControllerBuilder>((
  ref,
) {
  return () {
    try {
      return WebViewController();
    } catch (_) {
      // No platform implementation (unit test, unsupported host). The screen
      // shows its unavailable state rather than crashing the route.
      return null;
    }
  };
});

/// The in-app article reader (§1 pillar 5).
///
/// Newsroom stores a summary and a link, never the publisher's body text
/// (migration `0058`), so "read the whole thing" has to be the publisher's own
/// page. It renders HERE, inside Wear The Mood, instead of handing the user to
/// Chrome or Safari — the app never loses them mid-session.
///
/// Every navigation, including the first load and anything the page redirects
/// to, goes through [decideInAppLink]. Nothing about TLS is overridden.
class WtmArticleWebScreen extends ConsumerStatefulWidget {
  const WtmArticleWebScreen({super.key, required this.args});

  final WtmArticleWebArgs args;

  @override
  ConsumerState<WtmArticleWebScreen> createState() =>
      _WtmArticleWebScreenState();
}

class _WtmArticleWebScreenState extends ConsumerState<WtmArticleWebScreen> {
  WebViewController? _controller;

  /// 0–100 while the page loads; null once it has settled.
  int? _progress;
  bool _failed = false;

  /// The URL actually on screen — the app bar subtitle follows redirects rather
  /// than claiming the domain we started from.
  late String _currentUrl = widget.args.url;

  @override
  void initState() {
    super.initState();
    // Refuse an unsafe URL before a controller exists: an article link comes
    // from a syndicated feed, and the reader is not a place to relax the rule.
    if (decideInAppLink(widget.args.url).action != InAppLinkAction.loadInApp) {
      _failed = true;
      return;
    }
    _controller = ref.read(webViewControllerBuilderProvider)();
    final controller = _controller;
    if (controller == null) {
      _failed = true;
      return;
    }
    // Publisher pages are script-driven; without this most render blank. No
    // JavaScript CHANNEL is registered, so the page has no bridge into the app.
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(WtmColors.bg)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _currentUrl = url;
              _failed = false;
              _progress = 0;
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _currentUrl = url;
              _progress = null;
            });
          },
          onWebResourceError: (error) {
            // Sub-resources fail constantly on news pages (ad slots, trackers,
            // fonts). Only a MAIN-FRAME failure means the reader has nothing to
            // show, and only that earns the error state.
            if (error.isForMainFrame != true) return;
            if (mounted) setState(() => _failed = true);
          },
          onNavigationRequest: _decide,
        ),
      )
      ..loadRequest(Uri.parse(widget.args.url));
  }

  /// The one gate every navigation passes through.
  NavigationDecision _decide(NavigationRequest request) {
    final decision = decideInAppLink(request.url);
    switch (decision.action) {
      case InAppLinkAction.loadInApp:
        return NavigationDecision.navigate;
      case InAppLinkAction.routeInApp:
        // Leave the WebView where it is and move the APP instead.
        final route = decision.route;
        if (route != null && mounted) {
          // Scheduled rather than immediate: we are inside the platform's
          // navigation callback, and pushing a route from there can reenter it.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.push(route);
          });
        }
        return NavigationDecision.prevent;
      case InAppLinkAction.block:
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              wtmSnack(
                context,
                AppLocalizations.of(context).wtmArticleLinkBlocked,
              );
            }
          });
        }
        return NavigationDecision.prevent;
    }
  }

  /// System back / the reader's own back: walk the article's history first, and
  /// only leave the reader once there is nothing behind it. The user can never
  /// exit the app from here by accident — this route is always pushed on top of
  /// Newsroom, which keeps its scroll position underneath.
  Future<void> _back() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return;
    }
    if (mounted) wtmPageBack(context);
  }

  void _retry() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _failed = false;
      _progress = 0;
    });
    controller.loadRequest(Uri.parse(_currentUrl));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    final domain = displayDomain(_currentUrl) ?? l10n.wtmArticleEyebrow;

    return PopScope(
      // Never pop straight out: _back decides whether this gesture belongs to
      // the article's history or to the route.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: WtmScaffold(
        body: SafeArea(
          child: Column(
            children: [
              _ReaderHead(
                title: widget.args.title ?? widget.args.source ?? domain,
                domain: domain,
                onBack: _back,
              ),
              // A 2px determinate line, not a blocking spinner: the page paints
              // behind it as it arrives.
              SizedBox(
                height: 2,
                child: _progress == null
                    ? null
                    : LinearProgressIndicator(
                        value: (_progress! / 100).clamp(0.0, 1.0),
                        minHeight: 2,
                        backgroundColor: WtmColors.lineSoft,
                        valueColor: const AlwaysStoppedAnimation(
                          WtmColors.gold,
                        ),
                      ),
              ),
              Expanded(
                child: switch ((controller, _failed)) {
                  // No engine on this device/build at all. Retry cannot help,
                  // so it is not offered — the way out is back to Newsroom.
                  (null, _) => Padding(
                    padding: const EdgeInsets.all(WtmSpace.screenH),
                    child: Center(
                      child: WtmEmptyState(
                        glyph: WtmGlyph.bookmark,
                        title: l10n.wtmArticleWebUnavailableTitle,
                        message: l10n.wtmArticleWebUnavailableMessage,
                        ctaLabel: l10n.wtmNewsTitle,
                        onCta: () => wtmPageBack(context),
                      ),
                    ),
                  ),
                  // The engine is there and the page did not load — offline, a
                  // dead link, a TLS failure we did not override. Retryable.
                  (_, true) => Padding(
                    padding: const EdgeInsets.all(WtmSpace.screenH),
                    child: Center(
                      child: WtmErrorState(
                        title: l10n.wtmArticleWebErrorTitle,
                        message: l10n.wtmArticleWebErrorMessage,
                        retryLabel: l10n.commonRetry,
                        onRetry: _retry,
                      ),
                    ),
                  ),
                  (final WebViewController c, false) => WebViewWidget(
                    controller: c,
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reader's chrome: back, the article title, and the publisher's domain so
/// the user always knows whose page this is. Deliberately NOT a browser bar —
/// there is no editable address field and no "open externally" affordance.
class _ReaderHead extends StatelessWidget {
  const _ReaderHead({
    required this.title,
    required this.domain,
    required this.onBack,
  });

  final String title;
  final String domain;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WtmSpace.screenH,
        WtmSpace.s8,
        WtmSpace.screenH,
        WtmSpace.s8,
      ),
      child: Row(
        children: [
          WtmIconButton(
            WtmGlyph.back,
            semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: onBack,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WtmType.h2.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 3),
                Text(
                  domain.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WtmType.eyebrow.copyWith(letterSpacing: 2.52),
                ),
              ],
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}
