import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/router/routes.dart';
import '../../data/repositories/credits_repository.dart';
import '../../features/collections/local_collections.dart';
import '../../features/social/post_image_service.dart';
import '../../features/tryon/save_look_service.dart';
import '../../features/tryon/tryon_controller.dart';
import '../../features/tryon/tryon_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../paywall/wtm_topup_sheet.dart';
import '../widgets/widgets.dart';
import 'wtm_mirror_adjust.dart';

/// Result (§3.5, P4) — the REAL render full-bleed, with the §8 action bar:
/// Save Look (durable re-upload via [SaveLookService], idempotent), Adjust
/// (board 06 → edits come back applied, §2), Retry (back to Step 3), Share
/// (OS sheet; adjusted pixels when edits are live). The image loads
/// progressively (shimmer → fade-in). NOTE: the spec's "low-res → Real-ESRGAN
/// swap" has no existing backend pipeline — HD quality is chosen at submit
/// (`hd`), so this renders the one real result URL (flagged for review).
class WtmMirrorResultScreen extends ConsumerStatefulWidget {
  const WtmMirrorResultScreen({super.key});

  @override
  ConsumerState<WtmMirrorResultScreen> createState() =>
      _WtmMirrorResultScreenState();
}

class _WtmMirrorResultScreenState extends ConsumerState<WtmMirrorResultScreen> {
  final _captureKey = GlobalKey();
  var _adjustments = const WtmAdjustments();
  // Split busy states (mobile QA #2): saving/sharing each disable ONLY their
  // own button — Adjust / Retry / Back stay usable the whole time.
  bool _saving = false;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(tryOnControllerProvider);
    final job = state is TryOnSuccess ? state.job : null;
    final imageUrl = job?.resultImageUrl;
    final spendable = ref.watch(creditsProvider).asData?.value.totalAvailable;
    // Watch the STATE (not the notifier) so the button flips to "Saved" the
    // moment the record lands.
    final saved =
        job != null &&
        ref.watch(savedLookRecordsProvider).any((l) => l.id == job.jobId);

    if (job == null || imageUrl == null) {
      // Entered without a fresh render (deep link / stale stack).
      return WtmPage(
        fullBleed: true,
        title: l10n.wtmMirrorResultTitle,
        children: [
          const SizedBox(height: WtmSpace.s22),
          WtmEmptyState(
            glyph: WtmGlyph.sparkle,
            title: l10n.wtmMirrorNoResultTitle,
            message: l10n.wtmMirrorNoResultMessage,
            ctaLabel: l10n.wtmMirrorTitle,
            onCta: () => context.go(AppRoute.wtmMirror),
          ),
        ],
      );
    }

    return WtmScaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The render — captured (with live adjustments) for save/share.
          RepaintBoundary(
            key: _captureKey,
            child: ColorFiltered(
              colorFilter: _adjustments.toColorFilter(),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                cacheKey: stableImageCacheKey(imageUrl),
                fit: BoxFit.cover,
                fadeInDuration: WtmMotion.base,
                placeholder: (_, _) => const Stack(
                  fit: StackFit.expand,
                  children: [
                    AuroraBox(
                      borderRadius: BorderRadius.zero,
                      border: false,
                      vignette: true,
                    ),
                    LoadingShimmer(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: BorderRadius.zero,
                    ),
                  ],
                ),
                errorWidget: (_, _, _) => const AuroraBox(
                  borderRadius: BorderRadius.zero,
                  border: false,
                  vignette: true,
                ),
              ),
            ),
          ),
          // Legibility scrim behind the action bar.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 220,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x0008060F), Color(0xE608060F)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(WtmSpace.screenH),
              child: Column(
                children: [
                  Row(
                    children: [
                      WtmIconButton(
                        WtmGlyph.back,
                        semanticLabel: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        onTap: () => _leave(context),
                      ),
                      const Spacer(),
                      GoldPill(
                        label: '${spendable ?? '—'}',
                        icon: const WtmIcon(
                          WtmGlyph.coin,
                          size: 12,
                          color: WtmColors.gold,
                        ),
                        onTap: () => showTopUpSheet(context),
                      ),
                    ],
                  ),
                  const Spacer(),
                  GradientCta(
                    label: _saving
                        ? l10n.wtmMirrorSaving
                        : saved
                        ? l10n.wtmMirrorSaved
                        : l10n.wtmMirrorSaveLook,
                    icon: _saving
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: WtmColors.ctaText,
                            ),
                          )
                        : WtmIcon(
                            saved ? WtmGlyph.check : WtmGlyph.bookmark,
                            size: 15,
                            color: WtmColors.ctaText,
                          ),
                    onPressed: _saving || saved
                        ? null
                        : () => _save(l10n, job.jobId, imageUrl),
                  ),
                  const SizedBox(height: WtmSpace.s10),
                  Row(
                    children: [
                      Expanded(
                        child: GhostButton(
                          label: l10n.wtmMirrorAdjust,
                          onPressed: () => _adjust(context, imageUrl),
                        ),
                      ),
                      const SizedBox(width: WtmSpace.s10),
                      Expanded(
                        child: GhostButton(
                          label: l10n.wtmMirrorRetry,
                          onPressed: () => _leave(context),
                        ),
                      ),
                      const SizedBox(width: WtmSpace.s10),
                      Expanded(
                        child: GhostButton(
                          label: _sharing
                              ? l10n.wtmSharePreparing
                              : l10n.wtmMirrorShare,
                          onPressed: _sharing
                              ? null
                              : () => _share(l10n, imageUrl),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Back/Retry: return to Step 3 and clear the run so Generate is fresh.
  void _leave(BuildContext context) {
    ref.read(tryOnControllerProvider.notifier).reset();
    wtmPageBack(context);
  }

  Future<void> _adjust(BuildContext context, String imageUrl) async {
    final result = await context.push<WtmAdjustments>(
      AppRoute.wtmMirrorAdjust,
      extra: WtmAdjustArgs(imageUrl: imageUrl, initial: _adjustments),
    );
    if (result != null && mounted) setState(() => _adjustments = result);
  }

  /// The pixels to persist/share: the raw render, or the adjusted capture
  /// when edits are live.
  Future<Uint8List?> _pixels(String imageUrl) async {
    if (_adjustments.isNeutral) {
      return ref.read(postImageServiceProvider).downloadImageBytes(imageUrl);
    }
    final boundary =
        _captureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(
      pixelRatio: MediaQuery.of(context).devicePixelRatio,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _save(
    AppLocalizations l10n,
    String jobId,
    String imageUrl,
  ) async {
    setState(() => _saving = true);
    try {
      if (_adjustments.isNeutral) {
        await ref
            .read(saveLookServiceProvider)
            .saveFromUrl(id: jobId, url: imageUrl);
      } else {
        final bytes = await _pixels(imageUrl);
        if (bytes == null) throw StateError('capture failed');
        await ref
            .read(saveLookServiceProvider)
            .saveBytes(id: jobId, bytes: bytes);
      }
      if (mounted) wtmSnack(context, l10n.wtmMirrorSaved);
    } catch (_) {
      // The button returns to "Save Look" — tapping again IS the retry.
      if (mounted) wtmSnack(context, l10n.wtmMirrorSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share(AppLocalizations l10n, String imageUrl) async {
    setState(() => _sharing = true);
    try {
      final bytes = await _pixels(imageUrl);
      if (bytes == null) throw StateError('capture failed');
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: 'wear-the-mood-look.png',
        ),
      ], text: l10n.wtmMirrorShareText);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.wtmMirrorSaveFailed);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

/// Route extra for the adjust editor.
class WtmAdjustArgs {
  const WtmAdjustArgs({required this.imageUrl, required this.initial});

  final String imageUrl;
  final WtmAdjustments initial;
}
