import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/share/share_service.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/generated_image.dart';
import '../../data/repositories/ai_studio_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../social/post_image_service.dart';

/// AI Looks — the user's saved AI-generated images (enhanced items + catalog
/// shots). Tap one to open the viewer with Report / Delete / Save / Share
/// (BUILD_PROMPT_PRO_PROMAX.md Phase 5).
class AiLooksScreen extends ConsumerWidget {
  const AiLooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final looks = ref.watch(generatedImagesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiLooksTitle)),
      body: SafeArea(
        child: looks.when(
          loading: () => GridView.count(
            padding: const EdgeInsets.all(AppSpace.lg),
            crossAxisCount: 2,
            mainAxisSpacing: AppSpace.md,
            crossAxisSpacing: AppSpace.md,
            childAspectRatio: 3 / 4,
            children: List.generate(
              4,
              (_) => const LoadingShimmer(width: double.infinity, height: double.infinity),
            ),
          ),
          error: (_, _) => ErrorState(
            title: l10n.aiLooksError,
            onRetry: () => ref.invalidate(generatedImagesProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.auto_awesome,
                title: l10n.aiLooksTitle,
                message: l10n.aiLooksEmpty,
              );
            }
            return GridView.count(
              padding: const EdgeInsets.all(AppSpace.lg),
              crossAxisCount: 2,
              mainAxisSpacing: AppSpace.md,
              crossAxisSpacing: AppSpace.md,
              childAspectRatio: 3 / 4,
              children: [
                for (final g in items)
                  _LookTile(
                    look: g,
                    onTap: () => _openViewer(context, g),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, GeneratedImage look) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _AiLookViewer(look: look)),
    );
  }
}

class _LookTile extends StatelessWidget {
  const _LookTile({required this.look, required this.onTap});

  final GeneratedImage look;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = look.outputUrl ?? '';
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
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

/// Fullscreen viewer with the four required actions.
class _AiLookViewer extends ConsumerStatefulWidget {
  const _AiLookViewer({required this.look});

  final GeneratedImage look;

  @override
  ConsumerState<_AiLookViewer> createState() => _AiLookViewerState();
}

class _AiLookViewerState extends ConsumerState<_AiLookViewer> {
  bool _busy = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share() async {
    final url = widget.look.outputUrl;
    if (url == null || url.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final bytes =
          await ref.read(postImageServiceProvider).downloadImageBytes(url);
      // Save goes through the OS sheet too (no gallery-saver dependency), where
      // "Save image / Save to Files" is available alongside sharing.
      await ref
          .read(shareServiceProvider)
          .shareImageBytes(bytes, text: l10n.postShareText);
    } catch (_) {
      _snack(l10n.shareFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showConfirmSheet(
      context,
      icon: Icons.delete_outline_rounded,
      title: l10n.aiLooksDelete,
      message: l10n.wardrobeDeleteBody,
      confirmLabel: l10n.aiLooksDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(aiStudioRepositoryProvider).deleteGenerated(widget.look.id);
      ref.invalidate(generatedImagesProvider);
      if (!mounted) return;
      _snack(l10n.aiLooksDeleted);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _report() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(aiStudioRepositoryProvider).reportGenerated(widget.look.id);
      _snack(l10n.aiLooksReported);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final url = widget.look.outputUrl ?? '';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: l10n.aiLooksReport,
            onPressed: _busy ? null : _report,
            icon: const Icon(Icons.flag_outlined),
          ),
          IconButton(
            tooltip: l10n.aiLooksDelete,
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, _) =>
                      const Center(child: CircularProgressIndicator()),
                  errorWidget: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, color: Colors.white54),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: l10n.aiLooksSave,
                      icon: Icons.download_rounded,
                      onPressed: _busy ? null : _share,
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: PrimaryButton(
                      label: l10n.aiLooksShare,
                      icon: Icons.ios_share_rounded,
                      onPressed: _busy ? null : _share,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
