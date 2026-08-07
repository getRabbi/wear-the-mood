import 'package:flutter/material.dart';

import '../../features/discover/domain/discover_page.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_discover_tokens.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_discover_sections.dart';

/// The product-bearing furniture of Discover: one curated row, the filter
/// affordance, the row skeleton and the three empty states.
///
/// This file used to hold `WtmShopFeed`, which owned the whole lower half of
/// Discover: it took a paginated product list, cut it into bands, and dropped
/// modules into whatever gaps were left. That is the presentation path this
/// redesign removes. Section ORDER and how often a module may appear are now
/// decided once, in [DiscoverPage], and the screen renders what it is given.
/// Nothing here composes anything.

/// Heading copy for a row slot.
///
/// Every slot has its OWN pair, which is what makes a repeated heading
/// structurally impossible: [DiscoverPage] hands out each slot at most once per
/// page, so "Keep exploring" can no longer introduce four different rows.
({String eyebrow, String title}) wtmDiscoverRowCopy(
  AppLocalizations l10n,
  DiscoverRowSlot slot,
) => switch (slot) {
  DiscoverRowSlot.pickedForYou => (
    eyebrow: l10n.wtmShopStripPickedEyebrow,
    title: l10n.wtmShopPickedForYou,
  ),
  DiscoverRowSlot.newForYourMood => (
    eyebrow: l10n.wtmShopStripMoodEyebrow,
    title: l10n.wtmShopStripMoodTitle,
  ),
};

/// One curated product row: its own heading, then a horizontal strip of at most
/// [DiscoverPage.productsPerRow] cards.
///
/// Horizontal, always. There is no grid branch — a two-column wall is the shape
/// the approved layout exists to replace, so it is not reachable from here.
class WtmDiscoverProductRow extends StatelessWidget {
  const WtmDiscoverProductRow({
    super.key,
    required this.slot,
    required this.cards,
    this.trailing,
    this.onViewAll,
  });

  final DiscoverRowSlot slot;
  final List<Widget> cards;

  /// A control that replaces the text action — the filter indicator on the lead
  /// row.
  final Widget? trailing;

  /// Quiet secondary navigation, not a second CTA.
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final copy = wtmDiscoverRowCopy(l10n, slot);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        WtmSectionHead(
          eyebrow: copy.eyebrow,
          title: copy.title,
          trailing: trailing,
          actionLabel: onViewAll == null ? null : l10n.wtmShopViewAll,
          onAction: onViewAll,
        ),
        const SizedBox(height: WtmSpace.s12),
        WtmProductStrip(cards: cards),
      ],
    );
  }
}

/// Skeleton shaped like the row it stands in for — a strip of cards, not a
/// grid — so the first frame does not visibly re-lay-out when products land.
class WtmDiscoverRowSkeleton extends StatelessWidget {
  const WtmDiscoverRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).width;
    final width = WtmProductStripMetrics.widthFor(viewport);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: DiscoverTokens.padFor(viewport),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: WtmProductStripMetrics.gap),
            LoadingShimmer(
              width: width,
              height: width / DiscoverTokens.productAspect,
              borderRadius: BorderRadius.circular(WtmRadius.tile),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.text-action` with a filter glyph — a compact indicator, never a permanent
/// chip row.
class WtmDiscoverFilterButton extends StatelessWidget {
  const WtmDiscoverFilterButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WtmSpace.s10,
              vertical: WtmSpace.s6,
            ),
            decoration: BoxDecoration(
              color: active ? WtmColors.chipOnBg : WtmColors.chipBg,
              border: Border.all(
                color: active ? WtmColors.chipOnBorder : WtmColors.line,
              ),
              borderRadius: BorderRadius.circular(WtmRadius.chip),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WtmIcon(
                  WtmGlyph.filter,
                  size: 13,
                  color: active ? WtmColors.gold : WtmColors.muted,
                ),
                const SizedBox(width: WtmSpace.s6),
                // The heading caps this control's width, so at 2x text the
                // label has to give — it overflowed the chip by 40px on a
                // 320dp phone otherwise.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WtmType.chip.copyWith(
                      color: active ? WtmColors.gold : WtmColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The catalog's empty face.
///
/// Three genuinely different states: telling someone in an unsupported country
/// to "remove a filter" would be useless advice (§24).
class WtmDiscoverCatalogEmpty extends StatelessWidget {
  const WtmDiscoverCatalogEmpty({
    super.key,
    required this.regionEmpty,
    required this.filtered,
    required this.onResetFilters,
  });

  final bool regionEmpty;
  final bool filtered;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (regionEmpty) {
      return WtmEmptyState(
        glyph: WtmGlyph.store,
        title: l10n.wtmShopRegionEmptyTitle,
        message: l10n.wtmShopRegionEmptyMessage,
      );
    }
    if (filtered) {
      return WtmEmptyState(
        glyph: WtmGlyph.filter,
        title: l10n.wtmShopEmptyTitle,
        message: l10n.wtmShopEmptyMessage,
        ctaLabel: l10n.wtmShopFilterReset,
        onCta: onResetFilters,
      );
    }
    // Cold start: never a blank feed, and never a setup flow standing between
    // the user and Discover (§19.5).
    return WtmEmptyState(
      glyph: WtmGlyph.sparkle,
      title: l10n.wtmShopColdStartTitle,
      message: l10n.wtmShopColdStartMessage,
    );
  }
}

/// The quiet "these prices are not current" line shown over cached content.
class WtmDiscoverOfflineNote extends StatelessWidget {
  const WtmDiscoverOfflineNote({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DiscoverTokens.padFor(MediaQuery.sizeOf(context).width),
      ),
      child: Row(
        children: [
          const WtmIcon(WtmGlyph.shield, size: 13, color: WtmColors.muted),
          const SizedBox(width: WtmSpace.s6),
          Expanded(child: Text(l10n.wtmShopOffline, style: WtmType.micro)),
        ],
      ),
    );
  }
}
