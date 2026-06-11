import 'package:freezed_annotation/freezed_annotation.dart';

import '../../data/models/stylist_suggestion.dart';

part 'stylist_state.freezed.dart';

/// UI state for the daily stylist (CLAUDE.md §4.3 four states): idle (intro +
/// CTA), loading, content (a suggestion), error.
@freezed
sealed class StylistState with _$StylistState {
  /// Nothing requested yet — show the intro + "style me" CTA.
  const factory StylistState.idle() = StylistIdle;

  /// Waiting on the backend stylist.
  const factory StylistState.loading() = StylistLoading;

  /// A suggestion came back (may be empty when the closet is empty).
  const factory StylistState.success(StylistSuggestion suggestion) =
      StylistSuccess;

  /// Failed — friendly message (+ backend code when available).
  const factory StylistState.failure({required String message, String? code}) =
      StylistFailure;
}
