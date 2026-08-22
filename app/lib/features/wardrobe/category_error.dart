import '../../core/network/api_exception.dart';
import '../../l10n/app_localizations.dart';

/// What to SHOW when saving or repairing a category fails.
///
/// The rule this enforces is that a person never reads a transport error. Dio's
/// own message for a dropped connection is text like "Connection closed before
/// full header was received" — accurate, useless, and alarming — and it was
/// reaching the UI verbatim through `ApiException.message` on the one code that
/// carries no server envelope at all.
///
/// Where the SERVER authored the sentence it is kept: `VALIDATION_ERROR` on this
/// path says "That category isn't supported any more. Please choose another.",
/// which is better than anything a generic map could substitute, and keeping it
/// means the backend can improve its own copy without a client release. The
/// codes that are replaced are the ones whose message is machinery rather than
/// writing.
///
/// [cutoutExpired] switches the meaning of `NOT_FOUND`, which genuinely differs
/// by flow: while adding a garment it is the temp cutout having been reaped, and
/// the only way forward is a new photo; while editing an existing piece it is
/// the item itself being gone.
String categoryErrorMessage(
  AppLocalizations l10n,
  Object error, {
  bool cutoutExpired = false,
}) {
  if (error is! ApiException) return l10n.catFixFailed;
  return switch (error.code) {
    // No envelope came back, so there is no server sentence to show — and the
    // useful thing to say is not what the socket did, but that nothing was
    // saved and a retry is safe.
    ApiErrorCode.network => l10n.catErrorOffline,
    ApiErrorCode.unauthenticated => l10n.catErrorSession,
    ApiErrorCode.notFound when cutoutExpired => l10n.catErrorCutoutExpired,
    // Server-authored, user-facing copy. Passed through on purpose.
    ApiErrorCode.validationError ||
    ApiErrorCode.notFound ||
    ApiErrorCode.rateLimited ||
    ApiErrorCode.providerError => error.message,
    _ => l10n.catFixFailed,
  };
}
