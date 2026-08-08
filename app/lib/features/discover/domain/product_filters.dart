import 'package:flutter/foundation.dart';

/// The active Discover filter and search state (DISCOVER spec §11.2).
///
/// Value-equal, so a rebuild with identical filters does not restart the feed
/// — which is what keeps `ref.watch(productFiltersProvider)` from refetching on
/// every frame.
@immutable
class ProductFilters {
  const ProductFilters({
    this.query,
    this.category,
    this.subcategory,
    this.audience,
    this.colors = const [],
    this.sizes = const [],
    this.brands = const [],
    this.minPriceMinor,
    this.maxPriceMinor,
    this.tryOnReady = false,
    this.discounted = false,
    this.country,
    this.currency,
  });

  final String? query;
  final String? category;
  final String? subcategory;
  final String? audience;
  final List<String> colors;
  final List<String> sizes;
  final List<String> brands;

  /// Minor units, like every other price in the app (§34).
  final int? minPriceMinor;
  final int? maxPriceMinor;

  final bool tryOnReady;
  final bool discounted;
  final String? country;
  final String? currency;

  /// How many filters are set. Drives the compact `Filters · N` indicator —
  /// Discover never shows a permanent row of filter chips (§11.2, §26.1).
  ///
  /// A price range counts as ONE filter however many bounds it has, because
  /// that is how the user thinks of it.
  int get activeCount => [
    category != null,
    subcategory != null,
    audience != null,
    colors.isNotEmpty,
    sizes.isNotEmpty,
    brands.isNotEmpty,
    minPriceMinor != null || maxPriceMinor != null,
    tryOnReady,
    discounted,
  ].where((on) => on).length;

  bool get hasAny => activeCount > 0 || (query ?? '').isNotEmpty;

  ProductFilters copyWith({
    String? query,
    bool clearQuery = false,
    String? category,
    bool clearCategory = false,
    String? subcategory,
    String? audience,
    List<String>? colors,
    List<String>? sizes,
    List<String>? brands,
    int? minPriceMinor,
    int? maxPriceMinor,
    bool clearPrice = false,
    bool? tryOnReady,
    bool? discounted,
    String? country,
    String? currency,
  }) => ProductFilters(
    query: clearQuery ? null : (query ?? this.query),
    category: clearCategory ? null : (category ?? this.category),
    subcategory: subcategory ?? this.subcategory,
    audience: audience ?? this.audience,
    colors: colors ?? this.colors,
    sizes: sizes ?? this.sizes,
    brands: brands ?? this.brands,
    minPriceMinor: clearPrice ? null : (minPriceMinor ?? this.minPriceMinor),
    maxPriceMinor: clearPrice ? null : (maxPriceMinor ?? this.maxPriceMinor),
    tryOnReady: tryOnReady ?? this.tryOnReady,
    discounted: discounted ?? this.discounted,
    country: country ?? this.country,
    currency: currency ?? this.currency,
  );

  @override
  bool operator ==(Object other) =>
      other is ProductFilters &&
      other.query == query &&
      other.category == category &&
      other.subcategory == subcategory &&
      other.audience == audience &&
      listEquals(other.colors, colors) &&
      listEquals(other.sizes, sizes) &&
      listEquals(other.brands, brands) &&
      other.minPriceMinor == minPriceMinor &&
      other.maxPriceMinor == maxPriceMinor &&
      other.tryOnReady == tryOnReady &&
      other.discounted == discounted &&
      other.country == country &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(
    query,
    category,
    subcategory,
    audience,
    Object.hashAll(colors),
    Object.hashAll(sizes),
    Object.hashAll(brands),
    minPriceMinor,
    maxPriceMinor,
    tryOnReady,
    discounted,
    country,
    currency,
  );
}
