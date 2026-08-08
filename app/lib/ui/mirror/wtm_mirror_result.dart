import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/router/routes.dart';
import '../../core/utils/link_launcher.dart';
import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/discover_repository.dart';
import '../../features/collections/local_collections.dart';
import '../../features/discover/application/product_details.dart';
import '../../features/discover/application/shopping_tryon.dart';
import '../../features/social/post_image_service.dart';
import '../../features/tryon/save_look_service.dart';
import '../../features/tryon/tryon_controller.dart';
import '../../features/tryon/tryon_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/utils/uuid.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
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

  // Shopping try-on only (§13). One key per screen, so a retry after a dropped
  // response replays the same click rather than logging a second one; a new key
  // is minted only once a click actually lands.
  String _clickKey = uuidV4();
  bool _opening = false;
  ShopFailure? _shopFailure;

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
    // Null for a closet render, which is the overwhelmingly common case and
    // must look exactly as it did before Phase 5 (§13 "existing non-shopping
    // Try-On still works").
    //
    // Prefers what the JOB persisted, so a render that outlived the process
    // that started it still knows what it was of.
    final source = ref.watch(resultShoppingSourceProvider);

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
                  // A shopping try-on ends at the store, so `Shop at Store`
                  // takes the primary slot and Save Look steps down a row
                  // (§13). A closet render is unchanged: it has nowhere to
                  // shop, and inventing a destination for it would be a lie.
                  if (source != null) ...[
                    if (_shopFailure != null) ...[
                      _ShopNote(
                        failure: _shopFailure!,
                        onRetry: _shopFailure == ShopFailure.unreachable
                            ? () => _shop(source)
                            : null,
                      ),
                      const SizedBox(height: WtmSpace.s10),
                    ],
                    GradientCta(
                      label: _opening
                          ? l10n.wtmShopOpeningStore
                          : l10n.wtmShopShopAtStore,
                      icon: const WtmIcon(
                        WtmGlyph.store,
                        size: 15,
                        color: WtmColors.ctaText,
                      ),
                      onPressed: _opening ? null : () => _shop(source),
                    ),
                    const SizedBox(height: WtmSpace.s10),
                    Row(
                      children: [
                        Expanded(
                          child: GhostButton(
                            label: _saving
                                ? l10n.wtmMirrorSaving
                                : saved
                                ? l10n.wtmMirrorSaved
                                : l10n.wtmMirrorSaveLook,
                            onPressed: _saving || saved
                                ? null
                                : () => _save(l10n, job.jobId, imageUrl),
                          ),
                        ),
                        const SizedBox(width: WtmSpace.s10),
                        Expanded(
                          // The way back to what was tried on — where the
                          // colours, sizes and alternatives already live, so
                          // §13's "try another colour" and "find similar" need
                          // no second copy of either (§26.12).
                          child: GhostButton(
                            label: l10n.wtmShopViewProduct,
                            onPressed: () => _openProduct(source),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: WtmSpace.s10),
                  ] else ...[
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
                  ],
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

  /// The result's way back to what was tried on (§13).
  ///
  /// A fresh Product Details rather than a pop, because the user reached this
  /// screen through the mirror flow — there is no product route underneath to
  /// return to, and the details screen refetches anyway, so the price shown
  /// after a render is current rather than whatever was cached before it.
  void _openProduct(ShoppingTryOnSource source) {
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.productOpen,
          properties: {
            DiscoverAnalyticsProps.productId: source.productId,
            DiscoverAnalyticsProps.feedPlacement: 'tryon_result',
          },
        );
    // `go`, not `push`.
    //
    // Product Details lives INSIDE the stateful shell; this screen is declared
    // outside it, because a render is full-bleed and must not carry the nav
    // bar. Pushing a shell route from above the shell asks go_router to mount
    // the shell a second time while the first is still alive, and the branch
    // navigator's GlobalKey is reserved twice:
    //
    //   'navigator.dart': Failed assertion: '!keyReservation.contains(key)'
    //
    // — a red screen on the one action the shopping try-on exists to enable.
    // `go` rebuilds the stack at the product instead of stacking onto it, so
    // the shell is mounted once and back lands on Discover with the product's
    // own Try On and Shop at Store still there. The render is not lost: it is
    // in Saved Looks, which restores this screen's shopping actions from the
    // job (§13).
    context.go(
      '${AppRoute.wtmProductPath(source.productId)}&from=tryon_result',
    );
  }

  /// Shop at Store, from the render (§13, §18).
  ///
  /// The same tracked-click contract Product Details uses: the app sends a
  /// product id and receives one destination the backend has already validated
  /// against the merchant's domain allow-list. Nothing about the URL is
  /// assembled here, and a failure keeps the user on their result.
  Future<void> _shop(ShoppingTryOnSource source) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _shopFailure = null;
    });
    try {
      final click = await ref
          .read(discoverRepositoryProvider)
          .click(
            source.productId,
            idempotencyKey: _clickKey,
            // Where this click came from, so the try-on-to-shop rate can be
            // separated from a click straight off a card.
            feedPlacement: 'tryon_result',
            campaignId: source.campaignId,
            trackingToken: source.trackingToken,
          );
      final opened = await ref.read(linkLauncherProvider).open(click.url);
      if (!mounted) return;
      if (!opened) {
        _trackShopFailure(
          source.productId,
          shopLaunchFailedCode,
          merchantId: click.merchant.id,
        );
        setState(() => _shopFailure = ShopFailure.unreachable);
        return;
      }
      ref
          .read(analyticsProvider)
          .track(
            AnalyticsEvents.affiliateClick,
            properties: {
              DiscoverAnalyticsProps.productId: source.productId,
              DiscoverAnalyticsProps.merchantId: click.merchant.id,
              DiscoverAnalyticsProps.feedPlacement: 'tryon_result',
              // Server-derived. On this path it should be true — the render the
              // user is looking at is the try-on — and reporting the SERVER's
              // answer rather than assuming it is what makes the number worth
              // trusting.
              DiscoverAnalyticsProps.tryOnCompleted: click.tryOnCompleted,
            },
          );
      _clickKey = uuidV4();
    } catch (error) {
      if (!mounted) return;
      final failure = shopFailureFor(error);
      _trackShopFailure(source.productId, shopFailureCode(failure));
      setState(() => _shopFailure = failure);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Reports a Shop tap from the render that never reached a retailer (§40).
  /// A reason code only — no destination, no error message, nothing about the
  /// image the user is looking at.
  void _trackShopFailure(String productId, String code, {String? merchantId}) {
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.affiliateClickFailed,
          properties: {
            DiscoverAnalyticsProps.productId: productId,
            DiscoverAnalyticsProps.feedPlacement: 'tryon_result',
            DiscoverAnalyticsProps.failureCode: code,
            DiscoverAnalyticsProps.merchantId: ?merchantId,
          },
        );
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

/// A failed outbound click, on top of the render. Non-blocking and never red:
/// the user's result is fine, only the store could not be reached (§24, §25).
class _ShopNote extends StatelessWidget {
  const _ShopNote({required this.failure, this.onRetry});

  final ShopFailure failure;

  /// Null when retrying cannot help — a product that is gone will not come
  /// back by tapping again.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            failure == ShopFailure.unavailable
                ? l10n.wtmShopUnavailableTitle
                : l10n.wtmShopStoreUnreachable,
            style: WtmType.micro.copyWith(color: WtmColors.text),
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(width: WtmSpace.s10),
          // Both sides bounded: GhostButton stretches to double.infinity, and
          // an unbounded Row slot turns that into a layout error.
          Expanded(
            flex: 2,
            child: GhostButton(label: l10n.commonRetry, onPressed: onRetry),
          ),
        ],
      ],
    );
  }
}

/// Route extra for the adjust editor.
class WtmAdjustArgs {
  const WtmAdjustArgs({required this.imageUrl, required this.initial});

  final String imageUrl;
  final WtmAdjustments initial;
}
