import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:intl/intl.dart';

part 'money.freezed.dart';
part 'money.g.dart';

/// An amount in the smallest unit of [currency] — cents for USD, poisha for
/// BDT, and yen for JPY where the minor unit IS the major one (DISCOVER §34).
///
/// Integer minor units, never a double. Binary floating point cannot represent
/// most decimal prices exactly, so a catalog that round-trips prices through a
/// `double` eventually shows an amount the retailer does not honour. It is also
/// never a pre-formatted string: the server does not know how a currency should
/// read in the user's language, so it sends the number and the code and the app
/// formats it.
///
/// There is no FX conversion here and none is planned in this scope. A product
/// is priced in one currency and displayed in that currency.
@freezed
abstract class Money with _$Money {
  const factory Money({
    @JsonKey(name: 'amount_minor') required int amountMinor,
    required String currency,
  }) = _Money;

  const Money._();

  factory Money.fromJson(Map<String, dynamic> json) => _$MoneyFromJson(json);

  /// Formatted for [locale], e.g. `৳3,499` or `$34.99`.
  ///
  /// The number of decimal places comes from the currency itself via `intl`, so
  /// a zero-decimal currency (JPY, KRW) is not rendered with a bogus `.00` and
  /// a three-decimal one (BHD, KWD) is not truncated. Falls back to
  /// `CODE 1,234.56` for a currency `intl` does not know rather than throwing
  /// inside a product card.
  String format({String? locale}) {
    try {
      final format = NumberFormat.simpleCurrency(
        locale: locale,
        name: currency,
      );
      return format.format(
        amountMinor / _minorUnitFactor(format.decimalDigits),
      );
    } catch (_) {
      return '$currency ${(amountMinor / 100).toStringAsFixed(2)}';
    }
  }

  static num _minorUnitFactor(int? decimalDigits) {
    // 10^digits — 1 for zero-decimal currencies, 100 for most, 1000 for a few.
    var factor = 1;
    for (var i = 0; i < (decimalDigits ?? 2); i++) {
      factor *= 10;
    }
    return factor;
  }

  /// Whether this is a genuine reduction from [original].
  ///
  /// Comparing across currencies is meaningless without conversion, so a
  /// mismatch is "no discount" rather than a number invented from two
  /// incomparable amounts (§26.10 — never fake a price drop).
  bool isDiscountFrom(Money? original) =>
      original != null &&
      original.currency == currency &&
      original.amountMinor > amountMinor;

  /// Whole-percent discount from [original], or null when there isn't one.
  int? discountPercentFrom(Money? original) {
    if (!isDiscountFrom(original)) return null;
    final off = original!.amountMinor - amountMinor;
    return (off * 100 / original.amountMinor).round();
  }
}
