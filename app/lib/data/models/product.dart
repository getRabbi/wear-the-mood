import 'package:freezed_annotation/freezed_annotation.dart';

import 'money.dart';

part 'product.freezed.dart';
part 'product.g.dart';

/// Why a product was surfaced. A typed code from the server, localized by the
/// app — never display text off the wire (DISCOVER §37.2).
///
/// [unknown] catches a reason introduced by a newer backend: an unrecognised
/// code must render as "no reason" rather than crash the feed (§37.4).
@JsonEnum(fieldRename: FieldRename.snake, alwaysCreate: true)
enum MatchReason {
  closetMatch,
  moodMatch,
  styleMatch,
  budgetFit,
  colorMatch,
  trending,
  newArrival,
  priceDrop,
  curated,
  @JsonValue('unknown')
  unknown,
}

@JsonEnum(fieldRename: FieldRename.snake, alwaysCreate: true)
enum StockStatus {
  inStock,
  lowStock,
  outOfStock,
  @JsonValue('unknown')
  unknown,
}

/// Try-on compatibility. `pending` is deliberately distinct from `ready`: a
/// product is only ever LABELLED Try-On Ready once compatibility has actually
/// passed (§35).
@JsonEnum(fieldRename: FieldRename.snake, alwaysCreate: true)
enum TryOnStatus {
  unsupported,
  pending,
  ready,
  @JsonValue('unknown')
  unknown,
}

/// Whether the server can say anything truthful about delivery.
///
/// `unknown` is not a failure and not a restriction — it means the source
/// supplied no shipping data and no admin has verified the merchant. The
/// product is still shoppable; the retailer resolves delivery at checkout. It
/// must never be rendered as "ships everywhere", which is the claim we
/// deliberately cannot make.
@JsonEnum(fieldRename: FieldRename.snake, alwaysCreate: true)
enum ShippingAvailability {
  known,
  @JsonValue('unknown')
  unknown,
}

@freezed
abstract class MerchantSummary with _$MerchantSummary {
  const factory MerchantSummary({
    required String id,
    required String name,
    @JsonKey(name: 'logo_url') String? logoUrl,
  }) = _MerchantSummary;

  factory MerchantSummary.fromJson(Map<String, dynamic> json) =>
      _$MerchantSummaryFromJson(json);
}

/// One size/colour combination. "This product has size M" and "size M is in
/// stock in black" are different claims, and only the second is safe to act on
/// (§12.16).
@freezed
abstract class ProductVariant with _$ProductVariant {
  const factory ProductVariant({
    required String id,
    String? color,
    String? size,
    Money? price,
    @JsonKey(name: 'original_price') Money? originalPrice,
    @JsonKey(name: 'stock_status')
    @Default(StockStatus.unknown)
    StockStatus stockStatus,
    @Default(true) bool available,
  }) = _ProductVariant;

  const ProductVariant._();

  factory ProductVariant.fromJson(Map<String, dynamic> json) =>
      _$ProductVariantFromJson(json);

  bool get isBuyable => available && stockStatus != StockStatus.outOfStock;
}

/// An affiliate catalog product (§17.2).
///
/// Note what is NOT here: any affiliate or retailer URL. The server sends an
/// opaque reference that only the redirect service can resolve, so the app
/// cannot open an unvalidated destination even if it wanted to (§18, §38,
/// safety rule 11).
@freezed
abstract class Product with _$Product {
  const factory Product({
    required String id,
    required MerchantSummary merchant,
    required String title,
    required Money price,
    String? brand,
    String? description,
    String? category,
    String? subcategory,
    @JsonKey(name: 'original_price') Money? originalPrice,
    @JsonKey(name: 'image_urls') @Default(<String>[]) List<String> imageUrls,
    // Where a portrait crop should centre, 0..1, so a hemline or a face is not
    // cut off by the card's aspect ratio (§6.2).
    @JsonKey(name: 'image_focal_x') @Default(0.5) double imageFocalX,
    @JsonKey(name: 'image_focal_y') @Default(0.5) double imageFocalY,
    @Default(<String>[]) List<String> colors,
    @Default(<String>[]) List<String> sizes,
    @Default(<ProductVariant>[]) List<ProductVariant> variants,
    @JsonKey(name: 'stock_status', unknownEnumValue: StockStatus.unknown)
    @Default(StockStatus.unknown)
    StockStatus stockStatus,
    @JsonKey(name: 'try_on_status', unknownEnumValue: TryOnStatus.unknown)
    @Default(TryOnStatus.unsupported)
    TryOnStatus tryOnStatus,
    // Defaults to `known` so an older payload keeps its current meaning: only a
    // server that genuinely told us nothing ever sends `unknown`.
    @JsonKey(
      name: 'shipping_availability',
      unknownEnumValue: ShippingAvailability.known,
    )
    @Default(ShippingAvailability.known)
    ShippingAvailability shippingAvailability,
    @JsonKey(name: 'match_reason', unknownEnumValue: MatchReason.unknown)
    MatchReason? matchReason,
    @Default(false) bool saved,
    @Default(false) bool sponsored,
    @JsonKey(name: 'tracking_token') String? trackingToken,
    @JsonKey(name: 'last_synced_at') DateTime? lastSyncedAt,
  }) = _Product;

  const Product._();

  factory Product.fromJson(Map<String, dynamic> json) =>
      _$ProductFromJson(json);

  String? get imageUrl => imageUrls.isEmpty ? null : imageUrls.first;

  /// Only a genuine, same-currency reduction counts (§26.10).
  bool get isDiscounted => price.isDiscountFrom(originalPrice);
  int? get discountPercent => price.discountPercentFrom(originalPrice);

  /// Whether the server has verified this product's try-on compatibility.
  /// `pending` is not ready.
  ///
  /// The STATUS only. Whether the action can actually be offered is
  /// [tryOnGarmentImageUrl], which also needs something to render.
  bool get isTryOnReady => tryOnStatus == TryOnStatus.ready;

  /// The garment image a try-on would be seeded with, or null if there is none
  /// (§4).
  ///
  /// The single answer to "can this be tried on, and with which picture" —
  /// used by the card to decide whether to draw the action and by the try-on
  /// entry point to seed the stack, so the affordance and the flow can never
  /// disagree. A ready product with nothing usable to send is not ready: an
  /// enabled pill that apologises on tap is a dead tap, which is the thing
  /// §5 rules out.
  ///
  /// Two rules, in order:
  ///
  /// 1. **The server's verdict first.** A product is never treated as try-on
  ///    ready because it happens to have a picture (§35).
  /// 2. **A usable garment URL.** The first `http(s)` entry with a host.
  ///    Blank, relative and non-http values are SKIPPED rather than sent: a
  ///    `data:`, `file:` or malformed URL reaches the provider as a garment
  ///    and fails there, which costs a job to learn what a string check knows
  ///    for free.
  ///
  /// The catalog carries no per-image classification, so the display image and
  /// the try-on source are the same URL today. That is a deliberate contract,
  /// not an oversight: ingestion sets `ready` only for a product whose lead
  /// image is a clean garment shot, which is where a collage or a campaign
  /// banner is meant to be refused. Nothing here can second-guess that — the
  /// app cannot see the picture — so this rejects what it can prove unusable
  /// and defers to the server for the rest. A dedicated try-on source, when
  /// one exists, plugs in HERE and nowhere else.
  String? get tryOnGarmentImageUrl {
    if (!isTryOnReady) return null;
    for (final candidate in imageUrls) {
      final url = candidate.trim();
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty) continue;
      if (uri.scheme != 'https' && uri.scheme != 'http') continue;
      return url;
    }
    return null;
  }

  bool get isOutOfStock => stockStatus == StockStatus.outOfStock;

  /// Whether the price/stock claim is old enough that it should be qualified
  /// rather than stated flatly (§12.15, §35).
  bool isStaleAt(DateTime now, {Duration limit = const Duration(days: 2)}) =>
      lastSyncedAt != null && now.difference(lastSyncedAt!) > limit;
}

/// One page of the catalog. Cursor-based, so pages cannot drift or duplicate
/// as rows are inserted (§23, §37.2).
@freezed
abstract class ProductPage with _$ProductPage {
  const factory ProductPage({
    @JsonKey(name: 'schema_version') @Default(1) int schemaVersion,
    @JsonKey(name: 'server_time') String? serverTime,
    @Default(<Product>[]) List<Product> items,
    @JsonKey(name: 'next_cursor') String? nextCursor,
    @JsonKey(name: 'cache_ttl_seconds') @Default(300) int cacheTtlSeconds,
    // True when the region has no catalog at all, as opposed to nothing
    // matching the current filters — a different empty state (§24).
    @JsonKey(name: 'region_empty') @Default(false) bool regionEmpty,
    // The region the server actually RESOLVED, which is not necessarily what
    // the client asked for — saved preferences win. The offline cache keys on
    // these so a page is dropped when the account's region changes (§34).
    String? country,
    String? currency,
    // Monotonic stamp of the user's shopping preferences; any change moves it
    // and invalidates a page ranked under the old profile.
    @JsonKey(name: 'profile_version') @Default(0) int profileVersion,
  }) = _ProductPage;

  const ProductPage._();

  factory ProductPage.fromJson(Map<String, dynamic> json) =>
      _$ProductPageFromJson(json);

  bool get hasMore => (nextCursor ?? '').isNotEmpty;
}

/// One product, revalidated at the moment Product Details opened (§12).
///
/// The feed's copy of a price may be minutes old, and from the offline cache it
/// may be days old. Details is where someone decides to spend money, so the
/// server re-reads price, stock and variants here and this carries the answer's
/// own freshness alongside it.
@freezed
abstract class ProductDetail with _$ProductDetail {
  const factory ProductDetail({
    required Product product,
    // Whether this can still be shopped. Reported rather than enforced: a
    // sold-out product opens and says so instead of 404-ing like a dead link
    // (§11.3, §24).
    @Default(false) bool servable,
    // The price/stock claim is old enough to be qualified rather than stated
    // flatly (§12.15, §35).
    @Default(false) bool stale,
    @JsonKey(name: 'delivery_countries')
    @Default(<String>[])
    List<String> deliveryCountries,
    // Whether an outbound click can be produced at all, so the store action can
    // be shown as unavailable up front instead of failing on tap (§18, §24).
    @Default(false) bool shoppable,
    @JsonKey(name: 'try_on_completed') @Default(false) bool tryOnCompleted,
    @JsonKey(name: 'server_time') String? serverTime,
  }) = _ProductDetail;

  factory ProductDetail.fromJson(Map<String, dynamic> json) =>
      _$ProductDetailFromJson(json);
}

/// The result of a tracked outbound click (§18).
///
/// [url] is the ONLY retailer URL the app ever holds, it arrives already
/// validated against the merchant's server-side domain allow-list, and it is
/// handed straight to the platform browser. The app never builds one, never
/// stores one, and never receives one before the click is recorded.
@freezed
abstract class AffiliateClick with _$AffiliateClick {
  const factory AffiliateClick({
    @JsonKey(name: 'click_id') required String clickId,
    required String url,
    required MerchantSummary merchant,
    @JsonKey(name: 'try_on_completed') @Default(false) bool tryOnCompleted,
  }) = _AffiliateClick;

  factory AffiliateClick.fromJson(Map<String, dynamic> json) =>
      _$AffiliateClickFromJson(json);
}

/// A saved product plus the state the Saved screen has to show (§11.3).
@freezed
abstract class SavedProduct with _$SavedProduct {
  const factory SavedProduct({
    required Product product,
    @JsonKey(name: 'saved_at') required DateTime savedAt,
    @JsonKey(name: 'price_alert_enabled') @Default(true) bool priceAlertEnabled,
    @JsonKey(name: 'availability_alert_enabled')
    @Default(false)
    bool availabilityAlertEnabled,
    // Server-derived from the price stored at save time. Never from a discount
    // the client claims (§38).
    @JsonKey(name: 'price_dropped') @Default(false) bool priceDropped,
  }) = _SavedProduct;

  factory SavedProduct.fromJson(Map<String, dynamic> json) =>
      _$SavedProductFromJson(json);
}
