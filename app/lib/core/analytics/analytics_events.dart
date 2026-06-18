/// PostHog event names — `noun_verb`, snake_case (CLAUDE.md §15).
/// The single source of truth for event names; never inline raw strings.
abstract final class AnalyticsEvents {
  static const appOpened = 'app_opened';
  static const onboardingCompleted = 'onboarding_completed';
  static const consentGranted = 'consent_granted';
  static const avatarCreated = 'avatar_created';
  static const tryonStarted = 'tryon_started';
  static const tryonSucceeded = 'tryon_succeeded';
  static const tryonShared = 'tryon_shared';
  static const wardrobeItemAdded = 'wardrobe_item_added';
  static const outfitCreated = 'outfit_created';
  static const stylistQueried = 'stylist_queried';
  static const dailySuggestionOpened = 'daily_suggestion_opened';
  static const postCreated = 'post_created';
  static const postEdited = 'post_edited';
  static const postLiked = 'post_liked';
  static const pollCreated = 'poll_created';
  static const pollVoted = 'poll_voted';
  static const quizStarted = 'quiz_started';
  static const quizCompleted = 'quiz_completed';
  static const quizResultShared = 'quiz_result_shared';
  static const userFollowed = 'user_followed';
  static const challengeJoined = 'challenge_joined';
  static const trendClosetOpened = 'trend_closet_opened';
  static const paywallViewed = 'paywall_viewed';
  static const trialStarted = 'trial_started';
  static const subscriptionStarted = 'subscription_started';
  static const affiliateLinkClicked = 'affiliate_link_clicked';
  static const referralSent = 'referral_sent';
  static const accountDeleted = 'account_deleted';
}
