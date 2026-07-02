import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/share/share_service.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/ai_job.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/ai_studio_repository.dart';
import '../../data/repositories/credits_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../social/post_image_service.dart';

/// Opens the Catalog Model Shot flow for [item] (Pro/Pro Max). The caller gates
/// free users to the paywall before calling this.
Future<void> showCatalogModelSheet(BuildContext context, WardrobeItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _CatalogModelSheet(item: item),
  );
}

const _styles = [
  ('studio', 'catalogStyleStudio'),
  ('streetwear', 'catalogStyleStreetwear'),
  ('modest', 'catalogStyleModest'),
  ('luxury', 'catalogStyleLuxury'),
  ('cropped_face', 'catalogStyleCropped'),
];

String _styleLabel(AppLocalizations l10n, String key) => switch (key) {
  'studio' => l10n.catalogStyleStudio,
  'streetwear' => l10n.catalogStyleStreetwear,
  'modest' => l10n.catalogStyleModest,
  'luxury' => l10n.catalogStyleLuxury,
  'cropped_face' => l10n.catalogStyleCropped,
  _ => key,
};

enum _Phase { form, generating, result, failed }

class _CatalogModelSheet extends ConsumerStatefulWidget {
  const _CatalogModelSheet({required this.item});

  final WardrobeItem item;

  @override
  ConsumerState<_CatalogModelSheet> createState() => _CatalogModelSheetState();
}

class _CatalogModelSheetState extends ConsumerState<_CatalogModelSheet> {
  String _style = 'studio';
  bool _hd = false;
  _Phase _phase = _Phase.form;
  AiJob? _result;
  String? _error;
  bool _sharing = false;

  Future<void> _generate() async {
    final l10n = AppLocalizations.of(context);
    final credits = ref.read(creditsProvider).asData?.value;
    final cost = _hd ? (credits?.hdCost ?? 4) : (credits?.stdCost ?? 1);

    final ok = await showConfirmSheet(
      context,
      icon: Icons.auto_awesome,
      title: l10n.catalogTitle,
      message: l10n.aiCreditConfirm(cost),
      confirmLabel: l10n.catalogGenerateCta(cost),
      cancelLabel: l10n.commonCancel,
    );
    if (!ok || !mounted) return;

    setState(() => _phase = _Phase.generating);
    final repo = ref.read(aiStudioRepositoryProvider);
    ref.read(analyticsProvider).track(AnalyticsEvents.catalogShotStarted);
    try {
      var job = await repo.catalogModel(widget.item.id, style: _style, hd: _hd);
      ref.invalidate(creditsProvider); // reserved at submit
      final deadline = DateTime.now().add(const Duration(seconds: 180));
      while (!job.status.isTerminal) {
        if (DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(seconds: 2));
        job = await repo.getJob(job.jobId);
      }
      if (!mounted) return;
      ref.invalidate(creditsProvider);
      if (job.status.isDone) {
        ref.invalidate(generatedImagesProvider);
        setState(() {
          _result = job;
          _phase = _Phase.result;
        });
      } else {
        setState(() {
          _error = job.error ?? l10n.catalogError;
          _phase = _Phase.failed;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ref.invalidate(creditsProvider);
      setState(() {
        _error = e.message;
        _phase = _Phase.failed;
      });
    }
  }

  Future<void> _share() async {
    final url = _result?.outputUrl;
    if (url == null || url.isEmpty || _sharing) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sharing = true);
    try {
      final bytes =
          await ref.read(postImageServiceProvider).downloadImageBytes(url);
      // HD shares clean; standard carries the brand watermark (paywall promise).
      await ref
          .read(shareServiceProvider)
          .shareImageBytes(bytes, text: l10n.postShareText, watermark: !_hd);
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.shareFailed)));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpace.lg,
          right: AppSpace.lg,
          top: AppSpace.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.lg,
        ),
        child: switch (_phase) {
          _Phase.form => _form(context),
          _Phase.generating => _generating(context),
          _Phase.result => _resultView(context),
          _Phase.failed => _failure(context),
        },
      ),
    );
  }

  Widget _form(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final credits = ref.watch(creditsProvider).asData?.value;
    final hdAllowed = credits?.hdAllowed ?? false;
    final cost = _hd ? (credits?.hdCost ?? 4) : (credits?.stdCost ?? 1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.catalogTitle, style: text.headlineSmall),
        const SizedBox(height: AppSpace.xs),
        Text(l10n.catalogSubtitle, style: text.bodySmall),
        const SizedBox(height: AppSpace.lg),
        Text(l10n.catalogStyleLabel, style: text.labelLarge),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final (key, _) in _styles)
              AppChip(
                label: _styleLabel(l10n, key),
                selected: _style == key,
                onTap: () => setState(() => _style = key),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        Text(l10n.catalogQualityLabel, style: text.labelLarge),
        const SizedBox(height: AppSpace.sm),
        Row(
          children: [
            Expanded(
              child: _QualityCard(
                label: l10n.catalogQualityStandard,
                selected: !_hd,
                onTap: () => setState(() => _hd = false),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: _QualityCard(
                label: l10n.catalogQualityHd,
                selected: _hd,
                locked: !hdAllowed,
                onTap: () {
                  if (!hdAllowed) {
                    context.push(AppRoute.paywall);
                    return;
                  }
                  setState(() => _hd = true);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Text(l10n.aiUploadDisclaimer, style: text.bodySmall?.copyWith(fontSize: 11.5)),
        const SizedBox(height: AppSpace.lg),
        PrimaryButton(
          label: l10n.catalogGenerateCta(cost),
          icon: Icons.auto_awesome,
          onPressed: _generate,
        ),
      ],
    );
  }

  Widget _generating(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
      child: PremiumAILoader(label: l10n.catalogGenerating),
    );
  }

  Widget _resultView(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final url = _result?.outputUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (url != null && url.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AspectRatio(
              aspectRatio: 3 / 4,
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
          ),
        const SizedBox(height: AppSpace.md),
        Text(l10n.catalogResultTitle, style: text.headlineSmall),
        const SizedBox(height: AppSpace.xs),
        Text(l10n.catalogSavedNote, style: text.bodySmall),
        const SizedBox(height: AppSpace.lg),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: l10n.aiLooksShare,
                icon: _sharing ? Icons.hourglass_top_rounded : Icons.ios_share_rounded,
                onPressed: _share,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: PrimaryButton(
                label: l10n.commonDone,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _failure(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
          const SizedBox(height: AppSpace.md),
          Text(
            _error ?? l10n.catalogError,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: l10n.commonRetry,
                  onPressed: () => setState(() => _phase = _Phase.form),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: PrimaryButton(
                  label: l10n.commonDone,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({
    required this.label,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.glassBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.accent : AppColors.ink,
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 4),
              const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.graphite),
            ],
          ],
        ),
      ),
    );
  }
}
