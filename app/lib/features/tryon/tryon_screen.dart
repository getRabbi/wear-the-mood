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
import '../credits/credits_chip.dart';
import '../profile/avatar_service.dart';
import '../wardrobe/wardrobe_providers.dart';
import 'sample_garments.dart';
import 'tryon_controller.dart';
import 'tryon_state.dart';

/// The try-on hook (CLAUDE.md §7, §17). Pick a piece, watch it process, reveal
/// the result. Handles all four states (§4.3) with a smooth cross-fade. Uses
/// preset garments + a stand-in person until image upload (§8) lands.
class TryOnScreen extends ConsumerStatefulWidget {
  const TryOnScreen({super.key});

  @override
  ConsumerState<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends ConsumerState<TryOnScreen> {
  WardrobeItem? _selected;

  Future<void> _start() async {
    final garment = _selected;
    // Prefer the background-removed cutout for the garment; fall back to the
    // original photo if the cutout hasn't been generated yet (§2.2).
    final garmentUrl = garment?.cutoutUrl ?? garment?.imageUrl;
    if (garmentUrl == null) return;
    // Render on the user's own avatar (signed URL, §10) when set; otherwise a
    // stand-in model so the hook still demos (§17).
    final person =
        ref.read(avatarSignedUrlProvider).asData?.value ?? samplePersonImageUrl;
    await ref
        .read(tryOnControllerProvider.notifier)
        .start(personImageUrl: person, garmentImageUrl: garmentUrl);
  }

  void _another() {
    setState(() => _selected = null);
    ref.read(tryOnControllerProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(tryOnControllerProvider);
    final avatarUrl = ref.watch(avatarSignedUrlProvider).asData?.value;
    final personImageUrl = avatarUrl ?? samplePersonImageUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tryOnAppBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: l10n.tryonHistoryTitle,
            onPressed: () => context.push(AppRoute.tryonHistory),
          ),
          const Padding(
            padding: EdgeInsets.only(right: AppSpace.md),
            child: Center(child: CreditsChip()),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: AppMotion.base,
          switchInCurve: AppMotion.easing,
          child: switch (state) {
            TryOnIdle() => _Picker(
              key: const ValueKey('picker'),
              selected: _selected,
              hasAvatar: avatarUrl != null,
              onSelect: (g) => setState(() => _selected = g),
              onStart: _start,
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

class _Picker extends ConsumerWidget {
  const _Picker({
    super.key,
    required this.selected,
    required this.hasAvatar,
    required this.onSelect,
    required this.onStart,
    required this.onSetupAvatar,
    required this.onAddClothes,
  });

  final WardrobeItem? selected;
  final bool hasAvatar;
  final ValueChanged<WardrobeItem> onSelect;
  final VoidCallback onStart;
  final VoidCallback onSetupAvatar;
  final VoidCallback onAddClothes;

  static const _grid = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    mainAxisSpacing: AppSpace.md,
    crossAxisSpacing: AppSpace.md,
    childAspectRatio: 0.66,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final canSpend = ref
        .watch(creditsProvider)
        .maybeWhen(data: (c) => c.canSpend, orElse: () => true);
    final wardrobe = ref.watch(wardrobeItemsProvider);

    final header = SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.sm,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tryOnPickTitle, style: text.headlineSmall),
            const SizedBox(height: AppSpace.xs),
            Text(l10n.tryOnPickSubtitle, style: text.bodySmall),
            if (!hasAvatar) ...[
              const SizedBox(height: AppSpace.md),
              _AvatarPrompt(onSetup: onSetupAvatar),
            ],
          ],
        ),
      ),
    );

    // The garment picker is the user's own wardrobe (§1 — try on what you own).
    final body = wardrobe.when(
      loading: () => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        sliver: SliverGrid(
          gridDelegate: _grid,
          delegate: SliverChildBuilderDelegate(
            (_, _) => LoadingShimmer(
              width: double.infinity,
              height: double.infinity,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            childCount: 4,
          ),
        ),
      ),
      error: (_, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorState(
          title: l10n.wardrobeErrorTitle,
          onRetry: () => ref.invalidate(wardrobeItemsProvider),
          retryLabel: l10n.commonRetry,
        ),
      ),
      data: (items) => items.isEmpty
          ? SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.checkroom_outlined,
                title: l10n.tryOnNoGarmentsTitle,
                message: l10n.tryOnNoGarmentsMessage,
                actionLabel: l10n.tryOnAddClothes,
                onAction: onAddClothes,
              ),
            )
          : SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              sliver: SliverGrid(
                gridDelegate: _grid,
                delegate: SliverChildBuilderDelegate((context, i) {
                  final item = items[i];
                  return _GarmentTile(
                    item: item,
                    selected: selected?.id == item.id,
                    onTap: () => onSelect(item),
                  );
                }, childCount: items.length),
              ),
            ),
    );

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              header,
              body,
              const SliverToBoxAdapter(child: SizedBox(height: AppSpace.lg)),
            ],
          ),
        ),
        _BottomBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!canSpend) ...[
                Text(
                  l10n.tryOnOutOfCredits,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: AppColors.danger),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              PrimaryButton(
                label: l10n.tryOnCta,
                icon: Icons.auto_awesome,
                onPressed: (selected != null && canSpend) ? onStart : null,
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

class _GarmentTile extends StatelessWidget {
  const _GarmentTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final WardrobeItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: item.title,
      child: Stack(
        children: [
          OutfitTile(
            imageUrl: item.displayImageUrl ?? '',
            label: item.title,
            onTap: onTap,
          ),
          if (selected)
            const Positioned(
              top: AppSpace.sm,
              right: AppSpace.sm,
              child: _CheckBadge(),
            ),
        ],
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
    );
  }
}

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
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final processing =
        state is TryOnPolling &&
        (state as TryOnPolling).job.status == TryOnStatus.processing;
    final label = processing ? l10n.tryOnProcessing : l10n.tryOnQueued;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: SizedBox(
                width: 220,
                height: 290,
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
                      decoration: BoxDecoration(color: Color(0x33000000)),
                    ),
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(label, style: text.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final imageUrl = job.resultImageUrl ?? personImageUrl;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
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
          const SizedBox(height: AppSpace.lg),
          Text(l10n.tryOnResultTitle, style: text.headlineSmall),
          const SizedBox(height: AppSpace.xs),
          Text(l10n.tryOnResultStubNote, style: text.bodySmall),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: l10n.tryOnTryAnother,
                  icon: Icons.refresh_rounded,
                  onPressed: onAnother,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.tryOnShareComingSoon)),
                ),
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(l10n.tryOnShare),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
      // Rejected input image (§19) — guide the user to pick a different one.
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

    // Out of credits -> offer the paywall instead of a bare retry (§18).
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
