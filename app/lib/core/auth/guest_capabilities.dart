import '../router/routes.dart';

/// The complete list of things an iOS guest is allowed to do.
///
/// **Deny by default.** [GuestCapabilities.allows] answers false for anything
/// not named in [_allowed], and [ProtectedAction] (see `protected_action.dart`)
/// is the enum everything else goes through — so a capability nobody thought
/// about is locked, not open. A new feature has to be added here on purpose,
/// with a human deciding it is safe to show without an account.
///
/// The dividing line is simple and worth stating, because it is the argument
/// made to App Review: **public, already-published content is browsable; the
/// user's own life is not.** A product catalog, a news story and a giveaway's
/// rules are things WTM publishes to everyone. A photograph of the user's body,
/// their wardrobe, their credits, their saved looks and their conversations are
/// not — and none of them can even exist without an account to own them.
enum GuestCapability {
  /// The public Home experience (no personal modules, no protected reads).
  viewHome,

  /// Choose/preview a mood. Local only — no server write, no personalization
  /// signal, nothing recorded against an account.
  previewMood,

  /// Browse the Shop / Discover product catalog.
  browseShop,

  /// Search and filter that catalog.
  searchProducts,

  /// Open a product's details and description.
  viewProductDetail,

  /// Open the merchant's "Shop Now" link (leaves the app).
  openMerchantLink,

  /// Read Newsroom stories.
  readNewsroom,

  /// See a giveaway's public information and its mandatory rules.
  /// Entering one is [ProtectedAction.giveawayEntry] and is NOT this.
  viewGiveawayInfo,

  /// Legal, privacy, terms, support and app-information screens.
  viewLegal,

  /// The Virtual Try-On explanation. An honest feature preview built from copy
  /// and the app's own design system — never a fabricated "result", and never a
  /// generated image attributed to the guest.
  viewTryOnExplainer,
}

/// The allowlist itself. Anything absent is denied.
///
/// Kept as an explicit set (rather than "all enum values") so that adding a
/// value to [GuestCapability] without adding it here leaves it DENIED, which is
/// the failure direction we want. `guest_capabilities_test.dart` pins the exact
/// membership so a change to this set is always a deliberate, reviewed diff.
const Set<GuestCapability> _allowed = {
  GuestCapability.viewHome,
  GuestCapability.previewMood,
  GuestCapability.browseShop,
  GuestCapability.searchProducts,
  GuestCapability.viewProductDetail,
  GuestCapability.openMerchantLink,
  GuestCapability.readNewsroom,
  GuestCapability.viewGiveawayInfo,
  GuestCapability.viewLegal,
  GuestCapability.viewTryOnExplainer,
};

abstract final class GuestCapabilities {
  /// Whether an iOS guest may do [capability]. Deny-by-default.
  static bool allows(GuestCapability capability) =>
      _allowed.contains(capability);

  /// Read-only view of the allowlist, for tests and diagnostics.
  static Set<GuestCapability> get allowed => Set.unmodifiable(_allowed);

  /// Routes a guest may occupy.
  ///
  /// This is the ROUTER half of the same allowlist and it is matched by exact
  /// path, never by prefix. Prefix matching is how gates leak: `/wtm/closet`
  /// would have opened `/wtm/closet/add`, and `/wtm/newsroom` matching by
  /// prefix is fine only because every child under it is also public. Listing
  /// each one costs a line and removes the whole class of mistake.
  ///
  /// Notably ABSENT, and each for a reason:
  ///  * `/wtm/discover/saved` — saved products live on the account.
  ///  * `/wtm/closet/*`, `/wtm/mirror/*`, `/wtm/outfits*`, `/wtm/looks*` — the
  ///    user's own wardrobe, body photos, renders and looks. The two BRANCH
  ///    ROOTS `/wtm/closet` and `/wtm/mirror` are allowed, and show a preview.
  ///  * `/wtm/social/*`, `/wtm/user*`, `/wtm/inbox` — community and private mail.
  ///  * `/wtm/profile/*`, `/wtm/settings*`, `/wtm/paywall` — the account
  ///    itself. `/wtm/profile` itself is allowed and shows the guest preview,
  ///    because it is a nav TAB: a tab that bounces is a broken tab.
  ///  * `/wtm/giveaway-create`, `/wtm/giveaway-chat` — giveaway mutations.
  ///  * `/wtm/onboarding` — post-signup, and it writes to a profile.
  static const Set<String> publicRoutes = {
    // Entry / auth surfaces.
    AppRoute.wtmSplash,
    AppRoute.wtmWelcome,
    AppRoute.wtmAuth,
    AppRoute.setPassword,

    // Public browsing.
    AppRoute.wtmHome,

    // Two surfaces that a guest may OCCUPY but not use. Both render a feature
    // preview instead of the real screen (`GuestPreviewGate` at the route
    // builder), so the guest gets an explanation rather than a silent bounce
    // and the real screen never mounts — no provider initialises, no request
    // fires. Their children (`/wtm/closet/add`, `/wtm/mirror/garments`, …) are
    // NOT listed and stay denied, which is why this set is matched exactly and
    // never by prefix.
    AppRoute.wtmCloset,
    AppRoute.wtmMirror,
    AppRoute.wtmProfile,

    AppRoute.wtmDiscover,
    AppRoute.wtmShopSearch,
    AppRoute.wtmShopBrowse,
    AppRoute.wtmProduct,
    AppRoute.wtmNewsroom,
    AppRoute.wtmArticle,
    AppRoute.wtmArticleWeb,
    AppRoute.wtmGiveaways,
    AppRoute.wtmGiveawayDetail,
  };

  /// Whether a guest may occupy [location] (a matched route path, query and
  /// fragment already stripped by go_router's `matchedLocation`).
  static bool allowsRoute(String location) => publicRoutes.contains(location);
}
