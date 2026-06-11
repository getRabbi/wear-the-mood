import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/stylist_suggestion.dart';
import '../../data/models/wardrobe_item.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'stylist_controller.dart';
import 'stylist_state.dart';

/// The daily stylist — "what do I wear today?" (CLAUDE.md §1, pillar 3). Asks
/// the backend to pick an outfit from the user's own closet (+ weather + taste);
/// handles all four states (§4.3). The AI runs server-side (§11).
class StylistScreen extends ConsumerWidget {
  const StylistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(stylistControllerProvider);
    final controller = ref.read(stylistControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.stylistAppBarTitle)),
      body: SafeArea(
        child: switch (state) {
          StylistIdle() => _Intro(onStyleMe: controller.styleMe),
          StylistLoading() => _LoadingView(label: l10n.stylistLoading),
          StylistFailure(:final message) => ErrorState(
            title: l10n.stylistErrorTitle,
            message: message,
            onRetry: controller.styleMe,
          ),
          StylistSuccess(:final suggestion) => suggestion.isEmpty
              ? EmptyState(
                  icon: Icons.checkroom_outlined,
                  title: l10n.stylistEmptyTitle,
                  message: l10n.stylistEmptyMessage,
                  actionLabel: l10n.wardrobeAdd,
                  onAction: () => context.push(AppRoute.wardrobeAdd),
                )
              : _SuggestionView(
                  suggestion: suggestion,
                  onStyleAgain: controller.styleMe,
                ),
        },
      ),
    );
  }
}

/// Idle state: explain the daily stylist and invite the first query.
class _Intro extends StatelessWidget {
  const _Intro({required this.onStyleMe});

  final VoidCallback onStyleMe;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            color: AppColors.accent,
            size: 40,
          ),
          const SizedBox(height: AppSpace.md),
          Text(l10n.stylistIntroTitle, style: text.displaySmall),
          const SizedBox(height: AppSpace.sm),
          Text(l10n.stylistIntroBody, style: text.bodyMedium),
          const SizedBox(height: AppSpace.xl),
          PrimaryButton(
            label: l10n.stylistStyleMe,
            icon: Icons.auto_awesome,
            onPressed: onStyleMe,
          ),
        ],
      ),
    );
  }
}

/// Loading state: a shimmer card plus a short, honest progress label.
class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LoadingShimmer(
            width: double.infinity,
            height: 200,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Content state: the suggested look — title, rationale and the chosen pieces.
class _SuggestionView extends StatelessWidget {
  const _SuggestionView({required this.suggestion, required this.onStyleAgain});

  final StylistSuggestion suggestion;
  final VoidCallback onStyleAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.xl,
      ),
      children: [
        Text(suggestion.title, style: text.displaySmall),
        const SizedBox(height: AppSpace.sm),
        Text(suggestion.rationale, style: text.bodyMedium),
        const SizedBox(height: AppSpace.lg),
        _PieceRow(items: suggestion.items),
        const SizedBox(height: AppSpace.xl),
        PrimaryButton(
          label: l10n.stylistStyleAgain,
          icon: Icons.refresh,
          onPressed: onStyleAgain,
        ),
      ],
    );
  }
}

class _PieceRow extends StatelessWidget {
  const _PieceRow({required this.items});

  final List<WardrobeItem> items;

  static const _height = 200.0;
  static const _itemWidth = 150.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
        itemBuilder: (context, i) =>
            SizedBox(width: _itemWidth, child: _PieceTile(item: items[i])),
      ),
    );
  }
}

class _PieceTile extends StatelessWidget {
  const _PieceTile({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);
    return Semantics(
      label: item.title ?? item.category,
      image: true,
      child: ClipRRect(
        borderRadius: radius,
        child: CachedNetworkImage(
          imageUrl: item.displayImageUrl ?? '',
          fit: BoxFit.cover,
          fadeInDuration: AppMotion.base,
          placeholder: (_, _) => const LoadingShimmer(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.zero,
          ),
          errorWidget: (_, _, _) => const ColoredBox(color: AppColors.mist),
        ),
      ),
    );
  }
}
