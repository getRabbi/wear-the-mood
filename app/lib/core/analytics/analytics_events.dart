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

  // Phase 3 — the shopping catalog. The `try_on_*` names still have nothing
  // firing them (shopping try-on is Phase 5), so they are not declared yet: a
  // name with no emitter is a dashboard that silently reads zero forever.
  static const productImpression = 'product_impression';
  static const productSave = 'product_save';
  static const productUnsave = 'product_unsave';
  static const completeLookOpen = 'complete_look_open';
  static const searchOpen = 'search_open';
  static const searchSubmit = 'search_submit';
  static const filterApplied = 'filter_applied';
  static const savedOpen = 'saved_open';
  static const feedLoadMore = 'feed_load_more';

  // Phase 4 — Product Details and the tracked outbound click.
  //
  // `affiliateClick` is deliberately a SECOND name alongside the older
  // [affiliateLinkClicked], which fires on Offers and Newsroom. They measure
  // different things — one is a catalog product with a merchant, a placement
  // and a try-on state, the other is an editorial link — and merging them
  // would make the shopping funnel unreadable. Renaming the old one would
  // break every dashboard already built on it.
  static const productOpen = 'product_open';
  static const affiliateClick = 'affiliate_click';

  /// A Shop tap that did NOT reach a retailer, carrying a typed
  /// [DiscoverAnalyticsProps.failureCode].
  ///
  /// Its own event rather than a property on [affiliateClick]: the rollout
  /// alert is "redirect failures above 1% of click attempts" (§40), and a
  /// failure counted as a click would inflate the denominator it is measured
  /// against — the rate could only ever fall.
  static const affiliateClickFailed = 'affiliate_click_failed';
  static const productFeedback = 'product_feedback';

  // Phase 5 — shopping try-on. Distinct from [tryonStarted]/[tryonSucceeded],
  // which fire for EVERY try-on including closet renders. Merging them would
  // make the shopping funnel unreadable: the denominator of "try-on to shop
  // click" has to be try-ons of a product someone can actually buy.
  static const tryOnStart = 'try_on_start';
  static const tryOnComplete = 'try_on_complete';
  static const tryOnFail = 'try_on_fail';
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

  /// How many REAL content cards the composed Discover page carries, and
  /// whether that came out under [DiscoverPage.targetCards].
  ///
  /// A thin page is not an error — a young account, an empty region or a quiet
  /// news day all produce one honestly. These exist so a genuine content
  /// shortage shows up on a dashboard instead of on a device, and so the fix is
  /// aimed at the starved SOURCE rather than at the composer.
  static const cardCount = 'card_count';
  static const cardShortfall = 'card_shortfall';

  /// Giveaway cards on the composed page (rail + campaign together). Watched
  /// because "why is Discover all giveaways" is a content-mix regression that
  /// is invisible in a story count.
  static const giveawayCardCount = 'giveaway_card_count';
  static const newsCardCount = 'news_card_count';

  static const productId = 'product_id';
  static const merchantId = 'merchant_id';
  static const feedPlacement = 'feed_placement';
  static const matchReason = 'match_reason';
  static const resultCount = 'result_count';

  /// Whether a try-on preceded an outbound click — the conversion metric the
  /// shopping funnel turns on (§22 "Try-On-to-shop-click rate"). Always
  /// server-derived; the client never asserts it.
  static const tryOnCompleted = 'try_on_completed';

  /// Why a generation failed, as the backend's TYPED error code — never its
  /// human message, which is display text and may be reworded at any time.
  static const failureCode = 'failure_code';

  /// How MANY filters are set, and WHICH dimensions — never the user's actual
  /// budget, sizes or colours. A shopping budget is personal, and §22 forbids
  /// putting raw user content into analytics.
  static const filterCount = 'filter_count';
  static const filterKeys = 'filter_keys';
}
