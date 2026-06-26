/// Canonical outbound links used in share sheets (invites, giveaways).
///
/// The bundle id `com.fashionos.app` is fixed for the life of the app (CLAUDE.md
/// §6/§22), so the Play Store URL is stable. These are OUTBOUND only — tapping a
/// shared link installs/opens the store; in-app deep-link routing is a separate,
/// later piece (decided: outbound-only for now).
abstract final class AppLinks {
  static const androidStore =
      'https://play.google.com/store/apps/details?id=com.fashionos.app';
  static const website = 'https://wearthemood.com';
}
