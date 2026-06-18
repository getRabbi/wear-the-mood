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
}
