import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/models/product.dart';
import '../../../data/repositories/discover_repository.dart';
import '../data/discover_local_store.dart';

/// One product, re-read from the server (DISCOVER §12, §35).
///
/// Product Details always fetches even when the feed handed it a whole
/// [Product]: the feed's copy can be minutes old, and served from the offline
/// cache it can be days old. This is the screen where someone decides to spend
/// money, so price, stock and variant availability are worth a round trip —
/// and the answer carries its own freshness so the screen can say when the
/// source last confirmed it.
///
/// `autoDispose` because a product the user has left is not state worth
/// keeping; the feed behind it is what must survive the trip, and it does.
final productDetailProvider = FutureProvider.autoDispose
    .family<ProductDetail, String>((ref, productId) async {
      final detail = await ref
          .watch(discoverRepositoryProvider)
          .product(productId);
      // Recently viewed is used to keep a just-seen product out of the first
      // feed positions (§33.3) and is a clearable user control (§36). Local,
      // non-sensitive, and best-effort: a store that cannot write must never
      // stop a product from opening.
      unawaited(
        ref
            .read(discoverLocalStoreProvider)
            .addRecentlyViewedProduct(productId),
      );
      return detail;
    });

/// Alternatives to a product (§12.12).
///
/// Its own provider, so a failure to find alternatives shows an empty section
/// rather than taking the product itself off the screen. The repository already
/// answers with an empty list rather than throwing, which is the right shape
/// for a helpful extra.
final similarProductsProvider = FutureProvider.autoDispose
    .family<List<Product>, String>((ref, productId) {
      return ref.watch(discoverRepositoryProvider).similar(productId, limit: 6);
    });

/// Why an outbound click could not be opened (§18, §24).
///
/// The two cases need genuinely different copy and different actions: a
/// product that is gone should offer alternatives, and a store that cannot be
/// reached should offer a retry. Telling someone to "try again" when the
/// product no longer exists is advice that can never work.
enum ShopFailure {
  /// The product is no longer available — sold out, expired, or withdrawn.
  unavailable,

  /// The destination could not be produced or validated. Retryable.
  unreachable,
}

/// Maps a failed click to the state the screen should show.
///
/// A rate limit is deliberately [ShopFailure.unreachable]: from the user's
/// side it is a temporary "not right now", and the honest action is to wait
/// and retry — not to imply the product vanished.
ShopFailure shopFailureFor(Object error) {
  if (error is ApiException && error.code == ApiErrorCode.notFound) {
    return ShopFailure.unavailable;
  }
  return ShopFailure.unreachable;
}
