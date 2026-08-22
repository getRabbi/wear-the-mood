import 'package:flutter/material.dart';

import '../../features/wardrobe/garment_category.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_surface.dart';
import '../../theme/wtm_typography.dart';

/// The garment category picker, shared by Add Garment, Edit piece and the
/// legacy-item resolver.
///
/// One control, one vocabulary ([kGarmentCategories]), one visual language. The
/// thing it is built to prevent is a person tapping a word whose consequence
/// they could not have known — a tank top filed under "Bottoms" and rendered as
/// trousers on their own photograph. So every tile carries three things:
///
///   * a label,
///   * two to four CONCRETE examples ("T-shirt, shirt, blouse, sweater"), which
///     is what actually disambiguates a bucket name, and
///   * an honest badge when the try-on provider cannot render that role, rather
///     than letting the limit surface later as a look that silently came back
///     missing a piece.
///
/// Nothing is preselected. [selected] is null until the person taps, and a
/// caller that rebuilds this widget for a NEW garment passes null again — there
/// is no "last used" memory anywhere in this file, deliberately: a default that
/// is right most of the time is a default nobody reads, and the times it is
/// wrong are exactly the times it matters.
class WtmCategoryPicker extends StatelessWidget {
  const WtmCategoryPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.showError = false,
    this.enabled = true,
    this.legacyValue,
    this.showHeading = true,
  });

  /// The stored category value currently chosen, or null for "not chosen".
  final String? selected;

  /// Called with the tapped tile's stored value. Never called with null — a
  /// category is chosen, not toggled off, because an item that reaches Save
  /// must have one.
  final ValueChanged<String> onChanged;

  /// Whether to show the "you must choose one" error. Held back by the caller
  /// until the person has actually tried to continue.
  final bool showError;

  /// False while a save is in flight, so a tile cannot be re-tapped mid-write.
  final bool enabled;

  /// Whether to draw the "What kind of piece is this?" heading.
  ///
  /// False where the surrounding surface has already asked — the legacy
  /// resolver's sheet title IS the question, and rendering it again put the
  /// same sentence on screen twice.
  final bool showHeading;

  /// The item's stored category when it is NOT one of the twelve — a legacy or
  /// free-text value. Shown as a plain statement of fact above the grid so the
  /// person can see what it is today without it being silently re-affirmed as
  /// a selection.
  final String? legacyValue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final legacy = legacyValue?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading) ...[
          Text(l10n.catSectionTitle, style: WtmType.labelMedium),
          const SizedBox(height: WtmSpace.s4),
        ],
        Text(
          l10n.catSectionHint,
          style: WtmType.micro.copyWith(color: WtmColors.muted),
        ),
        if (legacy != null && legacy.isNotEmpty) ...[
          const SizedBox(height: WtmSpace.s8),
          Text(
            l10n.catCurrentLegacy(legacy),
            style: WtmType.micro.copyWith(color: WtmColors.faint),
          ),
        ],
        const SizedBox(height: WtmSpace.s12),
        // A LayoutBuilder rather than a fixed column count: the tiles carry a
        // sentence of examples, and two per row on a 320 dp phone would wrap
        // "Sneakers, heels, boots, sandals" onto four lines.
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = WtmSpace.s8;
            final columns = constraints.maxWidth >= 560 ? 3 : 2;
            final tileWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final category in kGarmentCategories)
                  SizedBox(
                    width: tileWidth,
                    child: _CategoryTile(
                      category: category,
                      on: garmentCategoryOf(selected)?.value == category.value,
                      enabled: enabled,
                      onTap: () => onChanged(category.value),
                    ),
                  ),
              ],
            );
          },
        ),
        if (showError && garmentCategoryOf(selected) == null) ...[
          const SizedBox(height: WtmSpace.s8),
          Text(
            l10n.catErrorNotChosen,
            style: WtmType.micro.copyWith(color: WtmColors.danger),
          ),
        ],
      ],
    );
  }
}

/// One choice. Tall enough for a 48 dp target at every text scale, and the whole
/// tile is the target rather than just the label.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.on,
    required this.enabled,
    required this.onTap,
  });

  final GarmentCategory category;
  final bool on;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = category.label(l10n);
    final examples = category.examples(l10n);
    final renderable = category.isTryOnCapable;

    // The selected state has to survive on a near-black glassy surface, so it
    // carries three signals at once — gold fill, gold border, gold glyph — and
    // is never colour alone: the check mark is what a person who cannot
    // distinguish the border tint still sees (§4.4).
    final tile = AnimatedContainer(
      duration: WtmMotion.fast,
      curve: WtmMotion.easing,
      padding: const EdgeInsets.symmetric(
        horizontal: WtmSpace.s12,
        vertical: WtmSpace.s10,
      ),
      constraints: const BoxConstraints(minHeight: 76),
      decoration: BoxDecoration(
        color: on ? WtmColors.chipOnBg : WtmColors.chipBg,
        borderRadius: BorderRadius.circular(WtmRadius.tile),
        border: Border.all(
          color: on ? WtmColors.chipOnBorder : WtmColors.line,
          width: on ? 1.5 : 1,
        ),
        boxShadow: on ? WtmGlass.selectedGlow : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                category.icon,
                size: 18,
                color: on ? WtmColors.gold : WtmColors.muted,
              ),
              const SizedBox(width: WtmSpace.s8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: on
                      ? WtmType.labelMedium.copyWith(color: WtmColors.gold)
                      : WtmType.labelMedium,
                ),
              ),
              if (on)
                const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: WtmColors.gold,
                ),
            ],
          ),
          const SizedBox(height: WtmSpace.s4),
          Text(examples, style: WtmType.micro.copyWith(color: WtmColors.muted)),
          if (!renderable) ...[
            const SizedBox(height: WtmSpace.s4),
            Text(
              l10n.catNotRendered,
              style: WtmType.micro.copyWith(color: WtmColors.faint),
            ),
          ],
        ],
      ),
    );

    // One semantics node for the whole tile, reading label + examples together,
    // so a screen reader hears "Bottoms. Pants, jeans, skirt, shorts." rather
    // than two disconnected fragments.
    return Semantics(
      button: true,
      selected: on,
      enabled: enabled,
      label: renderable
          ? '$label. $examples'
          : '$label. $examples. ${l10n.catNotRendered}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Opacity(opacity: enabled ? 1 : 0.5, child: tile),
        ),
      ),
    );
  }
}

/// The confirmation line that sits next to Save.
///
/// Saving IS the confirmation — there is no second "are you sure" dialog — so
/// this line is what makes the choice reviewable at the moment it is committed:
/// it names, in the same words the renderer will use, what the piece is about
/// to become.
class WtmTryOnTypeSummary extends StatelessWidget {
  const WtmTryOnTypeSummary({super.key, required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final category = garmentCategoryOf(selected);

    final (text, color) = switch (category) {
      null => (l10n.catTryOnSummaryNone, WtmColors.faint),
      final c when !c.isTryOnCapable => (
        l10n.catTryOnSummaryUnsupported(c.label(l10n)),
        WtmColors.muted,
      ),
      final c => (l10n.catTryOnSummary(c.label(l10n)), WtmColors.goldDim),
    };

    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(
            category == null
                ? Icons.info_outline_rounded
                : Icons.auto_awesome_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: WtmSpace.s6),
          Expanded(
            child: Text(text, style: WtmType.micro.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
