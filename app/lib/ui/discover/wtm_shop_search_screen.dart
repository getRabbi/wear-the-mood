import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/router/routes.dart';
import '../../data/models/product.dart';
import '../../features/discover/application/product_feed.dart';
import '../../features/discover/application/saved_products.dart';
import '../../features/discover/application/shopping_tryon.dart';
import '../../features/discover/data/discover_local_store.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_product_card.dart';

/// Recent search terms from the on-device store (DISCOVER §11.1).
final recentSearchesProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(discoverLocalStoreProvider).recentSearches();
});

/// Product search (§11.1).
///
/// Its own screen, and its own results list rather than the Discover feed's:
/// this is a deliberate query, so the composed rhythm of products and modules
/// would be noise here. Submitting a search REPLACES the filters rather than
/// stacking on them (§11.2 — "do not silently carry old filters into a new
/// explicit search").
class WtmShopSearchScreen extends ConsumerStatefulWidget {
  const WtmShopSearchScreen({super.key, this.browse = false});

  /// BROWSE rather than SEARCH.
  ///
  /// `View all` on a Discover row opens the same screen in this mode: the
  /// products are on screen the moment it opens, the field is present but
  /// unfocused, and no keyboard appears. Arriving at a blank recents list with
  /// the keyboard already up — which is what View all used to do — reads as if
  /// the app decided the user wanted to type.
  final bool browse;

  @override
  ConsumerState<WtmShopSearchScreen> createState() =>
      _WtmShopSearchScreenState();
}

class _WtmShopSearchScreenState extends ConsumerState<WtmShopSearchScreen> {
  final _controller = TextEditingController();
  String? _submitted;

  /// Whether results are on screen: always in browse mode, and after a
  /// submitted term in search mode.
  bool get _showingResults => widget.browse || _submitted != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(analyticsProvider).track(AnalyticsEvents.searchOpen);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final term = raw.trim();
    if (term.isEmpty) return;

    setState(() => _submitted = term);
    _controller.text = term;
    ref.read(productFiltersProvider.notifier).search(term);
    ref
        .read(analyticsProvider)
        .track(AnalyticsEvents.searchSubmit, properties: {'has_query': true});

    // Best-effort: a store that cannot write must not stop a search.
    await ref.read(discoverLocalStoreProvider).addRecentSearch(term);
    ref.invalidate(recentSearchesProvider);
  }

  /// The card's Try On pill, through the one shared entry point (§13).
  ///
  /// Search results are ordinary product cards, so they carry the ordinary
  /// product action. The placement is `search` — the same code Product Details
  /// and the affiliate click already use from here, so a try-on started in
  /// results is attributed to results.
  void _tryOn(Product product) {
    final started = startShoppingTryOn(
      context,
      ref,
      product,
      placement: 'search',
    );
    if (!started) {
      wtmSnack(context, AppLocalizations.of(context).wtmShopTryOnUnavailable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return WtmPage(
      title: widget.browse ? l10n.wtmShopBrowseTitle : l10n.wtmSearchTitle,
      eyebrow: l10n.wtmDiscoverTitle,
      children: [
        _Field(
          controller: _controller,
          hint: l10n.wtmShopSearchHint,
          onSubmitted: _submit,
          // Only a deliberate tap on the field opens the keyboard in browse.
          autofocus: !widget.browse,
        ),
        const SizedBox(height: WtmSpace.s16),
        if (_showingResults)
          ..._results(l10n, _submitted ?? '')
        else
          ..._recents(l10n),
      ],
    );
  }

  List<Widget> _recents(AppLocalizations l10n) {
    final recents = ref.watch(recentSearchesProvider).asData?.value ?? const [];
    if (recents.isEmpty) return const [];

    return [
      Row(
        children: [
          EyebrowLabel(l10n.wtmShopSearchRecent),
          const Spacer(),
          // Clearing recent searches is a required user control (§36).
          GhostButton(
            label: l10n.wtmShopSearchClear,
            onPressed: () async {
              await ref.read(discoverLocalStoreProvider).clearRecentSearches();
              ref.invalidate(recentSearchesProvider);
            },
          ),
        ],
      ),
      const SizedBox(height: WtmSpace.s10),
      WtmChipRow(
        children: [
          for (final term in recents)
            WtmChip(label: term, on: false, onTap: () => _submit(term)),
        ],
      ),
    ];
  }

  List<Widget> _results(AppLocalizations l10n, String query) {
    final feed = ref.watch(productFeedProvider);
    return feed.when<List<Widget>>(
      skipLoadingOnReload: true,
      loading: () => const [
        LoadingShimmer(width: double.infinity, height: 220),
      ],
      error: (_, _) => [
        WtmErrorState(
          title: l10n.wtmDiscoverErrorTitle,
          message: l10n.errorGenericTitle,
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(productFeedProvider),
        ),
      ],
      data: (state) {
        if (state.isEmpty) {
          return [
            const SizedBox(height: WtmSpace.s22),
            WtmEmptyState(
              glyph: WtmGlyph.search,
              // Browse has no term to quote back, so "No results for ''" would
              // be nonsense there.
              title: query.isEmpty
                  ? l10n.wtmShopEmptyTitle
                  : l10n.wtmShopSearchEmpty(query),
              message: l10n.wtmShopEmptyMessage,
            ),
          ];
        }

        final columns = MediaQuery.sizeOf(context).width >= 720 ? 3 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < state.items.length; i += columns) {
          final slice = state.items.sublist(
            i,
            (i + columns).clamp(0, state.items.length),
          );
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: WtmSpace.s16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (c, product) in slice.indexed) ...[
                    if (c > 0) const SizedBox(width: WtmSpace.s10),
                    Expanded(
                      child: WtmProductCard(
                        key: ValueKey(product.id),
                        product: product.copyWith(
                          saved: watchSaved(ref, product),
                        ),
                        onToggleSave: () => ref
                            .read(productFeedProvider.notifier)
                            .toggleSave(product),
                        onTap: () => context.push(
                          '${AppRoute.wtmProductPath(product.id)}&from=search',
                          extra: product,
                        ),
                        onTryOn: () => _tryOn(product),
                      ),
                    ),
                  ],
                  for (var pad = slice.length; pad < columns; pad++) ...[
                    const SizedBox(width: WtmSpace.s10),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          );
        }
        // The catalog past page one. This screen is where `View all` lands and
        // where a search's results live, and it used to render page one and
        // stop — so "everything" was the first page and the rest of the catalog
        // could not be reached from anywhere in the app. Discover itself is a
        // fixed composition by design and deliberately does not paginate; this
        // is the surface that must.
        if (state.hasMore || state.loadingMore || state.loadMoreFailed) {
          rows.add(
            _LoadMoreTail(
              // Keyed on the cursor, so each page's tail is a NEW widget and
              // the visibility callback fires again for it. A fixed key would
              // load page two and never page three.
              key: ValueKey('more:${state.cursor ?? 'end'}'),
              state: state,
              onLoad: () => ref.read(productFeedProvider.notifier).loadMore(),
            ),
          );
        }
        return rows;
      },
    );
  }
}

/// The end of the results, and what to do about it.
///
/// Loads the next page when it scrolls into view, shows a skeleton while that
/// page is in flight, and offers Retry when it failed — a failed page two must
/// never blank the page one the user is reading (§24), so the failure lives
/// here rather than replacing the grid.
class _LoadMoreTail extends StatefulWidget {
  const _LoadMoreTail({super.key, required this.state, required this.onLoad});

  final ProductFeedState state;
  final VoidCallback onLoad;

  @override
  State<_LoadMoreTail> createState() => _LoadMoreTailState();
}

class _LoadMoreTailState extends State<_LoadMoreTail> {
  /// One automatic load per tail. `loadMore` is a no-op while a page is in
  /// flight, but a detector that keeps firing on every visibility change would
  /// still be a stream of wasted calls.
  bool _asked = false;

  void _onVisibility(VisibilityInfo info) {
    if (_asked || !mounted) return;
    if (info.visibleFraction <= 0) return;
    if (!widget.state.hasMore || widget.state.loadingMore) return;
    _asked = true;
    widget.onLoad();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // A failed page waits for a deliberate tap: retrying automatically on an
    // offline device is a loop nobody asked for.
    if (widget.state.loadMoreFailed && !widget.state.loadingMore) {
      return Padding(
        padding: const EdgeInsets.only(bottom: WtmSpace.s16),
        child: Center(
          child: GhostButton(
            label: l10n.commonRetry,
            onPressed: () {
              _asked = true;
              widget.onLoad();
            },
          ),
        ),
      );
    }

    return VisibilityDetector(
      key: Key('shop-more:${widget.state.cursor ?? 'end'}'),
      onVisibilityChanged: _onVisibility,
      child: const Padding(
        padding: EdgeInsets.only(bottom: WtmSpace.s16),
        child: LoadingShimmer(width: double.infinity, height: 120),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.onSubmitted,
    required this.autofocus,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WtmSpace.s12),
      decoration: BoxDecoration(
        color: WtmColors.chipBg,
        border: Border.all(color: WtmColors.line),
        borderRadius: BorderRadius.circular(WtmRadius.button),
      ),
      child: Row(
        children: [
          const WtmIcon(WtmGlyph.search, size: 15, color: WtmColors.muted),
          const SizedBox(width: WtmSpace.s8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              style: WtmType.body.copyWith(fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: WtmType.micro,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: WtmSpace.s12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
