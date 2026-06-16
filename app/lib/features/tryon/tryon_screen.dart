import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/tryon_job.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/credits_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../collections/local_collections.dart';
import '../credits/credits_chip.dart';
import '../credits/credits_sheet.dart';
import '../paywall/billing_providers.dart';
import '../profile/avatar_service.dart';
import '../wardrobe/wardrobe_providers.dart';
import 'models/studio_models.dart';
import 'sample_garments.dart';
import 'tryon_controller.dart';
import 'tryon_mode.dart';
import 'tryon_preselect.dart';
import 'tryon_state.dart';
import 'two_d/two_d_editor_screen.dart';

/// The try-on hook (CLAUDE.md §7, §17). A premium landing — choose photo,
/// clothing and mode — then watch it render and reveal the result. Handles all
/// four states (§4.3). All AI runs server-side; the controller/credits/moderation
/// logic is unchanged.
class TryOnScreen extends ConsumerStatefulWidget {
  const TryOnScreen({super.key});

  @override
  ConsumerState<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends ConsumerState<TryOnScreen> {
  // The outfit stack — multiple pieces (tops, bottoms, shoes, accessories…).
  final List<TryOnLayer> _selected = [];
  TryOnMode _mode = TryOnMode.twoD; // free 2D is the default

  void _addPiece(WardrobeItem item) {
    final url = item.cutoutUrl ?? item.imageUrl;
    if (url == null || url.isEmpty) return;
    if (_selected.any((l) => l.wardrobeItemId == item.id)) return;
    setState(() => _selected.add(TryOnLayer.fromSource(
      imageUrl: url,
      category: item.category,
      wardrobeItemId: item.id,
      zIndex: _selected.length,
    )));
  }

  void _removePiece(String layerId) =>
      setState(() => _selected.removeWhere((l) => l.id == layerId));

  /// The garment the (single-garment) AI endpoint renders today — the most
  /// prominent piece. Full multi-garment AI is a follow-up; the whole stack is
  /// still saved.
  TryOnLayer? _primary() {
    if (_selected.isEmpty) return null;
    int rank(TryOnLayer l) {
      final c = (l.category ?? '').toLowerCase();
      if (c.contains('dress') || c.contains('gown')) return 0;
      if (c.contains('top') || c.contains('shirt') || c.contains('blouse')) {
        return 1;
      }
      if (c.contains('pant') ||
          c.contains('jean') ||
          c.contains('skirt') ||
          c.contains('bottom') ||
          c.contains('short')) {
        return 2;
      }
      if (c.contains('shoe')) return 3;
      return 4;
    }

    final sorted = [..._selected]..sort((a, b) => rank(a).compareTo(rank(b)));
    return sorted.first;
  }

  /// Generate — branches on mode. 2D builds the on-device outfit composite (free,
  /// no credits, multi-layer). AI keeps the premium-OR-credits gate and renders
  /// the primary piece via the existing server flow.
  Future<void> _generate() async {
    if (_selected.isEmpty) return;
    final bodyUrl =
        ref.read(avatarSignedUrlProvider).asData?.value ?? samplePersonImageUrl;

    if (_mode.isTwoD) {
      await context.push(
        AppRoute.tryon2dEditor,
        extra: TwoDEditorArgs(bodyImageUrl: bodyUrl, layers: _selected),
      );
      return;
    }

    final isPremium = ref.read(isPremiumProvider);
    final canSpend = ref
        .read(creditsProvider)
        .maybeWhen(data: (c) => c.canSpend, orElse: () => false);
    if (!isPremium && !canSpend) {
      final l10n = AppLocalizations.of(context);
      final upgrade = await showConfirmSheet(
        context,
        icon: Icons.workspace_premium_outlined,
        title: l10n.tryOnUpgradeTitle,
        message: l10n.tryOnUpgradeBody,
        confirmLabel: l10n.tryOnUpgradeCta,
        cancelLabel: l10n.tryOnUpgradeMaybe,
      );
      if (upgrade && mounted) context.push(AppRoute.paywall);
      return;
    }
    final primary = _primary();
    if (primary == null) return;
    await ref
        .read(tryOnControllerProvider.notifier)
        .start(personImageUrl: bodyUrl, garmentImageUrl: primary.imageUrl);
  }

  void _another() {
    setState(() => _selected.clear());
    ref.read(tryOnControllerProvider.notifier).reset();
  }

  // Both modes are freely selectable; AI gating happens at generate time.
  void _pickMode(TryOnMode mode) => setState(() => _mode = mode);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(tryOnControllerProvider);
    final avatarUrl = ref.watch(avatarSignedUrlProvider).asData?.value;
    final personImageUrl = avatarUrl ?? samplePersonImageUrl;

    // Seed the outfit stack from elsewhere (closet "Try on me" or community
    // "Try this look").
    ref.listen(tryOnPreselectProvider, (_, next) {
      if (next != null && next.isNotEmpty) {
        setState(() => _selected
          ..clear()
          ..addAll(next));
        ref.read(tryOnPreselectProvider.notifier).clear();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tryOnLandingTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: l10n.tryonHistoryTitle,
            onPressed: () => context.push(AppRoute.tryonHistory),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.md),
            child: Center(
              child: CreditsChip(onTap: () => showCreditsSheet(context)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: AppMotion.base,
          switchInCurve: AppMotion.easing,
          child: switch (state) {
            TryOnIdle() => _Landing(
              key: const ValueKey('landing'),
              selected: _selected,
              mode: _mode,
              hasAvatar: avatarUrl != null,
              avatarUrl: avatarUrl,
              onAddPiece: _addPiece,
              onRemovePiece: _removePiece,
              onPickMode: _pickMode,
              onGenerate: _generate,
              onSetupAvatar: () => context.push(AppRoute.avatar),
              onAddClothes: () => context.push(AppRoute.wardrobeAdd),
            ),
            TryOnSubmitting() || TryOnPolling() => _Progress(
              key: const ValueKey('progress'),
              state: state,
              personImageUrl: personImageUrl,
            ),
            TryOnSuccess(:final job) => _Result(
              key: const ValueKey('result'),
              job: job,
              personImageUrl: personImageUrl,
              onAnother: _another,
            ),
            TryOnFailure(:final message, :final code) => _Failure(
              key: const ValueKey('failure'),
              message: message,
              isInsufficientCredits: code == ApiErrorCode.insufficientCredits,
              isModerationBlocked: code == ApiErrorCode.moderationBlocked,
              onRetry: _another,
              onUpgrade: () => context.push(AppRoute.paywall),
            ),
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── Landing ─────────

class _Landing extends ConsumerWidget {
  const _Landing({
    super.key,
    required this.selected,
    required this.mode,
    required this.hasAvatar,
    required this.avatarUrl,
    required this.onAddPiece,
    required this.onRemovePiece,
    required this.onPickMode,
    required this.onGenerate,
    required this.onSetupAvatar,
    required this.onAddClothes,
  });

  final List<TryOnLayer> selected;
  final TryOnMode mode;
  final bool hasAvatar;
  final String? avatarUrl;
  final ValueChanged<WardrobeItem> onAddPiece;
  final ValueChanged<String> onRemovePiece;
  final ValueChanged<TryOnMode> onPickMode;
  final VoidCallback onGenerate;
  final VoidCallback onSetupAvatar;
  final VoidCallback onAddClothes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final isPremium = ref.watch(isPremiumProvider);
    final canSpend = ref
        .watch(creditsProvider)
        .maybeWhen(data: (c) => c.canSpend, orElse: () => true);
    // 2D is free for everyone; only AI needs premium/credits.
    final aiBlocked = mode.isAi && !isPremium && !canSpend;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.lg,
            ),
            children: [
              Text(l10n.tryOnLandingSubtitle, style: text.bodyMedium),
              const SizedBox(height: AppSpace.lg),
              _StepCard(
                number: 1,
                title: l10n.tryOnStepPhotoTitle,
                subtitle: l10n.tryOnStepPhotoSub,
                child: hasAvatar
                    ? _PhotoRow(avatarUrl: avatarUrl!, onChange: onSetupAvatar)
                    : _AvatarPrompt(onSetup: onSetupAvatar),
              ),
              const SizedBox(height: AppSpace.md),
              _StepCard(
                number: 2,
                title: l10n.studioYourOutfit,
                subtitle: l10n.studioSelectLayerHint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OutfitStrip(selected: selected, onRemove: onRemovePiece),
                    const SizedBox(height: AppSpace.md),
                    _ClothingPicker(
                      selected: selected,
                      onAdd: onAddPiece,
                      onRemove: onRemovePiece,
                      onAddClothes: onAddClothes,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              _StepCard(
                number: 3,
                title: l10n.tryOnStepModeTitle,
                subtitle: l10n.tryOnStepModeSub,
                child: _ModeCards(mode: mode, onPick: onPickMode),
              ),
              const SizedBox(height: AppSpace.md),
              const _PhotoGuide(),
            ],
          ),
        ),
        _BottomBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mode-specific helper line: free for 2D, credit warning for AI.
              if (mode.isTwoD) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bolt_rounded,
                        size: 15, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      l10n.tryOn2dFreeHint,
                      style: text.bodySmall?.copyWith(color: AppColors.success),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
              ] else if (aiBlocked) ...[
                Text(
                  l10n.tryOnOutOfCredits,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: AppColors.danger),
                ),
                const SizedBox(height: AppSpace.sm),
              ] else ...[
                Text(
                  l10n.studioAiPrimaryNote,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              PrimaryButton(
                label: mode.isTwoD
                    ? l10n.studioGenerate2d
                    : l10n.tryOnGenerateAi,
                icon: mode.isTwoD ? Icons.layers_rounded : Icons.auto_awesome,
                // Enabled once the outfit has at least one piece; an AI tap with
                // no credits opens the upgrade sheet rather than failing.
                onPressed: selected.isNotEmpty ? onGenerate : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A numbered step container.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final int number;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: AppGradients.brand,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    Text(subtitle, style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          child,
        ],
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.avatarUrl, required this.onChange});

  final String avatarUrl;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: CachedNetworkImage(
            imageUrl: avatarUrl,
            width: 64,
            height: 80,
            fit: BoxFit.cover,
            placeholder: (_, _) =>
                const LoadingShimmer(width: 64, height: 80),
            errorWidget: (_, _, _) => const SizedBox(
              width: 64,
              height: 80,
              child: ColoredBox(color: AppColors.mist),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_rounded,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text(
                    l10n.tryOnSelectedLabel,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.success),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              SecondaryButton(
                label: l10n.tryOnChangePhoto,
                icon: Icons.photo_camera_outlined,
                expand: false,
                onPressed: onChange,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Nudge to set up a real avatar so try-on renders on the user, not a model.
class _AvatarPrompt extends StatelessWidget {
  const _AvatarPrompt({required this.onSetup});

  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onSetup,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              const Icon(Icons.face_outlined, color: AppColors.accent),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  l10n.tryOnAvatarPrompt,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected outfit stack — thumbnails with a remove button (or a hint when
/// empty).
class _OutfitStrip extends StatelessWidget {
  const _OutfitStrip({required this.selected, required this.onRemove});

  final List<TryOnLayer> selected;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (selected.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.layers_outlined, size: 18, color: AppColors.lavender),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                l10n.studioOutfitEmpty,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: selected.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (_, i) {
          final layer = selected[i];
          return SizedBox(
            width: 58,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: AppColors.paperAlt),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: CachedNetworkImage(
                          imageUrl: layer.imageUrl,
                          fit: BoxFit.contain,
                          errorWidget: (_, _, _) => const Icon(
                            Icons.checkroom_outlined,
                            size: 18,
                            color: AppColors.graphite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => onRemove(layer.id),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.scrim,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 13, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Multi-select wardrobe picker — tap a piece to add it to (or remove it from)
/// the outfit stack.
class _ClothingPicker extends ConsumerWidget {
  const _ClothingPicker({
    required this.selected,
    required this.onAdd,
    required this.onRemove,
    required this.onAddClothes,
  });

  final List<TryOnLayer> selected;
  final ValueChanged<WardrobeItem> onAdd;
  final ValueChanged<String> onRemove;
  final VoidCallback onAddClothes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wardrobe = ref.watch(wardrobeItemsProvider);

    return wardrobe.when(
      loading: () => SkeletonLoader.rowTiles(height: 120, width: 92, count: 4),
      error: (_, _) => _AddClothesTile(onTap: onAddClothes, full: true),
      data: (items) {
        if (items.isEmpty) {
          return _AddClothesTile(onTap: onAddClothes, full: true);
        }
        return SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
            itemBuilder: (_, i) {
              if (i == items.length) {
                return _AddClothesTile(onTap: onAddClothes);
              }
              final item = items[i];
              TryOnLayer? layer;
              for (final l in selected) {
                if (l.wardrobeItemId == item.id) {
                  layer = l;
                  break;
                }
              }
              final isSel = layer != null;
              return SizedBox(
                width: 92,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: isSel ? AppColors.accent : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: SmartImageCard(
                          imageUrl: item.displayImageUrl ?? '',
                          aspectRatio: 92 / 120,
                          fit: BoxFit.contain,
                          padded: true,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          onTap: () =>
                              isSel ? onRemove(layer!.id) : onAdd(item),
                        ),
                      ),
                    ),
                    if (isSel)
                      const Positioned(
                        top: 4,
                        right: 4,
                        child: _CheckBadge(),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AddClothesTile extends StatelessWidget {
  const _AddClothesTile({required this.onTap, this.full = false});

  final VoidCallback onTap;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: full ? double.infinity : 92,
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: AppColors.accent),
            const SizedBox(height: AppSpace.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
              child: Text(
                l10n.tryOnAddClothes,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCards extends StatelessWidget {
  const _ModeCards({required this.mode, required this.onPick});

  final TryOnMode mode;
  final ValueChanged<TryOnMode> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // IntrinsicHeight gives the Row a bounded height so the two cards can stretch
    // to equal height (a bare stretch Row in a scroll view forces infinite height).
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _ModeCard(
            selected: mode == TryOnMode.twoD,
            dark: false,
            icon: Icons.bolt_rounded,
            title: l10n.tryOnMode2dTitle,
            subtitle: l10n.tryOnMode2dSub,
            badge: l10n.tryOnBadgeFree,
            onTap: () => onPick(TryOnMode.twoD),
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: _ModeCard(
            selected: mode == TryOnMode.aiRealistic,
            dark: true,
            icon: Icons.auto_awesome,
            title: l10n.tryOnModeAiTitle,
            subtitle: l10n.tryOnModeAiSub,
            badge: l10n.tryOnBadgePremium,
            onTap: () => onPick(TryOnMode.aiRealistic),
          ),
        ),
      ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.dark,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  final bool selected;
  final bool dark;
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : AppColors.ink;
    final sub = dark ? Colors.white70 : AppColors.graphite;
    final radius = BorderRadius.circular(AppRadius.card);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          gradient: dark ? AppGradients.premiumDark : null,
          color: dark ? null : Theme.of(context).colorScheme.surface,
          borderRadius: radius,
          border: Border.all(
            color: selected
                ? AppColors.accent
                : (dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppColors.mist),
            width: selected ? 2 : 1,
          ),
          boxShadow: dark ? AppShadow.premiumGlow : AppShadow.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: dark ? Colors.white : AppColors.accent),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.16)
                        : AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    badge.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: dark ? Colors.white : AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(color: sub, fontSize: 11.5, height: 1.3)),
          ],
        ),
      ),
    );
  }
}

/// Collapsible "perfect photo" guidance (collapsed by default).
class _PhotoGuide extends StatelessWidget {
  const _PhotoGuide();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tips = [
      l10n.tryOnGuideFullBody,
      l10n.tryOnGuidePlainBg,
      l10n.tryOnGuideLighting,
      l10n.tryOnGuideFaceCamera,
      l10n.tryOnGuideArms,
      l10n.tryOnGuideOnePerson,
      l10n.tryOnGuideAvoid,
    ];
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          leading: const Icon(Icons.lightbulb_outline_rounded,
              color: AppColors.accent),
          title: Text(
            l10n.tryOnGuideTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            0,
            AppSpace.lg,
            AppSpace.md,
          ),
          children: [
            for (final t in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded,
                        size: 16, color: AppColors.success),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        t,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 1.5)),
      ),
      child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
    );
  }
}

// ─────────────────────────────────────────────────────────── Progress ────────

class _Progress extends StatelessWidget {
  const _Progress({
    super.key,
    required this.state,
    required this.personImageUrl,
  });

  final TryOnState state;
  final String personImageUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: SizedBox(
                width: 230,
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: personImageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const LoadingShimmer(
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: BorderRadius.zero,
                      ),
                      errorWidget: (_, _, _) =>
                          const ColoredBox(color: AppColors.mist),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x6615102A), Color(0xCC15102A)],
                        ),
                      ),
                    ),
                    const Center(
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            const _ProgressText(),
          ],
        ),
      ),
    );
  }
}

/// Cycles through futuristic rendering phrases (redesign spec).
class _ProgressText extends StatefulWidget {
  const _ProgressText();

  @override
  State<_ProgressText> createState() => _ProgressTextState();
}

class _ProgressTextState extends State<_ProgressText> {
  int _i = 0;
  late final _ticker = Stream<int>.periodic(
    const Duration(milliseconds: 1600),
    (i) => i,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phrases = [
      l10n.tryOnProgressFitting,
      l10n.tryOnProgressMatching,
      l10n.tryOnProgressRendering,
    ];
    return StreamBuilder<int>(
      stream: _ticker,
      builder: (context, snapshot) {
        _i = (snapshot.data ?? 0) % phrases.length;
        return AnimatedSwitcher(
          duration: AppMotion.base,
          child: Text(
            phrases[_i],
            key: ValueKey(_i),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────── Result ──────────

class _Result extends ConsumerStatefulWidget {
  const _Result({
    super.key,
    required this.job,
    required this.personImageUrl,
    required this.onAnother,
  });

  final TryOnJob job;
  final String personImageUrl;
  final VoidCallback onAnother;

  @override
  ConsumerState<_Result> createState() => _ResultState();
}

class _ResultState extends ConsumerState<_Result> {
  bool _showBefore = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final resultUrl = widget.job.resultImageUrl ?? widget.personImageUrl;
    final shownUrl = _showBefore ? widget.personImageUrl : resultUrl;
    final saved = ref.watch(savedLooksProvider).contains(widget.job.jobId);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        bottomNavClearance(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: CachedNetworkImage(
                    imageUrl: shownUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: AppMotion.slow,
                    placeholder: (_, _) => const LoadingShimmer(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: BorderRadius.zero,
                    ),
                    errorWidget: (_, _, _) =>
                        const ColoredBox(color: AppColors.mist),
                  ),
                ),
              ),
              Positioned(
                top: AppSpace.sm,
                left: AppSpace.sm,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.scrim,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    _showBefore ? l10n.tryOnBefore : l10n.tryOnAfter,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text(l10n.tryOnResultTitle, style: text.headlineSmall),
          const SizedBox(height: AppSpace.xs),
          Text(l10n.tryOnResultStubNote, style: text.bodySmall),
          const SizedBox(height: AppSpace.lg),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              _ResultAction(
                icon: saved ? Icons.bookmark : Icons.bookmark_border,
                label: l10n.tryOnSaveLook,
                highlight: saved,
                onTap: () {
                  ref
                      .read(savedLooksProvider.notifier)
                      .add(widget.job.jobId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.tryOnLookSaved)),
                  );
                },
              ),
              _ResultAction(
                icon: Icons.compare_arrows_rounded,
                label: l10n.tryOnCompare,
                onTap: () => setState(() => _showBefore = !_showBefore),
              ),
              _ResultAction(
                icon: Icons.add_a_photo_outlined,
                label: l10n.tryOnPostCommunity,
                onTap: () => context.push(AppRoute.socialCompose),
              ),
              _ResultAction(
                icon: Icons.ios_share_rounded,
                label: l10n.tryOnShare,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.tryOnShareComingSoon)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          PrimaryButton(
            label: l10n.tryOnTryAnother,
            icon: Icons.refresh_rounded,
            onPressed: widget.onAnother,
          ),
        ],
      ),
    );
  }
}

class _ResultAction extends StatelessWidget {
  const _ResultAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    final color = highlight ? AppColors.accent : AppColors.graphite;
    return Material(
      color: highlight ? AppColors.accentSoft : Theme.of(context).colorScheme.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.mist),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: highlight ? AppColors.accent : AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── Failure ─────────

class _Failure extends StatelessWidget {
  const _Failure({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onUpgrade,
    this.isInsufficientCredits = false,
    this.isModerationBlocked = false,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onUpgrade;
  final bool isInsufficientCredits;
  final bool isModerationBlocked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (isModerationBlocked) {
      return ErrorState(
        title: l10n.tryOnBlockedTitle,
        message: l10n.tryOnBlockedMessage,
        onRetry: onRetry,
        retryLabel: l10n.tryOnTryAnother,
      );
    }
    if (!isInsufficientCredits) {
      return ErrorState(
        title: l10n.tryOnErrorTitle,
        message: message,
        onRetry: onRetry,
        retryLabel: l10n.commonRetry,
      );
    }

    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 56, color: AppColors.accent),
            const SizedBox(height: AppSpace.md),
            Text(message, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.lg),
            PrimaryButton(
              label: l10n.paywallSeePlans,
              icon: Icons.auto_awesome,
              onPressed: onUpgrade,
            ),
            const SizedBox(height: AppSpace.sm),
            TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
          ],
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
      child: Padding(
        // Sit safely above the floating nav (spec): never overlap it.
        padding: EdgeInsets.fromLTRB(
          AppSpace.md,
          AppSpace.md,
          AppSpace.md,
          bottomNavClearance(context),
        ),
        child: child,
      ),
    );
  }
}
