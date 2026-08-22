import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../features/wardrobe/category_error.dart';
import '../../features/wardrobe/garment_category.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_category_picker.dart';

/// Inline repair for a piece whose category the server cannot read.
///
/// What this replaces is a dead end. A legacy item — added before a category was
/// mandatory, or filed under a word like "Accessories" that names no body region
/// — is refused by the try-on planner, correctly: rendering a garment nobody can
/// identify means guessing which part of somebody's body to repaint, and a wrong
/// guess is a charged, wrong picture of them. But the refusal arrived as a
/// failure sheet AFTER the tap, with no way forward from where the person was
/// standing.
///
/// So the question is asked instead, at the moment it matters, with the actual
/// garment on screen. Answer it and the try-on that prompted it continues on its
/// own — the point is to resolve the block, not to send somebody off to a
/// settings screen to come back later.
///
/// Order is the whole safety property: the category is saved and CONFIRMED by
/// the server first, and only a confirmed update continues. A failed update
/// starts no job and spends no credit, because a job started on a piece the
/// server still cannot read is exactly the render this is preventing.
class WtmCategoryResolverSheet extends ConsumerStatefulWidget {
  const WtmCategoryResolverSheet({
    super.key,
    required this.item,
    this.continuesToTryOn = true,
  });

  final WardrobeItem item;

  /// Whether answering this question will carry straight on into the try-on
  /// that prompted it.
  ///
  /// True from a Try On tap, and the button says so. FALSE from the closet's
  /// review banner, which is somebody tidying their closet — nothing is waiting
  /// to be rendered, and a button reading "Save & Try On" there promises a
  /// render that never comes. Caught on a device: the sheet saved the category,
  /// closed, and returned to the closet, exactly as designed and not at all as
  /// labelled.
  final bool continuesToTryOn;

  @override
  ConsumerState<WtmCategoryResolverSheet> createState() =>
      _WtmCategoryResolverSheetState();
}

class _WtmCategoryResolverSheetState
    extends ConsumerState<WtmCategoryResolverSheet> {
  String? _category;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    // Single-flight. A double tap must not fire two PATCHes, and — because the
    // caller continues a try-on on success — must never resolve twice and hand
    // back two "go ahead"s for one question.
    if (_saving || !isChoosableGarmentCategory(_category)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    try {
      final updated = await ref
          .read(wardrobeRepositoryProvider)
          .updateItem(
            widget.item.id,
            title: widget.item.title?.trim().isNotEmpty ?? false
                ? widget.item.title
                // The API requires a name as well as a category, and a legacy
                // piece may have neither. Falling back to the category label
                // keeps the repair to ONE question instead of turning it into a
                // form — and it is a truthful name, not an invented one.
                : garmentCategoryOf(_category)?.label(l10n),
            category: _category,
            color: widget.item.color,
          );
      if (!mounted) return;
      // Keep the closet in step, so the grid and any open detail view stop
      // showing this piece as needing a category.
      ref.read(wardrobeItemsProvider.notifier).replaceItem(updated);
      Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Never the raw transport text — see `categoryErrorMessage`.
        _error = categoryErrorMessage(l10n, e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.catFixFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final image = widget.item.cardImageUrl;
    final chosen = garmentCategoryOf(_category);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.screenH,
            WtmSpace.s16,
            WtmSpace.screenH,
            WtmSpace.s18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.catFixTitle,
                textAlign: TextAlign.center,
                style: WtmType.h1.copyWith(fontSize: 20),
              ),
              const SizedBox(height: WtmSpace.s6),
              Text(
                widget.continuesToTryOn
                    ? l10n.catFixMessage
                    : l10n.catFixMessageReview,
                textAlign: TextAlign.center,
                style: WtmType.sub,
              ),
              const SizedBox(height: WtmSpace.s14),
              // The REAL garment, not a placeholder. Somebody asked to identify
              // a piece needs to be looking at the piece.
              if (image != null)
                Center(
                  child: SizedBox(
                    width: 120,
                    child: FabricTile(
                      imageUrl: image,
                      isCutout: widget.item.displaysCutout,
                      swatchIndex: widget.item.id.hashCode.abs() % 8,
                      fit: BoxFit.contain,
                      semanticLabel: widget.item.title ?? '',
                    ),
                  ),
                ),
              const SizedBox(height: WtmSpace.s16),
              WtmCategoryPicker(
                selected: _category,
                enabled: !_saving,
                // The sheet title above already asks the question.
                showHeading: false,
                legacyValue: widget.item.category,
                onChanged: (value) => setState(() {
                  _category = value;
                  _error = null;
                }),
              ),
              const SizedBox(height: WtmSpace.s14),
              // An honest heads-up rather than a hidden failure: a belt saves
              // fine and still will not be rendered, and it is better to say so
              // before the tap than to let the look come back without it.
              if (chosen != null && !chosen.isTryOnCapable) ...[
                Text(
                  l10n.catFixUnsupported(chosen.label(l10n)),
                  style: WtmType.micro.copyWith(color: WtmColors.muted),
                ),
                const SizedBox(height: WtmSpace.s10),
              ],
              if (_error != null) ...[
                Text(
                  _error!,
                  style: WtmType.micro.copyWith(color: WtmColors.danger),
                ),
                const SizedBox(height: WtmSpace.s10),
              ],
              GradientCta(
                label: widget.continuesToTryOn
                    ? l10n.catFixSaveAndTryOn
                    : l10n.catFixSaveOnly,
                onPressed: (_saving || !isChoosableGarmentCategory(_category))
                    ? null
                    : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ask what a piece is, and return the UPDATED item once the server has
/// confirmed it. Null means the person backed out or the update failed — and in
/// both cases the caller must not proceed with whatever prompted this.
Future<WardrobeItem?> showWtmCategoryResolver(
  BuildContext context, {
  required WardrobeItem item,
  bool continuesToTryOn = true,
}) {
  return showModalBottomSheet<WardrobeItem>(
    context: context,
    backgroundColor: WtmColors.panel,
    isScrollControlled: true,
    // Not dismissible by accident: this sheet is standing between a tap and a
    // charge, so backing out should be a decision.
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(WtmRadius.sheetTop),
      ),
    ),
    builder: (context) => WtmCategoryResolverSheet(
      item: item,
      continuesToTryOn: continuesToTryOn,
    ),
  );
}

/// Make [item] try-on ready, asking its owner if the server cannot read it.
///
/// The ONE place the "repair, then continue" rule lives, so every Try On entry
/// point behaves identically and none of them can forget the order. Returns the
/// item to render with, or null when the caller must stop — and stopping here
/// means no job was created and no credit was spent, which is the property that
/// matters most in this file.
Future<WardrobeItem?> wtmEnsureCategory(
  BuildContext context,
  WardrobeItem item,
) async {
  if (!item.needsCategory) return item;
  if (!context.mounted) return null;
  return showWtmCategoryResolver(context, item: item);
}
