import 'package:freezed_annotation/freezed_annotation.dart';

part 'outfit.freezed.dart';
part 'outfit.g.dart';

/// A saved combination of owned wardrobe items (CLAUDE.md §5). JSON keys match
/// the `outfits` table so this maps the `/v1/outfits` response directly.
@freezed
abstract class Outfit with _$Outfit {
  const factory Outfit({
    required String id,
    String? name,
    @JsonKey(name: 'item_ids') @Default(<String>[]) List<String> itemIds,
    @JsonKey(name: 'cover_image_url') String? coverImageUrl,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _Outfit;

  const Outfit._();

  factory Outfit.fromJson(Map<String, dynamic> json) => _$OutfitFromJson(json);

  int get itemCount => itemIds.length;
}
