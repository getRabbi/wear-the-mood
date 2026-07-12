/// Hosted legal documents (CLAUDE.md §10, §19, §22). Required for the store
/// listing and shown from the profile screen. Host the files in legal/ at these
/// URLs (wearthemood.com) before store submission — the Play listing + Data
/// Safety form reference them, and the acceptable-use policy backs try-on input
/// moderation (§19).
abstract final class LegalLinks {
  static const privacy = 'https://wearthemood.com/legal/privacy';
  static const terms = 'https://wearthemood.com/legal/terms';
  static const acceptableUse = 'https://wearthemood.com/legal/acceptable-use';

  /// Community Guidelines — the hosted acceptable-use policy is the guidelines
  /// document (App Store UGC requirement: guidelines reachable in-app).
  static const guidelines = acceptableUse;

  /// Support contact (the store-listing contact address, STORE_LISTING.md).
  static const supportEmail = 'uprightseo24@gmail.com';
}
