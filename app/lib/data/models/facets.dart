import 'package:freezed_annotation/freezed_annotation.dart';

import 'money.dart';

part 'facets.freezed.dart';
part 'facets.g.dart';

/// One selectable filter option (DISCOVER spec §11.2).
///
/// [value] is the CANONICAL value the API filters on and never changes with
/// language; [label] is display text. Keeping them apart is what lets the app
/// translate "Dresses" without breaking the query that uses `dresses` — and it
/// is why an unknown category from a newer catalog still renders with a
/// readable label instead of being dropped.
@freezed
abstract class FacetValue with _$FacetValue {
  const factory FacetValue({
    required String value,
    required String label,
    @Default(0) int count,
  }) = _FacetValue;

  factory FacetValue.fromJson(Map<String, dynamic> json) =>
      _$FacetValueFromJson(json);
}

/// Filter vocabularies derived from the currently servable catalog.
///
/// Country-aware and built server-side, so a size or colour that exists only
/// on products which cannot ship to this user is never offered: a filter that
/// always returns nothing is worse than no filter at all.
///
/// An empty instance is a valid answer — a region with no catalog has no
/// facets — and the UI falls back to its curated defaults rather than showing
/// an empty sheet (§24).
@freezed
abstract class CatalogFacets with _$CatalogFacets {
  const factory CatalogFacets({
    @Default(<FacetValue>[]) List<FacetValue> categories,
    @Default(<FacetValue>[]) List<FacetValue> sizes,
    @Default(<FacetValue>[]) List<FacetValue> colors,
    @Default(<FacetValue>[]) List<FacetValue> merchants,
    @JsonKey(name: 'min_price') Money? minPrice,
    @JsonKey(name: 'max_price') Money? maxPrice,
    @JsonKey(name: 'try_on_available') @Default(false) bool tryOnAvailable,
    @JsonKey(name: 'discount_available') @Default(false) bool discountAvailable,
  }) = _CatalogFacets;

  const CatalogFacets._();

  factory CatalogFacets.fromJson(Map<String, dynamic> json) =>
      _$CatalogFacetsFromJson(json);

  /// Nothing to offer — the caller should use its curated fallback.
  bool get isEmpty =>
      categories.isEmpty &&
      sizes.isEmpty &&
      colors.isEmpty &&
      merchants.isEmpty;
}
