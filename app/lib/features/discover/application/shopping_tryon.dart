import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics_events.dart';
import '../../../core/analytics/analytics_provider.dart';
import '../../../core/router/route_stack.dart';
import '../../../core/router/routes.dart';
import '../../../data/models/product.dart';
import '../../../data/models/tryon_source.dart';
import '../../../data/repositories/discover_repository.dart';
import '../../../data/repositories/tryon_repository.dart';
import '../../../ui/mirror/wtm_mirror_flow.dart';
import '../../tryon/models/studio_models.dart';
import '../../tryon/tryon_controller.dart';
import '../../tryon/tryon_preselect.dart';
import '../../tryon/tryon_state.dart';

/// Shopping Try-On (DISCOVER §13).
///
/// This file is an ADAPTER, not an engine. It converts a catalog product into
/// the input the existing MoodMirror pipeline already accepts and then gets out
/// of the way — the body-photo flow, consent gate, credit reservation, HD plan
/// gate, polling, refund-on-failure and result history all stay exactly where
/// they are. Nothing here submits a job, touches credits, or decides what a
/// failure costs. Duplicating any of that would mean two places where a refund
/// could go wrong, which is the one thing §13 is emphatic about.
///
/// The seam it uses already existed: [TryOnPreselect.setImages] takes arbitrary
/// remote garment URLs, and Step 2 consumes the queue on mount. A shopping
/// try-on is therefore the closet handoff with a different image source and
/// some metadata riding along.

/// Where a shopping try-on came from, so its result can go back (§13).
///
/// Deliberately small and non-sensitive: ids, a title and the product's own
/// public image. No body photo, no closet image, no affiliate URL — those must
/// never be attached to anything that travels (§36).
@immutable
class ShoppingTryOnSource {
  const ShoppingTryOnSource({
    required this.productId,
    required this.merchantId,
    required this.title,
    required this.imageUrl,
    this.trackingToken,
    this.feedPlacement,
    this.campaignId,
  });

  final String productId;
  final String merchantId;
  final String title;

  /// The garment image this run was seeded with. It is also how the source
  /// knows whether it is still relevant — see [activeShoppingTryOnSourceProvider].
  final String imageUrl;

  /// Rebuilds the context from what the JOB persisted (§13).
  ///
  /// [title] and [imageUrl] come back empty: neither is stored on a job, and
  /// neither is needed to act. The title would be a cached label that could
  /// have changed, and the image is the product's, which Product Details
  /// re-reads live. Everything a purchase decision needs is fetched fresh —
  /// this only has to know WHICH product.
  factory ShoppingTryOnSource.restored(TryOnSource source) =>
      ShoppingTryOnSource(
        productId: source.productId,
        merchantId: source.merchantId ?? '',
        title: '',
        imageUrl: '',
        feedPlacement: source.placement,
        campaignId: source.campaignId,
      );

  final String? trackingToken;
  final String? feedPlacement;
  final String? campaignId;

  @override
  bool operator ==(Object other) =>
      other is ShoppingTryOnSource &&
      other.productId == productId &&
      other.imageUrl == imageUrl;

  @override
  int get hashCode => Object.hash(productId, imageUrl);
}

final shoppingTryOnSourceProvider =
    NotifierProvider<ShoppingTryOnSourceNotifier, ShoppingTryOnSource?>(
      ShoppingTryOnSourceNotifier.new,
    );

class ShoppingTryOnSourceNotifier extends Notifier<ShoppingTryOnSource?> {
  @override
  ShoppingTryOnSource? build() => null;

  void set(ShoppingTryOnSource source) => state = source;

  void clear() => state = null;
}

/// The shopping source for the CURRENT outfit stack, or null.
///
/// This is the one that callers should read. It is derived rather than stored
/// because the alternative — clearing the source everywhere a non-shopping run
/// can begin — is a discipline that only has to be forgotten once to attach a
/// product to somebody's closet render. Instead the source is valid exactly
/// while the product it names is still in the stack: seeding a closet handoff
/// REPLACES the layers, so the source evaporates on its own, and removing the
/// product in Step 2 has the same effect.
final activeShoppingTryOnSourceProvider = Provider<ShoppingTryOnSource?>((ref) {
  final source = ref.watch(shoppingTryOnSourceProvider);
  if (source == null) return null;
  final layers = ref.watch(wtmMirrorFlowProvider).layers;
  return layers.any((l) => l.imageUrl == source.imageUrl) ? source : null;
});

/// The shopping context for the result currently on screen.
///
/// Prefers what the JOB persisted over what this session remembers. The two
/// agree during a normal run, and they diverge in exactly the case that
/// matters: the app was killed and restarted, so the in-memory source is gone
/// and only the job still knows. The fallback covers the opposite gap — a
/// backend that predates the field — so neither side alone is load-bearing.
final resultShoppingSourceProvider = Provider<ShoppingTryOnSource?>((ref) {
  final state = ref.watch(tryOnControllerProvider);
  final persisted = state is TryOnSuccess ? state.job.source : null;
  if (persisted != null) return ShoppingTryOnSource.restored(persisted);
  return ref.watch(activeShoppingTryOnSourceProvider);
});

/// The shopping context of a SAVED look, fetched by its job id.
///
/// This is the true process-death path: Saved Looks persists the job id on
/// device, and the origin comes back off the server with the job. Answers null
/// for an ordinary look, for a look whose product has since been withdrawn, and
/// for anything it cannot fetch — a history tile must never fail to open
/// because a back-link could not be resolved.
final savedLookSourceProvider = FutureProvider.autoDispose
    .family<ShoppingTryOnSource?, String>((ref, jobId) async {
      try {
        final source =
            (await ref.watch(tryOnRepositoryProvider).getJob(jobId)).source;
        return source == null ? null : ShoppingTryOnSource.restored(source);
      } catch (_) {
        return null;
      }
    });

/// Reports the shopping funnel's try-on events for the lifetime of the session.
///
/// It listens to the try-on controller rather than to a screen, because the
/// generating screen can be left while the job finishes — and a render the user
/// walked away from still counts toward the try-on-to-shop rate when they come
/// back and buy. Screens come and go; the conversion does not.
///
/// The `try_on` INTERACTION it writes on success is what makes the server
/// answer `try_on_completed` for this product later, which is how an affiliate
/// click knows a try-on preceded it (§13, §18).
final shoppingTryOnTrackerProvider =
    NotifierProvider<ShoppingTryOnTracker, ShoppingTryOnPhase>(
      ShoppingTryOnTracker.new,
    );

/// What the current shopping try-on is doing. Exposed so the result screen can
/// tell a completed shopping run from a completed closet run.
enum ShoppingTryOnPhase { idle, running, complete, failed }

class ShoppingTryOnTracker extends Notifier<ShoppingTryOnPhase> {
  @override
  ShoppingTryOnPhase build() {
    ref.listen<TryOnState>(tryOnControllerProvider, (previous, next) {
      // Read, never watch: this reacts to try-on progress, and re-running the
      // listener because the outfit stack changed would double-report.
      final source = ref.read(activeShoppingTryOnSourceProvider);
      if (source == null) return;
      switch (next) {
        case TryOnSubmitting():
          state = ShoppingTryOnPhase.running;
          _track(AnalyticsEvents.tryOnStart, source);
        case TryOnSuccess():
          state = ShoppingTryOnPhase.complete;
          _track(AnalyticsEvents.tryOnComplete, source);
          // The behavioural half. Recorded on SUCCESS, not on submit: a job
          // that never produced an image is not a try-on the user has seen,
          // and it must not make a later click look like a conversion.
          _record(source);
        case TryOnFailure(:final code):
          state = ShoppingTryOnPhase.failed;
          _track(
            AnalyticsEvents.tryOnFail,
            source,
            // The failure REASON, which is a typed code — never the server's
            // human message, which is display text and can change freely.
            extra: {DiscoverAnalyticsProps.failureCode: ?code},
          );
        case TryOnIdle() || TryOnPolling():
          break;
      }
    });
    return ShoppingTryOnPhase.idle;
  }

  void _track(
    String event,
    ShoppingTryOnSource source, {
    Map<String, Object> extra = const {},
  }) {
    ref
        .read(analyticsProvider)
        .track(
          event,
          properties: {
            DiscoverAnalyticsProps.productId: source.productId,
            DiscoverAnalyticsProps.merchantId: source.merchantId,
            if (source.feedPlacement != null)
              DiscoverAnalyticsProps.feedPlacement: source.feedPlacement!,
            if (source.trackingToken != null)
              DiscoverAnalyticsProps.trackingToken: source.trackingToken!,
            ...extra,
          },
        );
  }

  void _record(ShoppingTryOnSource source) {
    ref
        .read(discoverRepositoryProvider)
        .recordInteraction(
          eventType: 'try_on',
          productId: source.productId,
          merchantId: source.merchantId,
          feedPlacement: source.feedPlacement,
          trackingToken: source.trackingToken,
          // One signal per product per run, so a retried write cannot make one
          // render look like two.
          clientEventId:
              'try_on:${source.productId}:${source.imageUrl.hashCode}',
        )
        .catchError((Object _) {
          // A lost ranking write must never surface to someone looking at
          // their render.
        });
  }
}

/// Whether the garment step this function pushes is ALREADY the top page.
///
/// The double-tap guard (§3). `context.push` updates the router's page stack
/// synchronously, so the second tap of a rapid pair reads the destination the
/// first one just installed and declines to push it again — no timer, no
/// debounce window, and nothing to tune.
///
/// It deliberately checks the TOP of the stack rather than "have we pushed
/// before". Starting a second try-on from Product Details is a supported
/// sequence — the result screen's View Product leaves the mirror flow on the
/// stack — and there the product route is on top, so product B is not mistaken
/// for a double tap of product A.
///
/// Reads the page stack, NOT `currentConfiguration.uri`. That uri describes the
/// last location the router was navigated to declaratively and is deliberately
/// left alone by an imperative push: after `go('/wtm/discover')` then
/// `push('/wtm/mirror/garments')` it still reads `/wtm/discover`. So this guard
/// compared a path that could never match and answered "not open" every single
/// time — a double tap that landed pushed two garment steps, and one Back left
/// the user on the second.
bool _garmentStepAlreadyOpen(BuildContext context) =>
    isTopRoute(context, AppRoute.wtmMirrorGarments);

/// Sends [product] into the existing try-on pipeline (§13).
///
/// The ONE entry point every Try On action goes through — the card pill on
/// every product surface and the Product Details button alike. It composes the
/// stack and navigates, and nothing else: the body-photo flow, consent gate,
/// credit reservation, HD plan gate, polling, refund-on-failure and result
/// history stay where they are. Tapping Try On spends nothing; credits are
/// still governed entirely by the mirror's own generate step.
///
/// Lands on the garment step rather than jumping to generate, so the user can
/// finish the look with pieces they already own — which is the point of trying
/// a purchase on — and so every downstream gate (body photo, consent, mode,
/// credits) runs exactly as it does for a closet try-on.
///
/// Returns false when the product cannot be tried on: not verified compatible,
/// or no usable image. The caller warns instead of leaving a dead tap. A
/// product is never treated as Try-On Ready just because it has a picture
/// (§35).
bool startShoppingTryOn(
  BuildContext context,
  WidgetRef ref,
  Product product, {
  String? placement,
  String? campaignId,
}) {
  // The same answer the card used to decide whether to draw the action, so
  // the affordance and the flow cannot disagree (§4).
  final url = product.tryOnGarmentImageUrl;
  if (url == null) return false;
  // A second tap while the flow is already opening is the same tap. Answered
  // true, not false: the flow DID start, and returning false would put an
  // "isn't ready for try-on" warning on a product that is being tried on.
  if (_garmentStepAlreadyOpen(context)) return true;

  ref
      .read(shoppingTryOnSourceProvider.notifier)
      .set(
        ShoppingTryOnSource(
          productId: product.id,
          merchantId: product.merchant.id,
          title: product.title,
          imageUrl: url,
          trackingToken: product.trackingToken,
          feedPlacement: placement,
          campaignId: campaignId,
        ),
      );
  // Instantiate the tracker so it is listening before the job can start. It
  // outlives this screen on purpose.
  ref.read(shoppingTryOnTrackerProvider);

  // Compose the stack HERE rather than through TryOnPreselect.
  //
  // The preselect is consumed by Step 2 on mount, which is the right door for
  // the closet handoff — that always arrives at a freshly pushed Step 2. A
  // shopping try-on does not: from Product Details the user can start a second
  // one without Step 2 ever re-mounting (the result screen's View Product
  // leaves the mirror flow on the stack), and then the queue is never consumed
  // and product B never replaces product A. Setting the layers directly makes
  // the outcome the same whatever the navigation did.
  ref
      .read(wtmMirrorFlowProvider.notifier)
      .setLayers(shoppingStack(ref.read(wtmMirrorFlowProvider).layers, url));
  // Nothing queued: a stale queue consumed by a later Step 2 mount would undo
  // the stack composed above.
  ref.read(tryOnPreselectProvider.notifier).clear();
  context.push(AppRoute.wtmMirrorGarments);
  return true;
}

/// The outfit stack for a new single-product shopping try-on.
///
/// One shopping product at a time: the previous one is REPLACED, never added
/// to, because "try this dress" twice in a row means two different dresses, not
/// both at once — and silently stacking them would spend credits rendering an
/// outfit nobody asked for.
///
/// Pieces the user OWNS are kept. Trying a purchase on with your own shoes is
/// the point of the feature, and a wardrobe id is what distinguishes a piece
/// someone deliberately added from a transient catalog image. Anything else
/// without an id — a previous product, a sample-rack garment — is transient and
/// makes way.
@visibleForTesting
List<TryOnLayer> shoppingStack(List<TryOnLayer> current, String productUrl) {
  final owned = [
    for (final layer in current)
      if (layer.wardrobeItemId != null && layer.imageUrl != productUrl) layer,
  ];
  return [
    TryOnLayer.fromSource(imageUrl: productUrl, zIndex: 0),
    for (final (i, layer) in owned.indexed) layer.copyWith(zIndex: i + 1),
  ].take(WtmMirrorFlow.maxGarments).toList();
}
