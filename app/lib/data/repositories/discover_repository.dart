import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/facets.dart';
import '../models/product.dart';

/// A catalog page plus the exact JSON the server sent.
///
/// The raw map travels with the parsed page because the offline cache stores
/// the SERVER'S response, not a re-serialization of the model: this project
/// generates serializers with `explicit_to_json` off, so `Product.toJson()`
/// writes nested objects as objects rather than maps and would not read back.
class ProductPageResult {
  const ProductPageResult({required this.page, required this.raw});

  final ProductPage page;
  final Map<String, dynamic> raw;
}

/// The Discover shopping catalog (DISCOVER spec §17, §37).
///
/// Deliberately thin: filters go out as query parameters and pages come back
/// whole. All eligibility, ranking, region resolution and money handling live
/// server-side, so this cannot drift from what the API actually enforces.
class DiscoverRepository {
  DiscoverRepository(this._dio);

  final Dio _dio;

  /// One page of the catalog.
  ///
  /// [cursor] is the opaque position from the previous page; passing null
  /// starts at the beginning. Prices are MINOR UNITS, matching the models.
  Future<ProductPageResult> products({
    String? cursor,
    int? limit,
    String? country,
    String? currency,
    String? category,
    String? subcategory,
    String? audience,
    List<String> colors = const [],
    List<String> sizes = const [],
    List<String> brands = const [],
    int? minPriceMinor,
    int? maxPriceMinor,
    bool tryOnReady = false,
    bool discounted = false,
    String? query,
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/discover/products',
        // Null entries are dropped by dio, so an unset filter is simply absent
        // rather than sent as an empty string the server has to interpret.
        queryParameters: {
          'cursor': ?cursor,
          'limit': ?limit,
          'country': ?country,
          'currency': ?currency,
          'category': ?category,
          'subcategory': ?subcategory,
          'audience': ?audience,
          if (colors.isNotEmpty) 'color': colors,
          if (sizes.isNotEmpty) 'size': sizes,
          if (brands.isNotEmpty) 'brand': brands,
          'min_price': ?minPriceMinor,
          'max_price': ?maxPriceMinor,
          if (tryOnReady) 'try_on_ready': true,
          if (discounted) 'discounted': true,
          if ((query ?? '').trim().isNotEmpty) 'q': query!.trim(),
        },
        // Lets the caller abandon a superseded request — a filter change or a
        // new search must not be overwritten by the response to the old one
        // (§23 "cancel stale requests").
        cancelToken: cancelToken,
      );
      final raw = res.data!;
      // Parse first: `raw` is only worth caching once it is proven to be a
      // page this build can read. The offline cache stores this map rather
      // than re-serializing the model (see DiscoverFeedCache).
      return ProductPageResult(page: ProductPage.fromJson(raw), raw: raw);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// One product, revalidated server-side right now (§12, §35).
  ///
  /// Product Details always calls this even when it was handed a product from
  /// the feed: the feed's copy can be minutes old, and from the offline cache
  /// it can be days old. A price someone is about to act on is worth a round
  /// trip.
  Future<ProductDetail> product(String productId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/discover/products/$productId',
      );
      return ProductDetail.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Alternatives to [productId] (§12.12).
  ///
  /// Returns an empty list rather than throwing when the backend cannot answer:
  /// similar products are a helpful extra on Product Details, and a failure to
  /// find alternatives must not take the product itself off the screen.
  Future<List<Product>> similar(String productId, {int? limit}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/discover/products/$productId/similar',
        queryParameters: {'limit': ?limit},
      );
      return (res.data ?? [])
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException {
      return const [];
    }
  }

  /// Records an outbound click and returns the one destination it may open
  /// (§18, §38).
  ///
  /// The app sends a product id and context and receives a URL; it never sends
  /// one, and never holds one before the click is recorded. [idempotencyKey]
  /// must be stable for a single tap so a retry after a dropped response
  /// replays rather than logging a second click.
  Future<AffiliateClick> click(
    String productId, {
    required String idempotencyKey,
    String? feedPlacement,
    String? storyId,
    String? campaignId,
    String? trackingToken,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/discover/products/$productId/click',
        data: {
          'feed_placement': ?feedPlacement,
          'story_id': ?storyId,
          'campaign_id': ?campaignId,
          'tracking_token': ?trackingToken,
        },
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return AffiliateClick.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Filter vocabularies for the currently servable catalog (§11.2).
  ///
  /// Returns null when the backend cannot answer — the caller then falls back
  /// to its curated defaults rather than showing an empty filter sheet.
  Future<CatalogFacets?> facets({String? country}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/discover/facets',
        queryParameters: {'country': ?country},
      );
      return CatalogFacets.fromJson(res.data!);
    } on DioException {
      return null;
    }
  }

  Future<List<SavedProduct>> saved() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/discover/saved');
      return (res.data ?? [])
          .map((e) => SavedProduct.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Save a product. Idempotent server-side, so a double-tap is one row.
  Future<void> save(
    String productId, {
    bool priceAlert = true,
    bool availabilityAlert = false,
  }) async {
    try {
      await _dio.put<void>(
        '/v1/discover/saved/$productId',
        data: {
          'price_alert_enabled': priceAlert,
          'availability_alert_enabled': availabilityAlert,
        },
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Unsave. Also idempotent — removing something already gone is success.
  Future<void> unsave(String productId) async {
    try {
      await _dio.delete<void>('/v1/discover/saved/$productId');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Record one behavioural signal (§19.3/§19.4).
  ///
  /// [clientEventId] must be stable across retries of the SAME user action;
  /// the server's unique index turns a retry into a no-op so a dropped
  /// response cannot double-count (§37.3).
  Future<void> recordInteraction({
    required String eventType,
    String? productId,
    String? merchantId,
    String? feedPlacement,
    String? storyId,
    String? trackingToken,
    String? clientEventId,
  }) async {
    try {
      await _dio.post<void>(
        '/v1/discover/interactions',
        data: {
          'event_type': eventType,
          'product_id': ?productId,
          'merchant_id': ?merchantId,
          'feed_placement': ?feedPlacement,
          'story_id': ?storyId,
          'tracking_token': ?trackingToken,
          'client_event_id': ?clientEventId,
        },
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final discoverRepositoryProvider = Provider<DiscoverRepository>((ref) {
  return DiscoverRepository(ref.watch(dioProvider));
});
