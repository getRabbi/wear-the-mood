import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../features/discover/application/product_feed.dart';
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
  const WtmShopSearchScreen({super.key});

  @override
  ConsumerState<WtmShopSearchScreen> createState() =>
      _WtmShopSearchScreenState();
}

class _WtmShopSearchScreenState extends ConsumerState<WtmShopSearchScreen> {
  final _controller = TextEditingController();
  String? _submitted;

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return WtmPage(
      title: l10n.wtmSearchTitle,
      eyebrow: l10n.wtmDiscoverTitle,
      children: [
        _Field(
          controller: _controller,
          hint: l10n.wtmShopSearchHint,
          onSubmitted: _submit,
        ),
        const SizedBox(height: WtmSpace.s16),
        if (_submitted == null)
          ..._recents(l10n)
        else
          ..._results(l10n, _submitted!),
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
              title: l10n.wtmShopSearchEmpty(query),
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
                        product: product,
                        onToggleSave: () => ref
                            .read(productFeedProvider.notifier)
                            .toggleSave(product),
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
        return rows;
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;

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
              autofocus: true,
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
