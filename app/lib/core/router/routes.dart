/// Centralized route paths + names for type-safe navigation and deep links.
/// Add new routes here as features land (CLAUDE.md §3 feature list).
abstract final class AppRoute {
  static const home = '/';
  static const homeName = 'home';
  static const tryon = '/tryon';
  static const tryonName = 'tryon';
  static const tryonHistory = '/tryon/history';
  static const tryonHistoryName = 'tryonHistory';
  static const tryon2dEditor = '/tryon/2d';
  static const tryon2dEditorName = 'tryon2dEditor';
  static const aiLooks = '/studio/looks';
  static const aiLooksName = 'aiLooks';
  static const wardrobe = '/wardrobe';
  static const wardrobeName = 'wardrobe';
  static const wardrobeAdd = '/wardrobe/add';
  static const wardrobeAddName = 'wardrobeAdd';
  static const wardrobeItem = '/wardrobe/item';
  static const wardrobeItemName = 'wardrobeItem';
  static const wardrobeCategorize = '/wardrobe/categorize';
  static const wardrobeCategorizeName = 'wardrobeCategorize';
  static const wardrobeDrawerName = 'wardrobeDrawer';
  static const wardrobeInsights = '/wardrobe/insights';
  static const wardrobeInsightsName = 'wardrobeInsights';
  static const stylist = '/stylist';
  static const stylistName = 'stylist';
  static const socialCompose = '/social/compose';
  static const socialComposeName = 'socialCompose';
  static const styleQuiz = '/quiz';
  static const styleQuizName = 'styleQuiz';
  static const dailyGuide = '/guide';
  static const dailyGuideName = 'dailyGuide';
  static const giveawayCreate = '/giveaways/create';
  static const giveawayCreateName = 'giveawayCreate';
  static const giveawayDetail = '/giveaways/detail';
  static const giveawayDetailName = 'giveawayDetail';
  static const giveawaysMine = '/giveaways/mine';
  static const giveawaysMineName = 'giveawaysMine';
  static const challenges = '/challenges';
  static const challengesName = 'challenges';
  static const leaderboard = '/community/leaderboard';
  static const leaderboardName = 'leaderboard';
  static const challengeDetailName = 'challengeDetail';
  static const news = '/news';
  static const newsName = 'news';
  static const referrals = '/referrals';
  static const referralsName = 'referrals';
  static const packing = '/packing';
  static const packingName = 'packing';
  static const calendar = '/calendar';
  static const calendarName = 'calendar';
  static const outfits = '/outfits';
  static const outfitsName = 'outfits';
  static const outfitsCreate = '/outfits/create';
  static const outfitsCreateName = 'outfitsCreate';
  static const outfitsDetail = '/outfits/detail';
  static const outfitsDetailName = 'outfitsDetail';
  static const auth = '/auth';
  static const authName = 'auth';
  static const setPassword = '/set-password';
  static const setPasswordName = 'setPassword';
  static const notifications = '/notifications';
  static const notificationsName = 'notifications';
  static const profile = '/profile';
  static const profileName = 'profile';
  // Public creator profiles (CLAUDE.md §1 pillar 4). `/user/:userId` with
  // `followers` / `following` sub-routes.
  static const userProfile = '/user';
  static const userProfileName = 'userProfile';
  static const userFollowersName = 'userFollowers';
  static const userFollowingName = 'userFollowing';

  /// Path to a creator's public profile.
  static String userProfilePath(String userId) => '/user/$userId';
  static const avatar = '/avatar';
  static const avatarName = 'avatar';
  static const accountDetails = '/account-details';
  static const accountDetailsName = 'accountDetails';
  static const paywall = '/paywall';
  static const paywallName = 'paywall';

  /// DEV-ONLY (debug builds): WTM component gallery (UI_IMPLEMENTATION.md P0).
  static const devGallery = '/dev/gallery';
  static const devGalleryName = 'devGallery';

  // ---- WTM Atelier shell (UI_IMPLEMENTATION.md §2/§8) ----
  // The new-UI route table, namespaced under /wtm while the rebuild runs
  // parallel to the shipped app (debug-only until cutover). P1 registers every
  // §8 destination as a stub; later phases replace stubs with real screens at
  // these same paths.
  static const wtmHome = '/wtm/home';
  static const wtmHomeName = 'wtmHome';
  static const wtmSocial = '/wtm/social';
  static const wtmSocialName = 'wtmSocial';
  static const wtmInbox = '/wtm/inbox';
  static const wtmInboxName = 'wtmInbox';
  static const wtmProfile = '/wtm/profile';
  static const wtmProfileName = 'wtmProfile';
  static const wtmProfileEdit = '/wtm/profile/edit';
  static const wtmProfileEditName = 'wtmProfileEdit';
  static const wtmProfileSaved = '/wtm/profile/saved';
  static const wtmProfileSavedName = 'wtmProfileSaved';
  static const wtmReferral = '/wtm/referral';
  static const wtmReferralName = 'wtmReferral';
  static const wtmNotifPrefs = '/wtm/settings/notifications';
  static const wtmNotifPrefsName = 'wtmNotifPrefs';
  static const wtmSettings = '/wtm/settings';
  static const wtmSettingsName = 'wtmSettings';
  // MoodMirror flow (§2 LOCKED order). Steps keep the nav; generating/result/
  // adjust are full-bleed.
  static const wtmMirror = '/wtm/mirror';
  static const wtmMirrorName = 'wtmMirror';
  static const wtmMirrorGarments = '/wtm/mirror/garments';
  static const wtmMirrorGarmentsName = 'wtmMirrorGarments';
  static const wtmMirrorMode = '/wtm/mirror/mode';
  static const wtmMirrorModeName = 'wtmMirrorMode';
  static const wtmMirrorGenerating = '/wtm/mirror/generating';
  static const wtmMirrorGeneratingName = 'wtmMirrorGenerating';
  static const wtmMirrorResult = '/wtm/mirror/result';
  static const wtmMirrorResultName = 'wtmMirrorResult';
  static const wtmMirrorAdjust = '/wtm/mirror/adjust';
  static const wtmMirrorAdjustName = 'wtmMirrorAdjust';
  static const wtmCloset = '/wtm/closet';
  static const wtmClosetName = 'wtmCloset';
  static const wtmClosetItem = '/wtm/closet/item';
  static const wtmClosetItemName = 'wtmClosetItem';
  static const wtmClosetAdd = '/wtm/closet/add';
  static const wtmClosetAddName = 'wtmClosetAdd';
  static const wtmClosetFixCutout = '/wtm/closet/fix-cutout';
  static const wtmClosetFixCutoutName = 'wtmClosetFixCutout';
  static const wtmStylist = '/wtm/stylist';
  static const wtmStylistName = 'wtmStylist';
  static const wtmStylistLook = '/wtm/stylist/look';
  static const wtmStylistLookName = 'wtmStylistLook';
  static const wtmOutfits = '/wtm/outfits';
  static const wtmOutfitsName = 'wtmOutfits';
  static const wtmOutfitDetail = '/wtm/outfits/detail';
  static const wtmOutfitDetailName = 'wtmOutfitDetail';
  static const wtmLooks = '/wtm/looks';
  static const wtmLooksName = 'wtmLooks';
  static const wtmGiveaways = '/wtm/giveaways';
  static const wtmGiveawaysName = 'wtmGiveaways';
  static const wtmGiveawayDetail = '/wtm/giveaways/detail';
  static const wtmGiveawayDetailName = 'wtmGiveawayDetail';
  static const wtmGiveawayCreate = '/wtm/giveaway-create';
  static const wtmGiveawayCreateName = 'wtmGiveawayCreate';
  static const wtmGiveawayChat = '/wtm/giveaway-chat';
  static const wtmGiveawayChatName = 'wtmGiveawayChat';
  static const wtmOffers = '/wtm/offers';
  static const wtmOffersName = 'wtmOffers';
  static const wtmOfferDetail = '/wtm/offers/detail';
  static const wtmOfferDetailName = 'wtmOfferDetail';
  static const wtmNewsroom = '/wtm/newsroom';
  static const wtmNewsroomName = 'wtmNewsroom';
  static const wtmArticle = '/wtm/newsroom/article';
  static const wtmArticleName = 'wtmArticle';
  static const wtmSearch = '/wtm/search';
  static const wtmSearchName = 'wtmSearch';
  static const wtmBodyPhoto = '/wtm/body-photo';
  static const wtmBodyPhotoName = 'wtmBodyPhoto';
  static const wtmBrandStore = '/wtm/brand-store';
  static const wtmBrandStoreName = 'wtmBrandStore';
  static const wtmPost = '/wtm/social/post';
  static const wtmPostName = 'wtmPost';
  static const wtmCompose = '/wtm/social/compose';
  static const wtmComposeName = 'wtmCompose';
  static const wtmUser = '/wtm/user';
  static const wtmUserName = 'wtmUser';
  static const wtmUserFollowers = '/wtm/user/followers';
  static const wtmUserFollowersName = 'wtmUserFollowers';
  static const wtmUserFollowing = '/wtm/user/following';
  static const wtmUserFollowingName = 'wtmUserFollowing';
  static const wtmPaywall = '/wtm/paywall';
  static const wtmPaywallName = 'wtmPaywall';

  // Auth & onboarding (UI_IMPLEMENTATION.md §3.A) — the WTM-styled entry flow.
  static const wtmSplash = '/wtm/splash';
  static const wtmSplashName = 'wtmSplash';
  static const wtmAuth = '/wtm/auth';
  static const wtmAuthName = 'wtmAuth';
  static const wtmOnboarding = '/wtm/onboarding';
  static const wtmOnboardingName = 'wtmOnboarding';
}
