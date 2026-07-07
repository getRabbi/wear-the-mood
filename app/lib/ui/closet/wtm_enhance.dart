import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/ai_job.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/ai_studio_repository.dart';
import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_add_garment_screen.dart' show WtmGoldProgress;

/// AI Enhance plumbing shared by the Add-Garment flow and the garment detail
/// (mobile QA #5/#6). The job — not just the wardrobe item — is polled, so a
/// failure (e.g. the AI studio being unavailable) surfaces with the server's
/// real message instead of silently ending as "just background removal".

/// Confirm the credit spend before charging (§18 — never silent).
Future<bool> confirmWtmEnhanceSpend(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  final cost = ref.read(creditsProvider).asData?.value.stdCost ?? 1;
  return wtmConfirmDialog(
    context,
    title: l10n.addPieceEnhanceTitle,
    message: l10n.aiCreditConfirm(cost),
    confirmLabel: l10n.addPieceEnhanceCta(cost),
  );
}

/// Polls the enhance job to a terminal state (same cadence as the shipped add
/// flow). On timeout the job keeps finishing server-side; the last-seen state
/// is returned so the caller can reveal honestly.
Future<AiJob> pollWtmAiJob(
  WidgetRef ref,
  AiJob job, {
  Duration timeout = const Duration(seconds: 90),
  Duration interval = const Duration(milliseconds: 1200),
}) async {
  final deadline = DateTime.now().add(timeout);
  var latest = job;
  while (!latest.status.isTerminal && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(interval);
    try {
      latest = await ref.read(aiStudioRepositoryProvider).getJob(job.jobId);
    } catch (_) {
      // Transient blip — keep polling until the deadline.
    }
  }
  return latest;
}

/// Runs the full enhance on an existing closet piece behind a blocking WTM
/// dialog: start job → poll → refresh closet/credits. Resolves with the
/// refreshed item on success, null on failure/decline (errors are shown here).
/// The caller must have already confirmed the spend + the Pro gate.
Future<WardrobeItem?> runWtmEnhanceDialog(
  BuildContext context,
  WidgetRef ref, {
  required WardrobeItem item,
}) async {
  final l10n = AppLocalizations.of(context);

  AiJob job;
  try {
    job = await ref.read(aiStudioRepositoryProvider).enhanceItem(item.id);
    ref.read(analyticsProvider).track(AnalyticsEvents.aiEnhanceStarted);
    ref.invalidate(creditsProvider); // the reserve shows immediately
  } on ApiException catch (e) {
    if (context.mounted) wtmSnack(context, e.message);
    return null;
  }

  if (!context.mounted) return null;
  final result = await showDialog<AiJob>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xF2050308),
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: _WtmEnhanceDialog(item: item, job: job),
    ),
  );

  // Reflect whatever happened (enhanced cover / cleared flag) + final balance.
  await ref.read(wardrobeItemsProvider.notifier).refresh();
  ref.invalidate(creditsProvider);

  if (result == null) return null;
  if (!result.status.isDone) {
    if (context.mounted) {
      wtmSnack(context, result.error ?? l10n.wardrobeEnhanceError);
    }
    return null;
  }
  WardrobeItem? refreshed;
  try {
    for (final i in await ref.read(wardrobeRepositoryProvider).getItems()) {
      if (i.id == item.id) {
        refreshed = i;
        break;
      }
    }
  } catch (_) {
    refreshed = null; // closet refresh already happened; show what we have
  }
  if (context.mounted) wtmSnack(context, l10n.wtmEnhanceDone);
  return refreshed ?? item;
}

/// The blocking progress dialog: the piece under a sweep, the gold progress
/// line, and the enhancing status. Pops with the terminal job.
class _WtmEnhanceDialog extends ConsumerStatefulWidget {
  const _WtmEnhanceDialog({required this.item, required this.job});

  final WardrobeItem item;
  final AiJob job;

  @override
  ConsumerState<_WtmEnhanceDialog> createState() => _WtmEnhanceDialogState();
}

class _WtmEnhanceDialogState extends ConsumerState<_WtmEnhanceDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final terminal = await pollWtmAiJob(ref, widget.job);
    if (mounted) Navigator.of(context).pop(terminal);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: WtmColors.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 34, vertical: 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WtmRadius.card),
        side: const BorderSide(color: WtmColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(WtmSpace.s18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 180,
              child: FabricTile(
                imageUrl: widget.item.displayImageUrl,
                swatchIndex: widget.item.id.hashCode.abs() % 8,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: WtmSpace.s14),
            Text(
              l10n.wtmEnhanceProgress,
              textAlign: TextAlign.center,
              style: WtmType.h2.copyWith(fontSize: 17),
            ),
            const SizedBox(height: WtmSpace.s6),
            Text(
              l10n.addPieceProcessingHint,
              textAlign: TextAlign.center,
              style: WtmType.micro,
            ),
            const SizedBox(height: WtmSpace.s14),
            const WtmGoldProgress(),
          ],
        ),
      ),
    );
  }
}
