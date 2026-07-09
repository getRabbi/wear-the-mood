import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../features/tryon/sample_garments.dart';
import '../../features/tryon/tryon_preselect.dart';
import '../../features/wardrobe/closet_category.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_mirror_flow.dart';

/// MoodMirror Step 2 (board 04, P4) — the outfit stack from the REAL closet
/// (cutouts preferred), with the sample rack as the activation path when the
/// closet is empty. Consumes [tryOnPreselectProvider] so "Try It On" taps
/// elsewhere land here pre-filled (the P5 stylist handoff uses the same door).
class WtmMirrorStep2Screen extends ConsumerStatefulWidget {
  const WtmMirrorStep2Screen({super.key});

  @override
  ConsumerState<WtmMirrorStep2Screen> createState() =>
      _WtmMirrorStep2ScreenState();
}

class _WtmMirrorStep2ScreenState extends ConsumerState<WtmMirrorStep2Screen> {
  ClosetCategory _filter = ClosetCategory.all;

  @override
  void initState() {
    super.initState();
    // The stylist / closet / outfit "Try This On" handoff seeds the preselect
    // BEFORE navigating here, so a build-time ref.listen never fires for it
    // (listen only reports changes made while mounted). Consume the already-set
    // queue once, after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePreselect());
  }

  void _consumePreselect() {
    if (!mounted) return;
    final queued = ref.read(tryOnPreselectProvider);
    if (queued == null || queued.isEmpty) return;
    ref.read(wtmMirrorFlowProvider.notifier).setLayers(queued);
    ref.read(tryOnPreselectProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemsAsync = ref.watch(wardrobeItemsProvider);
    final draft = ref.watch(wtmMirrorFlowProvider);

    // A preselect that arrives WHILE this screen is mounted (rare) — the
    // initState pass covers the set-before-mount handoff.
    ref.listen(tryOnPreselectProvider, (_, next) {
      if (next == null || next.isEmpty) return;
      ref.read(wtmMirrorFlowProvider.notifier).setLayers(next);
      ref.read(tryOnPreselectProvider.notifier).clear();
    });

    final count = draft.layers.length;
    return WtmPage(
      title: l10n.wtmMirrorTitle,
      eyebrow: l10n.wtmMirrorStep(2),
      // The Next / Choose Mode action stays pinned to the viewport bottom for
      // every tab and closet size — no infinite scroll to reach it.
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GradientCta(
            label: count == 0
                ? l10n.wtmMirrorS2Next
                : l10n.wtmMirrorS2NextCount(count),
            onPressed:
                count == 0 ? null : () => context.push(AppRoute.wtmMirrorMode),
          ),
          const SizedBox(height: WtmSpace.s6),
          Text(
            l10n.wtmMirrorS2Max(WtmMirrorFlow.maxGarments),
            textAlign: TextAlign.center,
            style: WtmType.micro,
          ),
        ],
      ),
      children: [
        Text(
          l10n.wtmMirrorS2Title,
          textAlign: TextAlign.center,
          style: WtmType.h2.copyWith(fontSize: 19),
        ),
        const SizedBox(height: WtmSpace.s6),
        Text(
          l10n.wtmMirrorS2Sub,
          textAlign: TextAlign.center,
          style: WtmType.sub,
        ),
        const SizedBox(height: WtmSpace.s14),
        ...itemsAsync.when<List<Widget>>(
          skipLoadingOnReload: true,
          loading: () => [
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              childAspectRatio: 3 / 4,
              children: [
                for (var i = 0; i < 6; i++)
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      FabricTile(swatchIndex: i, aspectRatio: null),
                      const Positioned.fill(
                        child: LoadingShimmer(
                          borderRadius: BorderRadius.all(
                              Radius.circular(WtmRadius.tile)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          error: (_, _) => [
            WtmErrorState(
              title: l10n.wtmClosetErrorTitle,
              message: l10n.errorGenericTitle,
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.invalidate(wardrobeItemsProvider),
            ),
            const SizedBox(height: WtmSpace.s14),
            ..._samples(l10n, draft),
          ],
          data: (items) {
            final filtered = [
              for (final i in items)
                if (_filter.matches(i.category)) i,
            ];
            return [
              if (items.isNotEmpty) ...[
                WtmChipRow(
                  children: [
                    for (final c in ClosetCategory.values)
                      if (c != ClosetCategory.favorites)
                        WtmChip(
                          label: c.label(l10n),
                          on: _filter == c,
                          onTap: () => setState(() => _filter = c),
                        ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s12),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  childAspectRatio: 3 / 4,
                  children: [
                    for (final (i, item) in filtered.indexed)
                      FabricTile(
                        imageUrl: item.displayImageUrl,
                        swatchIndex: i,
                        aspectRatio: null,
                        fit: BoxFit.contain,
                        badge: draft.containsUrl(
                                item.cutoutUrl ?? item.imageUrl ?? '')
                            ? FabricBadge.selected
                            : FabricBadge.add,
                        semanticLabel: closetCardLabel(l10n, item),
                        onTap: () {
                          final added = ref
                              .read(wtmMirrorFlowProvider.notifier)
                              .toggleItem(item);
                          if (!added &&
                              !draft.containsUrl(
                                  item.cutoutUrl ?? item.imageUrl ?? '')) {
                            wtmSnack(context,
                                l10n.wtmMirrorS2Max(WtmMirrorFlow.maxGarments));
                          }
                        },
                      ),
                  ],
                ),
              ] else ...[
                WtmEmptyState(
                  glyph: WtmGlyph.hanger,
                  title: l10n.wtmMirrorS2EmptyTitle,
                  message: l10n.wtmMirrorS2EmptyMessage,
                  ctaLabel: l10n.wtmMirrorS2AddCta,
                  onCta: () => context.push(AppRoute.wtmClosetAdd),
                ),
                const SizedBox(height: WtmSpace.s10),
                ..._samples(l10n, draft),
              ],
            ];
          },
        ),
      ],
    );
  }

  List<Widget> _samples(AppLocalizations l10n, WtmMirrorDraft draft) {
    return [
      EyebrowLabel(l10n.wtmMirrorS2Samples),
      const SizedBox(height: WtmSpace.s10),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        childAspectRatio: 3 / 4,
        children: [
          for (final (i, garment) in sampleGarments.indexed)
            FabricTile(
              imageUrl: garment.imageUrl,
              swatchIndex: i + 2,
              aspectRatio: null,
              badge: draft.containsUrl(garment.imageUrl)
                  ? FabricBadge.selected
                  : FabricBadge.add,
              semanticLabel: garment.name,
              onTap: () => ref
                  .read(wtmMirrorFlowProvider.notifier)
                  .toggleSample(garment),
            ),
        ],
      ),
    ];
  }
}
