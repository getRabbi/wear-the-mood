import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/credits_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../shell/shell_providers.dart';
import 'drawers/closet_drawer.dart';
import 'drawers/drawer_gating.dart';
import 'drawers/drawer_picker_sheet.dart';
import 'drawers/drawer_store.dart';
import 'wardrobe_add_processing.dart';
import 'wardrobe_categories.dart';
import 'wardrobe_image_service.dart';

/// Adds a piece to the closet (CLAUDE.md §8). Capture/pick a photo → it's
/// compressed (EXIF stripped) and uploaded to Supabase Storage → `POST
/// /v1/wardrobe` saves the item. Background removal + auto-tagging (§2.2) layer
/// on server-side later; for now the photo + optional name/category are enough.
class AddWardrobeItemScreen extends ConsumerStatefulWidget {
  const AddWardrobeItemScreen({super.key, this.presetDrawerId});

  /// When opened from a drawer, the new item is assigned to this drawer.
  final String? presetDrawerId;

  @override
  ConsumerState<AddWardrobeItemScreen> createState() =>
      _AddWardrobeItemScreenState();
}

/// How a new piece is added: a free background-removed cutout, or a premium AI
/// Enhance (clean, catalog-ready). Default is removeBg (BUILD_PROMPT_PRO_PROMAX).
enum _AddMode { removeBg, aiEnhance }

class _AddWardrobeItemScreenState extends ConsumerState<AddWardrobeItemScreen> {
  final _nameController = TextEditingController();
  Uint8List? _bytes;
  String? _category;
  String? _drawerId; // null = auto-suggest from category on save
  bool _drawerTouched = false;
  _AddMode _addMode = _AddMode.removeBg; // free background remove is the default

  @override
  void initState() {
    super.initState();
    _drawerId = widget.presetDrawerId;
    _drawerTouched = widget.presetDrawerId != null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pick(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    try {
      final bytes = await ref
          .read(wardrobeImageServiceProvider)
          .pickAndCompress(source);
      if (bytes != null && mounted) setState(() => _bytes = bytes);
    } catch (_) {
      _snack(l10n.addItemPickError);
    }
  }

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null) return;
    final l10n = AppLocalizations.of(context);
    final enhance = _addMode == _AddMode.aiEnhance;

    // AI Enhance spends a credit — confirm before charging (never silent, §18).
    if (enhance) {
      final cost = ref.read(creditsProvider).asData?.value.stdCost ?? 1;
      final ok = await showConfirmSheet(
        context,
        icon: Icons.auto_awesome,
        title: l10n.addPieceEnhanceTitle,
        message: l10n.aiCreditConfirm(cost),
        confirmLabel: l10n.addPieceEnhanceCta(cost),
        cancelLabel: l10n.commonCancel,
      );
      if (!ok || !mounted) return;
    }

    // Resolve the target drawer up-front — the explicit choice, else the
    // category suggestion from UNLOCKED drawers only (§18) so a free user is
    // never auto-assigned into a drawer they can't open.
    final drawers = ref.read(closetDrawersProvider);
    final locked = ref.read(lockedDrawerIdsProvider);
    final suggestable = [
      for (final d in drawers)
        if (!locked.contains(d.id)) d,
    ];
    final name = _nameController.text.trim();
    final drawerId = _drawerId ?? suggestDrawer(_category, suggestable)?.id;

    // Run the whole pipeline — upload, create, background removal, optional AI
    // enhance — behind a blocking progress sheet (the SINGLE loading cue, so
    // there's no second spinner on the button), and only reveal the closet once
    // the FINISHED piece is in it.
    final added = await showWardrobeAddProcessing(
      context,
      ref,
      bytes: bytes,
      title: name.isEmpty ? null : name,
      category: _category,
      drawerId: drawerId,
      enhance: enhance,
    );
    if (!mounted || !added) return;
    ref.read(shellTabProvider.notifier).select(ShellTabs.closet);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bytes = _bytes;
    final credits = ref.watch(creditsProvider).asData?.value;
    final isSubscriber = credits?.isSubscriber ?? false;
    final enhanceCost = credits?.stdCost ?? 1;
    final enhance = _addMode == _AddMode.aiEnhance;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.addItemTitle)),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    children: [
                      _PhotoArea(
                        bytes: bytes,
                        onCamera: () => _pick(ImageSource.camera),
                        onGallery: () => _pick(ImageSource.gallery),
                      ),
                      if (bytes != null) ...[
                        const SizedBox(height: AppSpace.lg),
                        _AddModeChoice(
                          mode: _addMode,
                          isSubscriber: isSubscriber,
                          onPickRemoveBg: () =>
                              setState(() => _addMode = _AddMode.removeBg),
                          onPickEnhance: () {
                            // Free users see AI Enhance but it's locked → paywall.
                            if (!isSubscriber) {
                              context.push(AppRoute.paywall);
                              return;
                            }
                            setState(() => _addMode = _AddMode.aiEnhance);
                          },
                        ),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          l10n.aiUploadDisclaimer,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.graphite,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpace.lg),
                      TextField(
                        controller: _nameController,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: l10n.addItemNameLabel,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text(
                        l10n.addItemCategoryLabel,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.graphite,
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      CategoryChipsField(
                        selected: _category,
                        onChanged: (v) => setState(() => _category = v),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text(
                        l10n.addItemDrawerLabel,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.graphite,
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      _DrawerPicker(
                        selectedId: _drawerId,
                        category: _category,
                        showSuggested: !_drawerTouched,
                        onPick: (id) => setState(() {
                          _drawerId = id;
                          _drawerTouched = true;
                        }),
                      ),
                    ],
                  ),
                ),
                _BottomBar(
                  child: PrimaryButton(
                    label: enhance
                        ? l10n.addPieceEnhanceCta(enhanceCost)
                        : l10n.addItemSave,
                    icon: enhance ? Icons.auto_awesome : Icons.add_rounded,
                    onPressed: bytes == null ? null : _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoArea extends StatelessWidget {
  const _PhotoArea({
    required this.bytes,
    required this.onCamera,
    required this.onGallery,
  });

  final Uint8List? bytes;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = bytes;

    if (data == null) {
      // A balanced, intentional panel (not a near-empty full-height box) before
      // a photo is chosen (real-device polish).
      return SizedBox(
        height: 220,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add_a_photo_outlined,
                size: 36,
                color: AppColors.graphite,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                l10n.addItemChoosePhoto,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                l10n.addItemPhotoHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.graphite,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(l10n.addItemCamera),
                  ),
                  OutlinedButton.icon(
                    onPressed: onGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(l10n.addItemGallery),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Image.memory(data, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: onCamera,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l10n.addItemCamera),
            ),
            TextButton.icon(
              onPressed: onGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.addItemGallery),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Choose how to add this piece" — free Remove background (default) vs premium
/// AI Enhance (BUILD_PROMPT_PRO_PROMAX.md). Free users see AI Enhance locked.
class _AddModeChoice extends StatelessWidget {
  const _AddModeChoice({
    required this.mode,
    required this.isSubscriber,
    required this.onPickRemoveBg,
    required this.onPickEnhance,
  });

  final _AddMode mode;
  final bool isSubscriber;
  final VoidCallback onPickRemoveBg;
  final VoidCallback onPickEnhance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.addPieceHowTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpace.sm),
        _OptionCard(
          selected: mode == _AddMode.removeBg,
          icon: Icons.auto_fix_high_outlined,
          title: l10n.addPieceRemoveBgTitle,
          subtitle: l10n.addPieceRemoveBgSub,
          onTap: onPickRemoveBg,
        ),
        const SizedBox(height: AppSpace.sm),
        _OptionCard(
          selected: mode == _AddMode.aiEnhance,
          icon: Icons.auto_awesome,
          title: l10n.addPieceEnhanceTitle,
          subtitle: l10n.addPieceEnhanceSub,
          description: l10n.addPieceEnhanceDesc,
          locked: !isSubscriber,
          onTap: onPickEnhance,
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.description,
    this.locked = false,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? description;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.md);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.glassBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: selected ? AppColors.accent : AppColors.graphite),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: text.titleMedium),
                        if (locked) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.lock_outline_rounded,
                              size: 14, color: AppColors.graphite),
                        ],
                      ],
                    ),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(color: AppColors.graphite),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(description!, style: text.bodySmall),
                    ],
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? AppColors.accent : AppColors.glassBorder,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: child,
        ),
      ),
    );
  }
}

/// Picks the drawer a new item lands in — pre-fills the category suggestion and
/// lets the user change it or create a new drawer.
class _DrawerPicker extends ConsumerWidget {
  const _DrawerPicker({
    required this.selectedId,
    required this.category,
    required this.showSuggested,
    required this.onPick,
  });

  final String? selectedId;
  final String? category;
  final bool showSuggested;
  final ValueChanged<String?> onPick;

  ClosetDrawer? _byId(List<ClosetDrawer> drawers, String? id) {
    if (id == null) return null;
    for (final d in drawers) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final result = await showDrawerPickerSheet(context, selectedId: selectedId);
    if (result != null) onPick(result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final drawers = ref.watch(closetDrawersProvider);
    // Suggest only from UNLOCKED drawers (§18) — never pre-pick a locked one.
    final locked = ref.watch(lockedDrawerIdsProvider);
    final suggestable = [
      for (final d in drawers)
        if (!locked.contains(d.id)) d,
    ];
    final chosen = _byId(drawers, selectedId);
    final suggested = chosen == null && showSuggested
        ? suggestDrawer(category, suggestable)
        : null;
    final shown = chosen ?? suggested;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Icon(shown?.icon ?? Icons.inventory_2_outlined,
                  color: shown?.accent ?? AppColors.lavender, size: 20),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  shown?.name ?? l10n.addItemDrawerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
              if (suggested != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    l10n.addItemDrawerSuggested,
                    style: text.bodySmall?.copyWith(
                      color: AppColors.lavender,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
              const Icon(Icons.expand_more_rounded, color: AppColors.graphite),
            ],
          ),
        ),
      ),
    );
  }
}
