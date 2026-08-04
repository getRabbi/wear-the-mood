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
  // Premium AI Studio (BUILD_PROMPT_PRO_PROMAX.md).
  static const aiStudioOpened = 'ai_studio_opened';
  static const aiEnhanceStarted = 'ai_enhance_started';
  static const catalogShotStarted = 'catalog_shot_started';
  static const studioModelTryonStarted = 'studio_model_tryon_started';
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
  static const dailyGuideViewed = 'daily_guide_viewed';
  static const dailyGuideOpened = 'daily_guide_opened';
  static const dailyGuideCtaClicked = 'daily_guide_cta_clicked';
  static const offerViewed = 'offer_viewed';
  static const giveawayListed = 'giveaway_listed';
  static const giveawayViewed = 'giveaway_viewed';
  static const giveawayClaimed = 'giveaway_claimed';
  static const giveawayClaimAccepted = 'giveaway_claim_accepted';
  static const giveawayClaimCancelled = 'giveaway_claim_cancelled';
  static const giveawayChatOpened = 'giveaway_chat_opened';
  static const giveawayChatMessageSent = 'giveaway_chat_message_sent';
  static const giveawayChatReported = 'giveaway_chat_reported';
  static const giveawayMarkedGiven = 'giveaway_marked_given';
  static const giveawayDeleted = 'giveaway_deleted';
  static const userFollowed = 'user_followed';
  static const challengeJoined = 'challenge_joined';
  static const trendClosetOpened = 'trend_closet_opened';
  static const paywallViewed = 'paywall_viewed';
  static const trialStarted = 'trial_started';
  static const subscriptionStarted = 'subscription_started';
  static const affiliateLinkClicked = 'affiliate_link_clicked';
  static const referralSent = 'referral_sent';
  static const accountDeleted = 'account_deleted';

  // ---- Discover (DISCOVER spec §22) ----
  // Phase 2 covers the Discover surface and its Stories rail. The product,
  // affiliate and try-on events in §22 land with the phases that build them —
  // a name here with nothing firing it would be a metric that silently reads
  // zero forever.
  static const discoverOpen = 'discover_open';
  static const discoverFeedLoaded = 'discover_feed_loaded';
  static const discoverFeedFailed = 'discover_feed_failed';
  static const discoverStoryImpression = 'discover_story_impression';
  static const discoverStoryOpen = 'discover_story_open';
  static const discoverStorySeen = 'discover_story_seen';
  static const discoverStoryAction = 'discover_story_action';
  static const discoverStoryClose = 'discover_story_close';
}

/// Property keys for the Discover events (§22 "useful parameters").
///
/// Centralised for the same reason the event names are: a typo in a property
/// key does not fail anywhere, it just produces a dimension that is empty in
/// every dashboard.
///
/// Nothing here may carry a body-photo URL, a private closet image URL or any
/// other raw user content (§22, §36). Story ids and typed codes only.
abstract final class DiscoverAnalyticsProps {
  static const storyType = 'story_type';
  static const storyId = 'story_id';
  static const storyCount = 'story_count';
  static const storyIndex = 'feed_position';
  static const trackingToken = 'tracking_token';
  static const destination = 'destination';
  static const failedSources = 'failed_sources';
  static const partial = 'partial';
}
