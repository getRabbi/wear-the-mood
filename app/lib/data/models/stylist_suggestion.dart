import 'package:freezed_annotation/freezed_annotation.dart';

import 'wardrobe_item.dart';

part 'stylist_suggestion.freezed.dart';
part 'stylist_suggestion.g.dart';

/// The daily stylist's pick (CLAUDE.md §1, pillar 3): a short title + rationale
/// and the chosen pieces from the user's own wardrobe. Maps the
/// `POST /v1/stylist/suggest` response directly.
@freezed
abstract class StylistSuggestion with _$StylistSuggestion {
  const factory StylistSuggestion({
    required String title,
    required String rationale,
    @Default(<WardrobeItem>[]) List<WardrobeItem> items,
  }) = _StylistSuggestion;

  const StylistSuggestion._();

  factory StylistSuggestion.fromJson(Map<String, dynamic> json) =>
      _$StylistSuggestionFromJson(json);

  /// True when the stylist returned no pieces (e.g. an empty closet).
  bool get isEmpty => items.isEmpty;
}
