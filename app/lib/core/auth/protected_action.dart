import '../router/routes.dart';

/// Every kind of thing a guest can *try* to do that needs a real account.
///
/// This enum is the vocabulary shared by all four enforcement layers — the UI
/// sheet, the router intercept, the controller/service guard and the pending
/// intent that resumes after sign-in — so the reason a guest was stopped is
/// carried end to end instead of being re-derived (and re-guessed) at each one.
///
/// Adding a value here does NOT grant anything: the guest allowlist lives in
/// `guest_capabilities.dart` and is a separate, deny-by-default list.
enum ProtectedAction {
  /// Any try-on entry: 2D, AI Couture, Try Look / full look, AI Enhance,
  /// Catalog Model Shot. They differ in cost and provider, not in whether they
  /// need an account — all of them create a job against a user.
  tryOn,

  /// Adding to, or editing, the digital wardrobe.
  closet,

  /// Choosing or capturing a person/body photo.
  bodyPhoto,

  /// Saving / favouriting a product to the account.
  saveProduct,

  /// Creating, editing or saving an outfit or a Saved Look.
  saveLook,

  /// Any community write: like, comment, post, follow, block, message.
  community,

  /// Entering a giveaway (viewing one is public).
  giveawayEntry,

  /// Creating or managing a giveaway listing.
  giveawayManage,

  /// The AI Stylist / Today's Look, which reads the wardrobe and writes signals.
  stylist,

  /// Profile creation and editing.
  profile,

  /// Subscriptions, top-ups and purchase restoration.
  purchase,

  /// Account settings, purchase history, private account data.
  accountSettings,

  /// Notification registration and private push content.
  notifications,

  /// Try-on history and privately generated results.
  history;

  /// Where a successful sign-in should land for this intent.
  ///
  /// For [tryOn] this is deliberately the START of the authenticated try-on
  /// flow, not a submit: resuming must never auto-select a photo, auto-consent,
  /// spend a credit or create a job. The user re-expresses the intent inside the
  /// real flow, with Consent v2 in its normal place.
  String get resumeRoute => switch (this) {
    ProtectedAction.tryOn => AppRoute.wtmMirror,
    ProtectedAction.closet => AppRoute.wtmClosetAdd,
    ProtectedAction.bodyPhoto => AppRoute.wtmBodyPhoto,
    ProtectedAction.saveProduct => AppRoute.wtmProduct,
    ProtectedAction.saveLook => AppRoute.wtmOutfits,
    ProtectedAction.community => AppRoute.wtmDiscover,
    ProtectedAction.giveawayEntry => AppRoute.wtmGiveawayDetail,
    ProtectedAction.giveawayManage => AppRoute.wtmGiveaways,
    ProtectedAction.stylist => AppRoute.wtmStylist,
    ProtectedAction.profile => AppRoute.wtmProfile,
    ProtectedAction.purchase => AppRoute.wtmPaywall,
    ProtectedAction.accountSettings => AppRoute.wtmSettings,
    ProtectedAction.notifications => AppRoute.wtmNotifPrefs,
    ProtectedAction.history => AppRoute.wtmTryOnHistory,
  };

  /// Whether the resume destination needs the public resource id that was
  /// captured when the guest was stopped (`?id=`). Only ever a PUBLIC id — a
  /// product or a giveaway — never a photo, a draft or anything private.
  bool get resumeNeedsResourceId => switch (this) {
    ProtectedAction.saveProduct || ProtectedAction.giveawayEntry => true,
    _ => false,
  };

  /// A stable, non-PII label for analytics + diagnostics.
  String get analyticsName => name;

  /// Maps a protected ROUTE a guest tried to reach (deep link, push, stale
  /// navigation) onto the action that explains it, so the conversion sheet says
  /// something specific instead of a generic "please sign in".
  ///
  /// Unknown protected routes fall back to [ProtectedAction.profile] — still
  /// denied, just with the most general copy. Returning null here would mean
  /// "allow", which is exactly the mistake this whole file exists to avoid.
  static ProtectedAction forRoute(String location) => switch (location) {
    AppRoute.wtmMirror ||
    AppRoute.wtmMirrorGarments ||
    AppRoute.wtmMirrorMode ||
    AppRoute.wtmMirrorGenerating ||
    AppRoute.wtmMirrorResult ||
    AppRoute.wtmMirrorAdjust => ProtectedAction.tryOn,
    AppRoute.wtmCloset ||
    AppRoute.wtmClosetAdd ||
    AppRoute.wtmClosetItem ||
    AppRoute.wtmClosetFixCutout => ProtectedAction.closet,
    AppRoute.wtmBodyPhoto => ProtectedAction.bodyPhoto,
    AppRoute.wtmSaved => ProtectedAction.saveProduct,
    AppRoute.wtmOutfits ||
    AppRoute.wtmOutfitDetail ||
    AppRoute.wtmLooks => ProtectedAction.saveLook,
    AppRoute.wtmTryOnHistory => ProtectedAction.history,
    AppRoute.wtmSocial ||
    AppRoute.wtmPost ||
    AppRoute.wtmCompose ||
    AppRoute.wtmUser ||
    AppRoute.wtmUserFollowers ||
    AppRoute.wtmUserFollowing ||
    AppRoute.wtmInbox => ProtectedAction.community,
    AppRoute.wtmGiveawayCreate ||
    AppRoute.wtmGiveawayChat => ProtectedAction.giveawayManage,
    AppRoute.wtmStylist ||
    AppRoute.wtmStylistLook ||
    AppRoute.wtmMoodPlanner ||
    AppRoute.wtmEvents => ProtectedAction.stylist,
    AppRoute.wtmPaywall => ProtectedAction.purchase,
    AppRoute.wtmNotifPrefs => ProtectedAction.notifications,
    _ => ProtectedAction.profile,
  };
}
