import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_item.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_category_resolver.dart';

/// Whether the review offer is hidden for this session.
///
/// Session-scoped on purpose, and this is the whole design of the feature: a
/// closet full of legacy pieces is not a problem anybody has to solve today, so
/// "Not now" has to actually mean not now — and it has to be resumable, so it
/// comes back next time rather than being dismissed forever by one impatient
/// tap. Nothing is written to the server; declining to tidy your own closet is
/// not a fact worth persisting.
class CategoryReviewDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final categoryReviewDismissedProvider =
    NotifierProvider<CategoryReviewDismissed, bool>(
      CategoryReviewDismissed.new,
    );

/// A quiet offer to identify the pieces the renderer cannot read.
///
/// Deliberately NOT a gate, NOT a modal, and NOT part of onboarding. Those items
/// are perfectly good closet items — visible, searchable, filterable, wearable —
/// and the ONLY thing they cannot do is be rendered on a body. Forcing somebody
/// through a full-closet review to fix a limitation they may never hit would be
/// charging everybody for a problem that belongs to one feature.
///
/// It is also not the only route: the same repair is offered inline at the
/// moment a person actually tries to wear one ([wtmEnsureCategory]), which is
/// where it is genuinely worth interrupting for. This is just the shortcut for
/// somebody who would rather deal with them all at once.
class WtmCategoryReviewBanner extends ConsumerStatefulWidget {
  const WtmCategoryReviewBanner({super.key, required this.items});

  /// The whole closet; the banner picks out what needs a category itself.
  final List<WardrobeItem> items;

  @override
  ConsumerState<WtmCategoryReviewBanner> createState() =>
      _WtmCategoryReviewBannerState();
}

class _WtmCategoryReviewBannerState
    extends ConsumerState<WtmCategoryReviewBanner> {
  bool _reviewing = false;

  Future<void> _review(List<WardrobeItem> pending) async {
    if (_reviewing) return; // one pass at a time
    setState(() => _reviewing = true);
    final l10n = AppLocalizations.of(context);
    try {
      for (final item in pending) {
        if (!mounted) return;
        // Tidying the closet, not starting a render — so the sheet must not
        // offer to.
        final updated = await showWtmCategoryResolver(
          context,
          item: item,
          continuesToTryOn: false,
        );
        // Backing out of ONE piece ends the pass rather than marching through
        // the rest: somebody who dismissed the sheet is done for now, and the
        // banner will still be there whenever they are not.
        if (updated == null) return;
      }
      if (!mounted) return;
      wtmSnack(context, l10n.catReviewDone);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (ref.watch(categoryReviewDismissedProvider)) {
      return const SizedBox.shrink();
    }
    final pending = [
      for (final item in widget.items)
        if (item.needsCategory) item,
    ];
    if (pending.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: WtmSpace.s12),
      padding: const EdgeInsets.symmetric(
        horizontal: WtmSpace.s12,
        vertical: WtmSpace.s10,
      ),
      decoration: BoxDecoration(
        color: WtmColors.chipBg,
        borderRadius: BorderRadius.circular(WtmRadius.tile),
        border: Border.all(color: WtmColors.line),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.help_outline_rounded,
            size: 16,
            color: WtmColors.goldDim,
          ),
          const SizedBox(width: WtmSpace.s10),
          Expanded(
            child: Text(
              l10n.catReviewBanner(pending.length),
              style: WtmType.micro.copyWith(color: WtmColors.text),
            ),
          ),
          TextButton(
            onPressed: ref
                .read(categoryReviewDismissedProvider.notifier)
                .dismiss,
            child: Text(
              l10n.catReviewDismiss,
              style: WtmType.micro.copyWith(color: WtmColors.faint),
            ),
          ),
          TextButton(
            onPressed: _reviewing ? null : () => _review(pending),
            child: Text(
              l10n.catReviewAction,
              style: WtmType.micro.copyWith(color: WtmColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}
