import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/outfit.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../outfits/outfit_providers.dart';
import 'social_providers.dart';

/// Share a look to the community (CLAUDE.md §1 pillar 4). Posts one of the
/// user's saved outfits (its cover image + a caption) — no new upload path, and
/// the backend moderates the image before it goes public (§19).
class ComposePostScreen extends ConsumerStatefulWidget {
  const ComposePostScreen({super.key});

  @override
  ConsumerState<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends ConsumerState<ComposePostScreen> {
  final _caption = TextEditingController();
  String? _selectedId;
  bool _sharing = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share(Outfit outfit) async {
    if (_sharing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _sharing = true);
    try {
      final caption = _caption.text.trim();
      await ref
          .read(socialRepositoryProvider)
          .createPost(
            caption: caption.isEmpty ? null : caption,
            imageUrl: outfit.coverImageUrl,
            outfitId: outfit.id,
          );
      await ref.read(analyticsProvider).track(AnalyticsEvents.postCreated);
      await ref.read(feedProvider.notifier).refresh();
      if (mounted) {
        _snack(l10n.composeShared);
        context.pop();
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      _snack(
        error.code == ApiErrorCode.moderationBlocked
            ? l10n.composeBlocked
            : l10n.composeError,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final outfits = ref.watch(outfitsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.composeTitle)),
      body: SafeArea(
        child: outfits.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            title: l10n.composeError,
            onRetry: () => ref.invalidate(outfitsProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.style_outlined,
                title: l10n.composeNoOutfitsTitle,
                message: l10n.composeNoOutfits,
                actionLabel: l10n.outfitsCreate,
                onAction: () => context.push(AppRoute.outfitsCreate),
              );
            }
            final selected = _selectedId == null
                ? null
                : list.firstWhere((o) => o.id == _selectedId);
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    children: [
                      TextField(
                        controller: _caption,
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          labelText: l10n.composeCaptionLabel,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text(l10n.composePickOutfit, style: text.titleMedium),
                      const SizedBox(height: AppSpace.md),
                      _OutfitPicker(
                        outfits: list,
                        selectedId: _selectedId,
                        onSelect: (id) => setState(() => _selectedId = id),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: PrimaryButton(
                      label: l10n.composeShare,
                      icon: Icons.send_rounded,
                      isLoading: _sharing,
                      onPressed: selected == null
                          ? null
                          : () => _share(selected),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OutfitPicker extends StatelessWidget {
  const _OutfitPicker({
    required this.outfits,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Outfit> outfits;
  final String? selectedId;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpace.md,
        crossAxisSpacing: AppSpace.md,
        childAspectRatio: 0.66,
      ),
      itemCount: outfits.length,
      itemBuilder: (context, i) {
        final outfit = outfits[i];
        final name = (outfit.name?.trim().isNotEmpty ?? false)
            ? outfit.name!.trim()
            : l10n.outfitsUntitled;
        final isSelected = outfit.id == selectedId;
        return Stack(
          children: [
            OutfitTile(
              imageUrl: outfit.coverImageUrl ?? '',
              label: name,
              onTap: () => onSelect(outfit.id),
            ),
            if (isSelected)
              Positioned(
                top: AppSpace.sm,
                right: AppSpace.sm,
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(AppSpace.xs),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
