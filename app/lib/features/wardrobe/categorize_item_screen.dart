import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'closet_colors.dart';
import 'drawers/closet_drawer.dart';
import 'drawers/drawer_picker_sheet.dart';
import 'drawers/drawer_store.dart';
import 'wardrobe_categories.dart';
import 'wardrobe_providers.dart';

/// Categorize / edit one owned piece (real-device polish — "Tap to categorize"
/// used to dead-end on a static detail page). Lets the user set a name, pick a
/// category (rich taxonomy), a colour, and move it to a drawer, then saves via
/// PATCH /v1/wardrobe/{id}. Returns the updated item to the caller so the detail
/// page can refresh in place; the closet grid refetches via invalidation.
class CategorizeItemScreen extends ConsumerStatefulWidget {
  const CategorizeItemScreen({super.key, required this.item});

  final WardrobeItem item;

  @override
  ConsumerState<CategorizeItemScreen> createState() =>
      _CategorizeItemScreenState();
}

class _CategorizeItemScreenState extends ConsumerState<CategorizeItemScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.item.title ?? '',
  );
  late String? _category = widget.item.category;
  late String? _colorLabel = resolveItemColor(widget.item)?.label;
  String? _drawerId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _drawerId = ref.read(closetAssignmentsProvider)[widget.item.id];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final name = _name.text.trim();
    try {
      final updated = await ref
          .read(wardrobeRepositoryProvider)
          .updateItem(
            widget.item.id,
            title: name.isEmpty ? null : name,
            category: _category,
            color: _colorLabel,
          );
      // Drawer assignment is local (no migration) — explicit choice wins, else
      // fall back to the category suggestion so it lands somewhere sensible.
      final drawers = ref.read(closetDrawersProvider);
      final drawerId = _drawerId ?? suggestDrawer(_category, drawers)?.id;
      final assignments = ref.read(closetAssignmentsProvider.notifier);
      if (drawerId != null) {
        assignments.assign(widget.item.id, drawerId);
      } else {
        assignments.unassign(widget.item.id);
      }
      ref.invalidate(wardrobeItemsProvider);
      ref.invalidate(wardrobeViewProvider);
      if (!mounted) return;
      _snack(l10n.categorizeSaved);
      context.pop(updated);
    } on ApiException {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(l10n.categorizeError);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(l10n.categorizeError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final drawers = ref.watch(closetDrawersProvider);
    final drawer = drawerById(drawers, _drawerId);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.categorizeTitle)),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.xl,
              ),
              children: [
                // Small preview so the user sees what they're tagging.
                Center(
                  child: SizedBox(
                    width: 140,
                    height: 140,
                    child: SmartImageCard(
                      imageUrl: widget.item.displayImageUrl ?? '',
                      aspectRatio: 1,
                      fit: BoxFit.contain,
                      padded: true,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Text(l10n.categorizeNameLabel, style: text.labelLarge),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: _name,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: l10n.categorizeNameHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Text(l10n.categorizeCategoryLabel, style: text.labelLarge),
                const SizedBox(height: AppSpace.sm),
                CategoryChipsField(
                  selected: _category,
                  onChanged: (v) => setState(() => _category = v),
                ),
                const SizedBox(height: AppSpace.lg),
                Text(l10n.categorizeColorLabel, style: text.labelLarge),
                const SizedBox(height: AppSpace.sm),
                _ColorChips(
                  selected: _colorLabel,
                  onChanged: (v) => setState(() => _colorLabel = v),
                ),
                const SizedBox(height: AppSpace.lg),
                Text(l10n.addItemDrawerLabel, style: text.labelLarge),
                const SizedBox(height: AppSpace.sm),
                _DrawerTile(
                  drawer: drawer,
                  onTap: () async {
                    final picked = await showDrawerPickerSheet(
                      context,
                      selectedId: _drawerId,
                    );
                    if (picked != null) setState(() => _drawerId = picked);
                  },
                ),
              ],
            ),
            if (_saving)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _SaveBar(
        saving: _saving,
        onSave: _save,
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.saving, required this.onSave});

  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: PrimaryButton(
            label: l10n.categorizeSave,
            icon: Icons.check_rounded,
            isLoading: saving,
            onPressed: onSave,
          ),
        ),
      ),
    );
  }
}

class _ColorChips extends StatelessWidget {
  const _ColorChips({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final c in closetColorPalette)
          ChoiceChip(
            avatar: CircleAvatar(backgroundColor: c.swatch, radius: 9),
            label: Text(c.label),
            selected: selected == c.label,
            onSelected: (sel) => onChanged(sel ? c.label : null),
          ),
      ],
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({required this.drawer, required this.onTap});

  final ClosetDrawer? drawer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Icon(
                drawer?.icon ?? Icons.inventory_2_outlined,
                color: drawer?.accent ?? AppColors.lavender,
                size: 20,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  drawer?.name ?? l10n.categorizeDrawerNone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
              const Icon(Icons.expand_more_rounded, color: AppColors.graphite),
            ],
          ),
        ),
      ),
    );
  }
}
