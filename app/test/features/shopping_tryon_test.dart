import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/analytics/analytics.dart';
import 'package:app/core/analytics/analytics_events.dart';
import 'package:app/core/analytics/analytics_provider.dart';
import 'package:app/data/models/money.dart';
import 'package:app/data/models/product.dart';
import 'package:app/data/models/tryon_job.dart' as job;
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/discover_repository.dart';
import 'package:app/features/discover/application/shopping_tryon.dart';
import 'package:app/features/tryon/models/studio_models.dart';
import 'package:app/features/tryon/tryon_controller.dart';
import 'package:app/features/tryon/tryon_preselect.dart';
import 'package:app/features/tryon/tryon_state.dart';
import 'package:app/ui/mirror/wtm_mirror_flow.dart';

/// Phase 5 domain: the shopping try-on source, its self-invalidation, and the
/// conversion signal that lets an affiliate click know a render preceded it.
///
/// What is NOT tested here, deliberately: credits, reservation and refunds.
/// The adapter does not touch them — the whole point is that the existing
/// pipeline still owns them — so a test asserting refund behaviour through this
/// layer would be testing nothing while looking like it tested something.

class _RecordingAnalytics implements Analytics {
  final events = <String>[];
  final props = <String, Map<String, Object>?>{};

  @override
  Future<void> track(String event, {Map<String, Object>? properties}) async {
    events.add(event);
    props[event] = properties;
  }

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}
}

class _FakeDiscover implements DiscoverRepository {
  final interactions = <Map<String, String?>>[];

  @override
  Future<void> recordInteraction({
    required String eventType,
    String? productId,
    String? merchantId,
    String? feedPlacement,
    String? storyId,
    String? trackingToken,
    String? clientEventId,
  }) async {
    interactions.add({
      'event': eventType,
      'product': productId,
      'merchant': merchantId,
      'placement': feedPlacement,
      'client_event_id': clientEventId,
    });
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

Product _product({
  String id = 'p1',
  TryOnStatus tryOn = TryOnStatus.ready,
  List<String> images = const ['https://cdn.test/dress.jpg'],
}) => Product(
  id: id,
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: 'Black silk dress',
  price: const Money(amountMinor: 349900, currency: 'BDT'),
  imageUrls: images,
  tryOnStatus: tryOn,
  trackingToken: 'p:$id',
);

ShoppingTryOnSource _source({
  String id = 'p1',
  String? placement = 'feed_grid',
}) => ShoppingTryOnSource(
  productId: id,
  merchantId: 'm1',
  title: 'Black silk dress',
  imageUrl: 'https://cdn.test/dress.jpg',
  trackingToken: 'p:$id',
  feedPlacement: placement,
);

void main() {
  late _RecordingAnalytics analytics;
  late _FakeDiscover discover;

  ProviderContainer boot() {
    analytics = _RecordingAnalytics();
    discover = _FakeDiscover();
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        analyticsProvider.overrideWithValue(analytics),
        discoverRepositoryProvider.overrideWithValue(discover),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Puts the product's image into the outfit stack, which is what makes a
  /// source "active".
  void seedStack(ProviderContainer container, String url) {
    container.read(wtmMirrorFlowProvider.notifier).setLayers([
      TryOnLayer.fromSource(imageUrl: url, zIndex: 0),
    ]);
  }

  group('the source follows the outfit stack', () {
    test('is inactive until the product is actually in the stack', () {
      final container = boot();
      container.read(shoppingTryOnSourceProvider.notifier).set(_source());

      // Set but not seeded: nothing is being tried on yet.
      expect(container.read(activeShoppingTryOnSourceProvider), isNull);

      seedStack(container, 'https://cdn.test/dress.jpg');
      expect(container.read(activeShoppingTryOnSourceProvider), isNotNull);
    });

    test('evaporates when a closet handoff replaces the stack', () {
      // This is the property that matters: without it, a stale product would
      // ride along on somebody's closet render and its result screen would
      // offer to buy something they never tried on.
      final container = boot();
      container.read(shoppingTryOnSourceProvider.notifier).set(_source());
      seedStack(container, 'https://cdn.test/dress.jpg');
      expect(container.read(activeShoppingTryOnSourceProvider), isNotNull);

      // A closet "Try This On" seeds its own layers, replacing the stack.
      container.read(wtmMirrorFlowProvider.notifier).setLayers([
        TryOnLayer.fromSource(
          imageUrl: 'https://cdn.test/my-own-jacket.jpg',
          wardrobeItemId: 'w1',
          zIndex: 0,
        ),
      ]);

      expect(container.read(activeShoppingTryOnSourceProvider), isNull);
    });

    test('survives the user adding their own pieces alongside it', () {
      // Trying a purchase on WITH what you own is the point, so the source
      // must not be lost just because the stack grew.
      final container = boot();
      container.read(shoppingTryOnSourceProvider.notifier).set(_source());
      container.read(wtmMirrorFlowProvider.notifier).setLayers([
        TryOnLayer.fromSource(
          imageUrl: 'https://cdn.test/dress.jpg',
          zIndex: 0,
        ),
      ]);
      container
          .read(wtmMirrorFlowProvider.notifier)
          .toggleItem(
            const WardrobeItem(
              id: 'w1',
              imageUrl: 'https://cdn.test/my-shoes.jpg',
            ),
          );

      expect(container.read(activeShoppingTryOnSourceProvider), isNotNull);
      expect(container.read(wtmMirrorFlowProvider).layers, hasLength(2));
    });

    test('removing the product in Step 2 deactivates it', () {
      final container = boot();
      container.read(shoppingTryOnSourceProvider.notifier).set(_source());
      seedStack(container, 'https://cdn.test/dress.jpg');

      container.read(wtmMirrorFlowProvider.notifier).setLayers([]);

      expect(container.read(activeShoppingTryOnSourceProvider), isNull);
    });
  });

  group('the conversion signal', () {
    /// Drives the real controller's state machine without a network.
    void emit(ProviderContainer container, TryOnState state) {
      container.read(tryOnControllerProvider.notifier).state = state;
    }

    test('reports start, complete, and the try_on interaction', () {
      final container = boot();
      container.read(shoppingTryOnSourceProvider.notifier).set(_source());
      seedStack(container, 'https://cdn.test/dress.jpg');
      container.read(shoppingTryOnTrackerProvider);

      emit(container, const TryOnState.submitting());
      emit(
        container,
        const TryOnState.success(
          job.TryOnJob(jobId: 'j1', status: job.TryOnStatus.done),
        ),
      );

      expect(analytics.events, [
        AnalyticsEvents.tryOnStart,
        AnalyticsEvents.tryOnComplete,
      ]);
      // The behavioural half — this is what makes the server answer
      // `try_on_completed` on the next click for this product.
      expect(discover.interactions, hasLength(1));
      expect(discover.interactions.single['event'], 'try_on');
      expect(discover.interactions.single['product'], 'p1');
      expect(discover.interactions.single['client_event_id'], isNotNull);
    });

    test('records the interaction on success only, never on submit', () {
      // A job that never produced an image is not a try-on the user has seen,
      // and it must not make a later click look like a conversion.
      final container = boot();
      container.read(shoppingTryOnSourceProvider.notifier).set(_source());
      seedStack(container, 'https://cdn.test/dress.jpg');
      container.read(shoppingTryOnTrackerProvider);

      emit(container, const TryOnState.submitting());
      expect(discover.interactions, isEmpty);

      emit(
        container,
        const TryOnState.failure(message: 'no', code: 'PROVIDER_ERROR'),
      );
      expect(discover.interactions, isEmpty);
    });

    test('a failure reports its typed code, not the server message', () {
      final container = boot();
      container.read(shoppingTryOnSourceProvider.notifier).set(_source());
      seedStack(container, 'https://cdn.test/dress.jpg');
      container.read(shoppingTryOnTrackerProvider);

      emit(container, const TryOnState.submitting());
      emit(
        container,
        const TryOnState.failure(
          message: 'Out of credits, friend.',
          code: 'INSUFFICIENT_CREDITS',
        ),
      );

      expect(analytics.events, contains(AnalyticsEvents.tryOnFail));
      final props = analytics.props[AnalyticsEvents.tryOnFail]!;
      expect(props[DiscoverAnalyticsProps.failureCode], 'INSUFFICIENT_CREDITS');
      // Display text changes freely; a dashboard built on it would rot.
      expect(props.values.join(), isNot(contains('friend')));
    });

    test('a closet render reports nothing to the shopping funnel', () {
      // The denominator of "try-on to shop click" has to be try-ons of
      // something someone can actually buy.
      final container = boot();
      container.read(shoppingTryOnTrackerProvider);
      container.read(wtmMirrorFlowProvider.notifier).setLayers([
        TryOnLayer.fromSource(imageUrl: 'https://cdn.test/mine.jpg', zIndex: 0),
      ]);

      emit(container, const TryOnState.submitting());
      emit(
        container,
        const TryOnState.success(
          job.TryOnJob(jobId: 'j1', status: job.TryOnStatus.done),
        ),
      );

      expect(analytics.events, isEmpty);
      expect(discover.interactions, isEmpty);
    });

    test('nothing carries a body photo, closet image or URL', () {
      final container = boot();
      container.read(shoppingTryOnSourceProvider.notifier).set(_source());
      seedStack(container, 'https://cdn.test/dress.jpg');
      container.read(shoppingTryOnTrackerProvider);

      emit(container, const TryOnState.submitting());
      emit(
        container,
        const TryOnState.success(
          job.TryOnJob(jobId: 'j1', status: job.TryOnStatus.done),
        ),
      );

      for (final entry in analytics.props.values) {
        expect(
          (entry ?? const {}).values.join(),
          isNot(contains('http')),
          reason: 'analytics must never carry an image URL (§22, §36)',
        );
      }
    });
  });

  group('the preselect handoff', () {
    test('a try-on-ready product seeds exactly one layer', () {
      // The adapter reuses TryOnPreselect rather than reaching into the mirror
      // draft — the same door the closet and stylist handoffs use.
      final container = boot();
      container.read(tryOnPreselectProvider.notifier).setImages([
        _product().imageUrl!,
      ]);

      final queued = container.read(tryOnPreselectProvider);
      expect(queued, hasLength(1));
      expect(queued!.single.imageUrl, 'https://cdn.test/dress.jpg');
      // A catalog product is a reference layer: it is not something the user
      // owns, so it must never claim a wardrobe id.
      expect(queued.single.wardrobeItemId, isNull);
    });
  });
}
