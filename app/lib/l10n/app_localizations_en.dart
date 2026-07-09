// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Wear The Mood';

  @override
  String get appTagline => 'Your personal Fashion OS';

  @override
  String get phase0Tagline => 'Phase 0 — Foundations';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get loadingGiveaways => 'Loading giveaways…';

  @override
  String get loadingCommunity => 'Loading community…';

  @override
  String get loadingNotifications => 'Loading notifications…';

  @override
  String get loadingProfile => 'Loading profile…';

  @override
  String get commonAdd => 'Add';

  @override
  String get errorGenericTitle => 'Something went wrong';

  @override
  String get emptyGenericTitle => 'Nothing here yet';

  @override
  String get homeGreetingMorning => 'GOOD MORNING';

  @override
  String get homeGreetingAfternoon => 'GOOD AFTERNOON';

  @override
  String get homeGreetingEvening => 'GOOD EVENING';

  @override
  String get homeTryOnTitle => 'Try it on';

  @override
  String get homeTryOnSubtitle => 'See any piece on you before you buy.';

  @override
  String get homeStartTryOn => 'Start a try-on';

  @override
  String get tryOnAppBarTitle => 'Try-on';

  @override
  String get tryonHistoryTitle => 'Try-on history';

  @override
  String get tryonHistoryError => 'Couldn\'t load your try-ons';

  @override
  String get tryonHistoryEmptyTitle => 'No try-ons yet';

  @override
  String get tryonHistoryEmptyMessage =>
      'Your try-on results will show up here.';

  @override
  String get tryonHistoryStart => 'Start a try-on';

  @override
  String get tryOnPickTitle => 'Pick a piece';

  @override
  String get tryOnPickSubtitle =>
      'Pick a piece from your wardrobe to see it on you.';

  @override
  String get tryOnNoGarmentsTitle => 'Your wardrobe is empty';

  @override
  String get tryOnNoGarmentsMessage =>
      'Add clothes to your wardrobe, then try them on yourself.';

  @override
  String get tryOnAddClothes => 'Add clothes';

  @override
  String get tryOnAvatarPrompt =>
      'Set up your avatar to try clothes on yourself';

  @override
  String get tryOnCta => 'Try it on';

  @override
  String get tryOnQueued => 'In the queue…';

  @override
  String get tryOnProcessing => 'Styling your look…';

  @override
  String get tryOnResultTitle => 'Your look';

  @override
  String get tryOnResultStubNote =>
      'Preview uses a placeholder model until real try-on is enabled.';

  @override
  String get tryOnTryAnother => 'Try another';

  @override
  String get tryOnShare => 'Share';

  @override
  String get tryOnShareComingSoon => 'Sharing is coming soon.';

  @override
  String get tryOnErrorTitle => 'Couldn\'t finish the try-on';

  @override
  String get tryOnBlockedTitle => 'Can\'t use this photo';

  @override
  String get tryOnBlockedMessage =>
      'Please choose a different photo for try-on.';

  @override
  String get tryOnOutOfCredits => 'You\'ve used all your free AI try-ons.';

  @override
  String get navHome => 'Home';

  @override
  String get navWardrobe => 'Wardrobe';

  @override
  String get wardrobeEmptyTitle => 'Your closet is empty';

  @override
  String get wardrobeEmptyMessage =>
      'Add pieces you own to mix, match and try on.';

  @override
  String get wardrobeAdd => 'Add a piece';

  @override
  String get wardrobeComingSoon => 'Adding items is coming soon.';

  @override
  String get wardrobeErrorTitle => 'Couldn\'t load your closet';

  @override
  String get wardrobeDeleteTitle => 'Remove this piece?';

  @override
  String get wardrobeDeleteBody =>
      'It\'ll be removed from your closet. This can\'t be undone.';

  @override
  String get wardrobeDeleteConfirm => 'Remove';

  @override
  String get wardrobeDeleteCancel => 'Cancel';

  @override
  String get wardrobeDeleted => 'Removed from your closet';

  @override
  String get wardrobeDeleteError => 'Couldn\'t remove that. Please try again.';

  @override
  String get addItemTitle => 'Add a piece';

  @override
  String get addItemChoosePhoto => 'Add a photo of your piece';

  @override
  String get addItemCamera => 'Camera';

  @override
  String get addItemGallery => 'Gallery';

  @override
  String get addItemNameLabel => 'Name (optional)';

  @override
  String get addItemCategoryLabel => 'Category';

  @override
  String get addItemCatTops => 'Tops';

  @override
  String get addItemCatBottoms => 'Bottoms';

  @override
  String get addItemCatOuterwear => 'Outerwear';

  @override
  String get addItemCatShoes => 'Shoes';

  @override
  String get addItemCatAccessories => 'Accessories';

  @override
  String get addItemSave => 'Add to closet';

  @override
  String get addPieceHowTitle => 'Choose how to add this piece';

  @override
  String get addPieceRemoveBgTitle => 'Remove background';

  @override
  String get addPieceRemoveBgSub => 'Free · quick closet item';

  @override
  String get addPieceEnhanceTitle => 'AI Enhance';

  @override
  String get addPieceEnhanceSub => 'Pro / Pro Max · credits used';

  @override
  String get addPieceEnhanceDesc => 'Make it clean, sharp and catalog-ready.';

  @override
  String addPieceEnhanceCta(int credits) {
    String _temp0 = intl.Intl.pluralLogic(
      credits,
      locale: localeName,
      other: '$credits credits',
      one: '1 credit',
    );
    return 'Enhance & add · $_temp0';
  }

  @override
  String get addPieceEnhanceLocked =>
      'Upgrade to Pro or Pro Max to use AI Enhance.';

  @override
  String get addPieceEnhanceStarted => 'Added — enhancing your piece…';

  @override
  String get addPieceProcessingHint => 'This takes a few seconds — hang tight.';

  @override
  String get wardrobeEnhancingBadge => 'Enhancing…';

  @override
  String get wardrobeEnhanceItem => 'Enhance item';

  @override
  String get wardrobeEnhanceStarted => 'Enhancing your piece…';

  @override
  String get wardrobeEnhanceError =>
      'Couldn\'t start enhancing. Please try again.';

  @override
  String get aiUploadDisclaimer =>
      'Only upload photos you own or have permission to use. AI results may not perfectly match fabric, color, logo, or fit.';

  @override
  String aiCreditConfirm(int credits) {
    String _temp0 = intl.Intl.pluralLogic(
      credits,
      locale: localeName,
      other: '$credits credits',
      one: '1 credit',
    );
    return 'This will use $_temp0. AI results may slightly change fabric, color, logo, or texture.';
  }

  @override
  String get closetShowOnModel => 'Show on model';

  @override
  String get catalogTitle => 'Catalog Model Shot';

  @override
  String get catalogSubtitle => 'See this piece on an AI fashion model.';

  @override
  String get catalogStyleLabel => 'Model style';

  @override
  String get catalogStyleStudio => 'Studio';

  @override
  String get catalogStyleStreetwear => 'Streetwear';

  @override
  String get catalogStyleModest => 'Modest';

  @override
  String get catalogStyleLuxury => 'Luxury';

  @override
  String get catalogStyleCropped => 'Cropped face';

  @override
  String get catalogQualityLabel => 'Quality';

  @override
  String get catalogQualityStandard => 'Pro Standard';

  @override
  String get catalogQualityHd => 'Pro Max HD';

  @override
  String catalogGenerateCta(int credits) {
    String _temp0 = intl.Intl.pluralLogic(
      credits,
      locale: localeName,
      other: '$credits credits',
      one: '1 credit',
    );
    return 'Generate · $_temp0';
  }

  @override
  String get catalogProTitle => 'Catalog shots are a Pro feature';

  @override
  String get catalogProBody =>
      'Upgrade to Pro or Pro Max to put your pieces on AI fashion models.';

  @override
  String get catalogGenerating => 'Creating your model shot…';

  @override
  String get catalogResultTitle => 'Your model shot';

  @override
  String get catalogSavedNote => 'Saved to your AI Looks.';

  @override
  String get catalogError => 'Couldn\'t create that. Your credit was refunded.';

  @override
  String get aiLooksTitle => 'AI Looks';

  @override
  String get aiLooksEmpty => 'Your AI-generated looks will appear here.';

  @override
  String get aiLooksReport => 'Report image';

  @override
  String get aiLooksDelete => 'Delete';

  @override
  String get aiLooksSave => 'Save';

  @override
  String get aiLooksShare => 'Share';

  @override
  String get aiLooksDeleted => 'Removed from AI Looks';

  @override
  String get aiLooksReported => 'Reported. Thanks for flagging.';

  @override
  String get aiLooksError => 'Couldn\'t load your AI Looks.';

  @override
  String get aiStudioTitle => 'AI Studio';

  @override
  String get aiStudioSubtitle =>
      'Enhance pieces, create model shots, and try looks on studio models.';

  @override
  String get aiStudioOpen => 'Open Studio';

  @override
  String get aiStudioEnhance => 'Enhance an item';

  @override
  String get aiStudioEnhanceSub => 'Make a piece clean and catalog-ready';

  @override
  String get aiStudioCatalog => 'Create model shot';

  @override
  String get aiStudioCatalogSub => 'Show a piece on an AI model';

  @override
  String get aiStudioTryStudio => 'Try on studio model';

  @override
  String get aiStudioTryStudioSub => 'See looks on a studio model';

  @override
  String get aiStudioViewLooks => 'View AI Looks';

  @override
  String get aiStudioViewLooksSub => 'Your saved AI-generated images';

  @override
  String get aiStudioMyModel => 'My Style Model';

  @override
  String get aiStudioMyModelSub =>
      'Create a reusable model inspired by your look.';

  @override
  String get aiStudioComingSoon => 'Coming soon';

  @override
  String get tierFree => 'Free';

  @override
  String get tierPro => 'Pro';

  @override
  String get tierProMax => 'Pro Max';

  @override
  String get addItemSaved => 'Added to your closet';

  @override
  String get addItemError => 'Couldn\'t add that. Please try again.';

  @override
  String get addItemPickError => 'Couldn\'t load that photo. Try another.';

  @override
  String get addItemRemovePhoto => 'Remove photo';

  @override
  String get addItemProcessingPhoto => 'Processing photo…';

  @override
  String get addItemReplacePhoto => 'Replace';

  @override
  String get wardrobeProcessing => 'Processing';

  @override
  String get wardrobeRemovingBackground => 'Removing background';

  @override
  String get wardrobeStillWorking => 'Still working — tap to refresh';

  @override
  String get wardrobeProcessingHint =>
      'Cleaning up your photo — just a few seconds';

  @override
  String get wardrobeSearchHint => 'Search your closet';

  @override
  String get wardrobeSearchEmptyTitle => 'No matches';

  @override
  String get wardrobeSearchEmptyMessage =>
      'Try a different word — a color, type or vibe.';

  @override
  String get commonClear => 'Clear';

  @override
  String get outfitsTitle => 'Outfits';

  @override
  String get outfitsEmptyTitle => 'No outfits yet';

  @override
  String get outfitsEmptyMessage =>
      'Combine pieces you own into looks you can reuse.';

  @override
  String get outfitsErrorTitle => 'Couldn\'t load your outfits';

  @override
  String get outfitsCreate => 'Create outfit';

  @override
  String get outfitsUntitled => 'Outfit';

  @override
  String outfitsPieceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pieces',
      one: '1 piece',
    );
    return '$_temp0';
  }

  @override
  String get outfitsDeleteTitle => 'Remove this outfit?';

  @override
  String get outfitsDeleteBody =>
      'It\'ll be removed from your saved looks. This can\'t be undone.';

  @override
  String get outfitsDeleteConfirm => 'Remove';

  @override
  String get outfitsDeleteCancel => 'Cancel';

  @override
  String get outfitsDeleted => 'Outfit removed';

  @override
  String get outfitsDeleteError => 'Couldn\'t remove that. Please try again.';

  @override
  String get createOutfitTitle => 'New outfit';

  @override
  String get createOutfitNameLabel => 'Name (optional)';

  @override
  String get createOutfitPickTitle => 'Pick pieces';

  @override
  String get createOutfitPickSubtitle =>
      'Tap items to add them to this outfit.';

  @override
  String get createOutfitSave => 'Save outfit';

  @override
  String get createOutfitSaved => 'Outfit saved';

  @override
  String get createOutfitError => 'Couldn\'t save. Please try again.';

  @override
  String get createOutfitNoItemsMessage =>
      'Add pieces to your closet first, then combine them into outfits.';

  @override
  String get homeClosetTitle => 'Your closet';

  @override
  String get homeSeeAll => 'See all';

  @override
  String get homeClosetEmpty => 'No pieces yet';

  @override
  String get homeStylistTitle => 'Today\'s stylist';

  @override
  String get homeStylistSubtitle => 'Your daily outfit, picked for you.';

  @override
  String get homeComingSoon => 'Coming soon';

  @override
  String get stylistAppBarTitle => 'Today\'s stylist';

  @override
  String get stylistIntroTitle => 'What do I wear today?';

  @override
  String get stylistIntroBody =>
      'Get an outfit picked from your closet for today\'s weather and your taste.';

  @override
  String get stylistStyleMe => 'Style me';

  @override
  String get stylistStyleAgain => 'Style me again';

  @override
  String get stylistLoading => 'Putting together your look…';

  @override
  String get stylistErrorTitle => 'Couldn\'t style you';

  @override
  String get stylistEmptyTitle => 'Your closet is empty';

  @override
  String get stylistEmptyMessage =>
      'Add a few pieces and I\'ll put an outfit together for you.';

  @override
  String get navSocial => 'Community';

  @override
  String get feedTitle => 'Community';

  @override
  String get communityTitle => 'Community';

  @override
  String get communityTabFeed => 'Community';

  @override
  String get communityTabNews => 'Newsroom';

  @override
  String get leaderboardTitle => 'Style leaderboard';

  @override
  String get leaderboardBannerSubtitle => 'Win a free month of Premium';

  @override
  String get leaderboardPrize =>
      'Top stylist this month wins a free month of Premium';

  @override
  String leaderboardDaysLeft(int days) {
    return '$days days left this month';
  }

  @override
  String get leaderboardYourRank => 'Your rank';

  @override
  String get leaderboardYouUnranked => 'Share a look to join the board';

  @override
  String leaderboardScore(int score) {
    return '$score pts';
  }

  @override
  String get leaderboardYouLabel => 'You';

  @override
  String get leaderboardEmpty => 'No scores yet this month — be the first!';

  @override
  String get leaderboardError => 'Couldn\'t load the leaderboard';

  @override
  String get leaderboardPastWinners => 'Past winners';

  @override
  String get leaderboardHowTooltip => 'How points work';

  @override
  String get leaderboardHowTitle => 'How points work';

  @override
  String get leaderboardHowIntro =>
      'Climb the monthly Style Score by sharing looks the community loves.';

  @override
  String get leaderboardHowPost => 'Post a look';

  @override
  String get leaderboardHowLike => 'Each like your look gets';

  @override
  String get leaderboardHowComment => 'Each comment your look gets';

  @override
  String leaderboardHowPoints(int points) {
    return '+$points';
  }

  @override
  String get leaderboardHowNoSelf =>
      'Only other people\'s likes and comments count — you can\'t boost your own.';

  @override
  String get leaderboardHowMonthly =>
      'Scores cover this calendar month and reset on the 1st. Standings update live; ties share a rank.';

  @override
  String get feedCompose => 'Share a look';

  @override
  String get feedEmptyTitle => 'No posts yet';

  @override
  String get feedEmptyMessage =>
      'Share your first look — your outfits, on the community.';

  @override
  String get feedErrorTitle => 'Couldn\'t load the feed';

  @override
  String get socialSomeone => 'Someone';

  @override
  String get socialFollow => 'Follow';

  @override
  String socialFollowing(String name) {
    return 'You\'re following $name';
  }

  @override
  String get socialActionError => 'Couldn\'t do that. Please try again.';

  @override
  String get postLike => 'Like';

  @override
  String get postDelete => 'Delete post';

  @override
  String get postEdit => 'Edit post';

  @override
  String get postEditedLabel => 'edited';

  @override
  String get postDeleteTitle => 'Delete this post?';

  @override
  String get postDeleteBody =>
      'It\'ll be removed from the community. This can\'t be undone.';

  @override
  String get postDeleteConfirm => 'Delete';

  @override
  String get postDeleteCancel => 'Cancel';

  @override
  String get postDeleted => 'Post removed';

  @override
  String get postDeleteError => 'Couldn\'t remove that. Please try again.';

  @override
  String get postReport => 'Report post';

  @override
  String get socialBlock => 'Block user';

  @override
  String get reportTitle => 'Report this post?';

  @override
  String get reportBody =>
      'Our team will review it. Thanks for helping keep the community safe.';

  @override
  String get reportConfirm => 'Report';

  @override
  String get reported =>
      'Reported. Thanks for helping keep the community safe.';

  @override
  String get blockTitle => 'Block this user?';

  @override
  String get blockBody =>
      'You won\'t see their posts, and they won\'t see yours.';

  @override
  String get blockConfirm => 'Block';

  @override
  String get blocked => 'You won\'t see that user anymore';

  @override
  String get commentBlocked => 'That comment can\'t be posted.';

  @override
  String get composeTitle => 'Share a look';

  @override
  String get composeEditTitle => 'Edit post';

  @override
  String get composeSaveChanges => 'Save changes';

  @override
  String get composeEditSaved => 'Post updated';

  @override
  String get composeAddPoll => 'Add a poll';

  @override
  String get composePollIncomplete =>
      'Add a question and at least 2 options to share your poll.';

  @override
  String get composePollQuestion => 'Poll question';

  @override
  String get composePollQuestionHint => 'Ask the community something';

  @override
  String composePollOption(int number) {
    return 'Option $number';
  }

  @override
  String get composePollAddOption => 'Add option';

  @override
  String get pollClosed => 'Poll closed';

  @override
  String pollTotalVotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votes',
      one: '1 vote',
      zero: 'No votes yet',
    );
    return '$_temp0';
  }

  @override
  String get pollVoteError => 'Couldn\'t record your vote. Please try again.';

  @override
  String get quizHomeTitle => 'Discover your Style DNA';

  @override
  String get quizHomeCardTitle => 'What\'s your Style DNA?';

  @override
  String get quizHomeCardBody => 'Take a 1-minute quiz to reveal your style.';

  @override
  String get quizStart => 'Take the quiz';

  @override
  String quizProgress(int current, int total) {
    return '$current of $total';
  }

  @override
  String get quizResultTitle => 'Your Style DNA';

  @override
  String get quizShare => 'Share to Community';

  @override
  String get quizSave => 'Save';

  @override
  String get quizSaved => 'Saved to your profile';

  @override
  String get quizRetake => 'Retake quiz';

  @override
  String get quizError => 'Couldn\'t load the quiz. Please try again.';

  @override
  String get quizSubmitError =>
      'Couldn\'t compute your result. Please try again.';

  @override
  String get quizProfileEmpty =>
      'Take the Style Quiz to reveal your Style DNA.';

  @override
  String get communityTabGiveaway => 'Giveaway';

  @override
  String get communityTabOffers => 'Offers';

  @override
  String get giveawayEmptyTitle => 'No giveaways yet';

  @override
  String get giveawayEmptyMessage =>
      'Free pieces shared by the community will show up here.';

  @override
  String get giveawayList => 'List an item';

  @override
  String get giveawayMine => 'My giveaways';

  @override
  String get giveawayPromoTitle =>
      'Sharing is caring — give your loved clothes a second home.';

  @override
  String get giveawayPromoSubtitle =>
      'One person\'s closet clear-out is another\'s favourite find. Pass it on, for free.';

  @override
  String get giveawayMineEmpty => 'You haven\'t listed anything yet.';

  @override
  String get giveawayCreateTitle => 'Give it away';

  @override
  String get giveawayFieldTitle => 'What are you giving away?';

  @override
  String get giveawayFieldDescription => 'Description (optional)';

  @override
  String get giveawayFieldSize => 'Size';

  @override
  String get giveawayFieldCategory => 'Category';

  @override
  String get giveawayFieldCondition => 'Condition';

  @override
  String get giveawayFieldArea => 'Area (e.g. neighbourhood)';

  @override
  String get giveawayAddPhoto => 'Add photo';

  @override
  String get giveawayPublish => 'Publish listing';

  @override
  String get giveawayPublished => 'Your giveaway is live';

  @override
  String get giveawayPublishError =>
      'Couldn\'t publish that. Please try again.';

  @override
  String get giveawayDisclaimer =>
      'Exchanges are between members — Fashion OS isn\'t a party to them. Keep chat in-app, never share your address or phone in a listing, and meet in a safe public place.';

  @override
  String get giveawayClaim => 'I want this';

  @override
  String get giveawayClaimMessage => 'Message to the owner (optional)';

  @override
  String get giveawayClaimSend => 'Send request';

  @override
  String get giveawayClaimed => 'Request sent';

  @override
  String get giveawayClaimError => 'Couldn\'t send that. Please try again.';

  @override
  String get giveawayClaimsTitle => 'Requests';

  @override
  String get giveawayNoClaims => 'No requests yet.';

  @override
  String get giveawayAccept => 'Accept';

  @override
  String get giveawayDecline => 'Decline';

  @override
  String get giveawayClose => 'Close listing';

  @override
  String get giveawayStatusAvailable => 'Available';

  @override
  String get giveawayStatusPending => 'Pending pickup';

  @override
  String get giveawayStatusGiven => 'Given away';

  @override
  String get giveawayStatusCancelled => 'Cancelled';

  @override
  String get giveawayManageStatus => 'Manage status';

  @override
  String get giveawayMarkPending => 'Mark pending pickup';

  @override
  String get giveawayMarkGiven => 'Mark given away';

  @override
  String get giveawayReopen => 'Reopen giveaway';

  @override
  String get giveawayCancel => 'Cancel giveaway';

  @override
  String get giveawayStatusUpdated => 'Status updated';

  @override
  String get giveawayClosedNote =>
      'This giveaway is closed. It stays viewable, but requests are off.';

  @override
  String get giveawayPrivacyNote =>
      'For your privacy, avoid sharing phone numbers, email, or your full address publicly. Contact through the app first, and share personal details only with people you trust.';

  @override
  String get giveawayReport => 'Report listing';

  @override
  String get giveawayShareText =>
      'Check out this giveaway on Wear The Mood — free fashion finds from the style community.';

  @override
  String get giveawayClaimPending => 'Request sent — waiting for the owner.';

  @override
  String get giveawayClaimAcceptedNote =>
      'Accepted! Arrange pickup with the owner in-app.';

  @override
  String get giveawayError => 'Couldn\'t load this. Please try again.';

  @override
  String giveawayRequestsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count requests',
      one: '1 request',
      zero: 'Free · be the first',
    );
    return '$_temp0';
  }

  @override
  String get offersStripTitle => 'Offers';

  @override
  String get offersStripSubtitle => 'Curated deals — affiliate links';

  @override
  String get offersErrorTitle => 'Couldn\'t load offers';

  @override
  String get offersEmptyTitle => 'No offers right now';

  @override
  String get offersEmptyMessage => 'Check back soon for fresh deals.';

  @override
  String get offersShopNow => 'Shop deal';

  @override
  String get guideTodayTitle => 'Today';

  @override
  String get guideRead => 'Read';

  @override
  String get composeCaptionLabel => 'Say something (optional)';

  @override
  String get composePickOutfit => 'Choose an outfit to share';

  @override
  String get composeSourcePhoto => 'Photo';

  @override
  String get composeSourceOutfit => 'Outfit';

  @override
  String get composeTagsLabel => 'Tags';

  @override
  String get composeTagsHint => 'e.g. ootd, streetwear';

  @override
  String get composeNoOutfitsTitle => 'No outfits yet';

  @override
  String get composeNoOutfits =>
      'Create an outfit first, then share it with the community.';

  @override
  String get composeShare => 'Share';

  @override
  String get composeShared => 'Shared to the community';

  @override
  String get composeError => 'Couldn\'t share. Please try again.';

  @override
  String get composeBlocked => 'That image can\'t be posted.';

  @override
  String get composeCaptionEmail =>
      'Please don\'t include email addresses in public posts.';

  @override
  String get commentsTitle => 'Comments';

  @override
  String get commentsEmpty => 'No comments yet';

  @override
  String get commentsErrorTitle => 'Couldn\'t load comments';

  @override
  String get commentHint => 'Add a comment…';

  @override
  String get commentError => 'Couldn\'t post your comment.';

  @override
  String get feedChallenges => 'Challenges';

  @override
  String get challengesTitle => 'Challenges';

  @override
  String get challengesEmptyTitle => 'No challenges yet';

  @override
  String get challengesEmptyMessage =>
      'Check back soon — new style challenges drop here.';

  @override
  String get challengesErrorTitle => 'Couldn\'t load challenges';

  @override
  String challengeEntriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
      zero: 'No entries yet',
    );
    return '$_temp0';
  }

  @override
  String get challengeJoinedBadge => 'Entered';

  @override
  String get challengeEntriesTitle => 'Entries';

  @override
  String get challengeEntriesEmpty => 'Be the first to enter this challenge.';

  @override
  String get challengeEnter => 'Enter this challenge';

  @override
  String get challengeErrorTitle => 'Couldn\'t load this challenge';

  @override
  String get challengeJoined => 'You\'re in! Your look is entered.';

  @override
  String get challengeJoinError =>
      'Couldn\'t enter the challenge. Please try again.';

  @override
  String composeEnterHeading(String title) {
    return 'Share a look to enter “$title”';
  }

  @override
  String get newsTitle => 'Fashion news';

  @override
  String get newsEmptyTitle => 'No news yet';

  @override
  String get newsEmptyMessage =>
      'Fresh fashion news and trends will land here soon.';

  @override
  String get newsErrorTitle => 'Couldn\'t load the news';

  @override
  String get newsOpenError => 'Couldn\'t open the article.';

  @override
  String get homeNewsTitle => 'Fashion news';

  @override
  String get homeNewsSubtitle => 'Trends, drops and industry buzz.';

  @override
  String get trendClosetAction => 'In your closet';

  @override
  String get newsShopAction => 'Shop this trend';

  @override
  String get wardrobeMarkWorn => 'Mark as worn today';

  @override
  String get wardrobeRemove => 'Remove';

  @override
  String get wardrobeWornLogged => 'Logged a wear';

  @override
  String get wardrobeActionError => 'Couldn\'t do that. Please try again.';

  @override
  String get insightsTitle => 'Wardrobe insights';

  @override
  String get insightsErrorTitle => 'Couldn\'t load your insights';

  @override
  String get insightsEmptyTitle => 'No insights yet';

  @override
  String get insightsEmptyMessage =>
      'Add pieces and log wears to see your cost-per-wear.';

  @override
  String get insightsItems => 'Items';

  @override
  String get insightsSpend => 'Total spend';

  @override
  String get insightsTotalWears => 'Total wears';

  @override
  String get insightsAvgPerWear => 'Avg / wear';

  @override
  String get insightsNeverWornCount => 'Unworn';

  @override
  String get insightsMostWorn => 'Most worn';

  @override
  String get insightsBestValue => 'Best value';

  @override
  String get insightsBiggestWaste => 'Biggest waste';

  @override
  String get insightsNeverWorn => 'Never worn';

  @override
  String insightsPerWear(String value) {
    return '$value/wear';
  }

  @override
  String insightsWears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wears',
      one: '1 wear',
    );
    return '$_temp0';
  }

  @override
  String get insightsGapsTitle => 'Fill the gaps';

  @override
  String get insightsGapMissing => 'Not in your closet yet';

  @override
  String get insightsGapShop => 'Shop';

  @override
  String get insightsGapShopError => 'Couldn\'t open the shop link.';

  @override
  String get profileInvite => 'Invite friends';

  @override
  String get referralTitle => 'Invite friends';

  @override
  String get referralHeadline => 'Give credits, get credits';

  @override
  String referralSubtitle(int credits) {
    return 'You and a friend each get $credits free try-ons when they join with your code.';
  }

  @override
  String get referralYourCode => 'Your code';

  @override
  String get referralShare => 'Share invite';

  @override
  String get referralCopied => 'Invite copied — paste it to a friend';

  @override
  String referralCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count friends have joined',
      one: '1 friend has joined',
    );
    return '$_temp0';
  }

  @override
  String get referralRedeemTitle => 'Have a code?';

  @override
  String get referralRedeemHint => 'Enter a referral code';

  @override
  String get referralRedeem => 'Redeem';

  @override
  String referralRedeemSuccess(int credits) {
    return 'You earned $credits credits!';
  }

  @override
  String get referralRedeemError =>
      'Couldn\'t redeem that code. It may be invalid, your own, or already used.';

  @override
  String get referralErrorTitle => 'Couldn\'t load referrals';

  @override
  String referralShareText(String code) {
    return 'Join me on Wear The Mood — try clothes on before you buy. Use my code $code when you sign up and we both get free try-ons!';
  }

  @override
  String get homePackingTitle => 'Pack for a trip';

  @override
  String get homePackingSubtitle => 'A smart packing list from your closet.';

  @override
  String get packingTitle => 'Packing planner';

  @override
  String get packingDaysLabel => 'Trip length';

  @override
  String packingDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get packingOccasionHint => 'Occasion (optional) — beach, work trip…';

  @override
  String get packingCta => 'Pack my bag';

  @override
  String get packingIntro =>
      'Pick your trip length and I\'ll pack a versatile list from your closet.';

  @override
  String get packingErrorTitle => 'Couldn\'t plan your trip';

  @override
  String get calendarTitle => 'Plan my week';

  @override
  String get calendarIntro =>
      'Add your upcoming events and I\'ll suggest an outfit for each.';

  @override
  String get calendarAddHint => 'Add an event — e.g. Work meeting, Dinner';

  @override
  String get calendarImport => 'Import from calendar';

  @override
  String get calendarImportSoon => 'Calendar import is coming soon.';

  @override
  String get calendarPlan => 'Plan my outfits';

  @override
  String get calendarErrorTitle => 'Couldn\'t plan your week';

  @override
  String get trendClosetTitle => 'Your closet for this trend';

  @override
  String get trendClosetEmptyTitle => 'No matches yet';

  @override
  String get trendClosetEmptyMessage =>
      'Pieces from your wardrobe will appear here as your closet is analyzed.';

  @override
  String get trendClosetErrorTitle => 'Couldn\'t match your closet';

  @override
  String get onboardingValue1Title => 'See it on you';

  @override
  String get onboardingValue1Body =>
      'Try any look on yourself with MoodMirror before you buy.';

  @override
  String get onboardingValue2Title => 'Your closet, digitized';

  @override
  String get onboardingValue2Body =>
      'Organize what you own and mix new outfits.';

  @override
  String get onboardingValue3Title => 'Your daily stylist';

  @override
  String get onboardingValue3Body =>
      'Outfit ideas from your wardrobe, the weather and your taste.';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingConsentTitle => 'Before we start';

  @override
  String get onboardingConsentBody =>
      'Wear The Mood uses your photos and body details only to create your avatar and try-ons. Raw inputs are deleted after processing — never sold.';

  @override
  String get onboardingConsentAgree => 'I agree — let\'s go';

  @override
  String get authSignInTitle => 'Welcome back';

  @override
  String get authSignUpTitle => 'Create your account';

  @override
  String get authSignInSubtitle =>
      'Sign in to your existing account to continue.';

  @override
  String get authSignUpSubtitle =>
      'New here? Create an account with your email to get started.';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authConfirmPassword => 'Confirm password';

  @override
  String get authPasswordMismatch => 'Passwords don\'t match.';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authSignUp => 'Sign up';

  @override
  String get authSignInCta => 'Log in';

  @override
  String get authSignUpCta => 'Create account';

  @override
  String get authToggleToSignUp => 'New here? Create an account';

  @override
  String get authToggleToSignIn => 'Already have an account? Sign in';

  @override
  String get authGoogle => 'Continue with Google';

  @override
  String get authEmailInvalid => 'Enter a valid email.';

  @override
  String get authPasswordTooShort => 'Password must be at least 8 characters.';

  @override
  String get authGenericError => 'Couldn\'t sign you in. Please try again.';

  @override
  String get authCheckEmail =>
      'Account created — check your email to confirm, then sign in.';

  @override
  String get authErrorInvalidCredentials =>
      'Incorrect email or password. Please try again.';

  @override
  String get authErrorEmailNotConfirmed =>
      'Please confirm your email first — check your inbox for the link.';

  @override
  String get authErrorEmailRegistered =>
      'That email is already registered. Try signing in instead.';

  @override
  String get authErrorWeakPassword =>
      'Choose a stronger password (at least 8 characters).';

  @override
  String get authErrorRateLimited =>
      'Too many attempts. Please wait a moment and try again.';

  @override
  String get authErrorSignupDisabled => 'New sign-ups are currently disabled.';

  @override
  String get authErrorNetwork =>
      'Can\'t reach the server. Check your connection and try again.';

  @override
  String get welcomeSubtitle =>
      'Sign in to try on looks, build your closet, and get styled every day.';

  @override
  String get profileTitle => 'Profile';

  @override
  String profileSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String get profileGuestTitle => 'You\'re browsing as a guest';

  @override
  String get profileGuestSubtitle => 'Sign in to save your wardrobe and looks.';

  @override
  String get profileSignIn => 'Sign in';

  @override
  String get profileSignOut => 'Sign out';

  @override
  String get profileSectionLegal => 'Privacy & legal';

  @override
  String get profileSectionAccount => 'Account';

  @override
  String get profilePrivacy => 'Privacy policy';

  @override
  String get profileTerms => 'Terms of service';

  @override
  String get profileAcceptableUse => 'Acceptable use policy';

  @override
  String get profileAvatar => 'Body & try-on photo';

  @override
  String get avatarTitle => 'Body & try-on photo';

  @override
  String get avatarPhotoTip =>
      'For try-on, use a full-body photo — stand facing the camera in good light with a plain background. A face-only selfie won\'t work for trying on clothes.';

  @override
  String get avatarLoadError => 'Couldn\'t load your profile';

  @override
  String get avatarConsentTitle => 'Use your photo for try-on';

  @override
  String get avatarConsentBody =>
      'We use your photo and the body details you share only to show clothes on you and suggest outfits. They\'re stored privately, never sold, and you can delete them anytime. Face and body data may be treated as biometric information.';

  @override
  String get avatarConsentAgree => 'I agree & continue';

  @override
  String get avatarConsentError =>
      'Couldn\'t record consent. Please try again.';

  @override
  String get avatarHeightLabel => 'Height';

  @override
  String get avatarBodyTypeLabel => 'Body type';

  @override
  String get avatarBodySlim => 'Slim';

  @override
  String get avatarBodyAverage => 'Average';

  @override
  String get avatarBodyAthletic => 'Athletic';

  @override
  String get avatarBodyCurvy => 'Curvy';

  @override
  String get avatarBodyPlus => 'Plus';

  @override
  String get avatarSave => 'Save';

  @override
  String get avatarSaved => 'Saved';

  @override
  String get avatarError => 'Couldn\'t save. Please try again.';

  @override
  String get avatarPrivacyNote =>
      'Stored privately. Delete anytime from your account.';

  @override
  String get avatarSectionPhoto => 'Try-on photo';

  @override
  String get avatarSectionBody => 'Body details';

  @override
  String get avatarGuideTitle => 'Take the perfect try-on photo';

  @override
  String get avatarGuideSubtitle =>
      'We place clothes on this photo, so your whole body must be visible.';

  @override
  String get avatarGuideDo1 => 'Stand straight — head to feet in frame';

  @override
  String get avatarGuideDo2 => 'Plain background, good lighting';

  @override
  String get avatarGuideDo3 => 'Face the camera, arms slightly away';

  @override
  String get avatarGuideDo4 => 'Fitted clothes, not baggy';

  @override
  String get avatarGuideDo5 => 'Just you — one person';

  @override
  String get avatarGuideDont =>
      'Avoid close-ups, cut-off mirror shots, or group photos.';

  @override
  String get avatarGuideFormats =>
      'Works with JPG, PNG, and iPhone (HEIC) photos.';

  @override
  String get avatarGuideExampleGood => 'Good example';

  @override
  String get avatarRetake => 'Retake';

  @override
  String get avatarChecking => 'Checking your photo…';

  @override
  String get avatarCheckOk => 'Looks great — full body detected.';

  @override
  String get avatarCheckNoPerson =>
      'We couldn\'t find a person. Use a clear full-body photo.';

  @override
  String get avatarCheckHead =>
      'Your head isn\'t fully in frame. Include head to feet.';

  @override
  String get avatarCheckFeet =>
      'Your feet aren\'t visible. Step back so the whole body shows.';

  @override
  String get avatarCheckFailGeneric =>
      'That photo won\'t work for try-on. Please try another.';

  @override
  String get avatarGenderLabel => 'Gender';

  @override
  String get avatarGenderFemale => 'Female';

  @override
  String get avatarGenderMale => 'Male';

  @override
  String get avatarGenderNonBinary => 'Non-binary';

  @override
  String get avatarGenderPreferNot => 'Prefer not to say';

  @override
  String get avatarHeightUnitCm => 'cm';

  @override
  String get avatarHeightUnitFt => 'ft/in';

  @override
  String get avatarHeightFeet => 'ft';

  @override
  String get avatarHeightInches => 'in';

  @override
  String get avatarBodyPetite => 'Petite';

  @override
  String get avatarBodyTall => 'Tall';

  @override
  String get avatarBodyHourglass => 'Hourglass';

  @override
  String get avatarBodyPear => 'Pear';

  @override
  String get avatarBodyApple => 'Apple';

  @override
  String get avatarBodyRectangle => 'Rectangle';

  @override
  String get avatarBodyMuscular => 'Muscular';

  @override
  String get avatarBodyBroad => 'Broad';

  @override
  String get avatarBodyLean => 'Lean';

  @override
  String get avatarBodyStocky => 'Stocky';

  @override
  String get avatarFitLabel => 'Fit preference';

  @override
  String get avatarFitSlim => 'Slim';

  @override
  String get avatarFitRegular => 'Regular';

  @override
  String get avatarFitRelaxed => 'Relaxed';

  @override
  String get avatarOptionalNote =>
      'Optional — improves fit and styling suggestions.';

  @override
  String get avatarWeightLabel => 'Weight (kg)';

  @override
  String get avatarAgeLabel => 'Age range';

  @override
  String get avatarAgeUnder18 => 'Under 18';

  @override
  String get avatarAge1824 => '18–24';

  @override
  String get avatarAge2534 => '25–34';

  @override
  String get avatarAge3544 => '35–44';

  @override
  String get avatarAge4554 => '45–54';

  @override
  String get avatarAge55Plus => '55+';

  @override
  String get avatarSkinToneLabel => 'Skin tone';

  @override
  String get avatarSkinFair => 'Fair';

  @override
  String get avatarSkinLight => 'Light';

  @override
  String get avatarSkinMedium => 'Medium';

  @override
  String get avatarSkinOlive => 'Olive';

  @override
  String get avatarSkinBrown => 'Brown';

  @override
  String get avatarSkinDeep => 'Deep';

  @override
  String get profilePictureLabel => 'Profile picture';

  @override
  String get profilePictureHint =>
      'Any photo you like — this is separate from your try-on photo.';

  @override
  String get profilePictureSaved => 'Profile picture updated';

  @override
  String get profilePictureError =>
      'Couldn\'t update your picture. Please try again.';

  @override
  String get profilePictureRemove => 'Remove photo';

  @override
  String get profilePictureRemoved => 'Profile picture removed';

  @override
  String get commonDone => 'Done';

  @override
  String get profilePersonalDetails => 'Personal details';

  @override
  String get accountDetailsTitle => 'Personal details';

  @override
  String get accountSectionProfile => 'Profile';

  @override
  String get accountSectionSecurity => 'Sign-in & security';

  @override
  String get accountNameLabel => 'Display name';

  @override
  String get accountPhoneLabel => 'Phone';

  @override
  String get accountBioLabel => 'Bio';

  @override
  String get accountBioHint => 'Tell people about your style…';

  @override
  String get accountStyleTagsLabel => 'Style tags';

  @override
  String get accountStyleTagsHint => 'Comma-separated, e.g. modest, minimal';

  @override
  String get accountPublicTitle => 'Public profile';

  @override
  String get accountPublicSubtitle =>
      'When on, others can open your profile and see your bio, looks and style tags.';

  @override
  String get profileVisibilityPublic => 'Public';

  @override
  String get profileVisibilityPrivate => 'Private';

  @override
  String get accountSave => 'Save changes';

  @override
  String get accountSaved => 'Saved';

  @override
  String get accountSaveError => 'Couldn\'t save. Please try again.';

  @override
  String get accountEmailLabel => 'New email';

  @override
  String accountEmailCurrent(String email) {
    return 'Signed in as $email';
  }

  @override
  String get accountChangeEmail => 'Change email';

  @override
  String get accountEmailNote =>
      'We\'ll send a confirmation link to the new address; the change applies once you confirm.';

  @override
  String get accountEmailChanged =>
      'Check your new email to confirm the change.';

  @override
  String get accountPasswordLabel => 'New password';

  @override
  String get accountChangePassword => 'Change password';

  @override
  String get accountPasswordChanged => 'Password updated.';

  @override
  String get accountPasswordTooShort => 'Use at least 8 characters.';

  @override
  String get accountCurrentPasswordLabel => 'Current password';

  @override
  String get accountCurrentPasswordWrong => 'Current password is incorrect.';

  @override
  String get accountAuthError =>
      'Couldn\'t update. Please sign in again and retry.';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authForgotTitle => 'Reset password';

  @override
  String get authForgotBody => 'Enter your email and we\'ll send a reset link.';

  @override
  String get authForgotSend => 'Send link';

  @override
  String get authForgotSent => 'Check your email for a reset link.';

  @override
  String get setPasswordTitle => 'Set a new password';

  @override
  String get setPasswordCta => 'Update password';

  @override
  String get avatarGalleryAdd => 'Add photo';

  @override
  String get avatarGalleryHint =>
      'Tap a photo to use it for try-on. Add a few and keep your best.';

  @override
  String get avatarGalleryEmpty =>
      'Add a full-body photo to try clothes on yourself.';

  @override
  String avatarQualityBadge(int score) {
    return 'Quality $score';
  }

  @override
  String get avatarSelectedBadge => 'Active';

  @override
  String get wtmBodyModelsLabel => 'Or use a model';

  @override
  String get wtmBodyModelsHint =>
      'Try clothes on a studio model or the mannequin — no photo needed.';

  @override
  String get wtmBodyMannequin => 'Mannequin';

  @override
  String get wtmBodyModelsSoon => 'Studio models arrive soon.';

  @override
  String get avatarPhotoDeleteTitle => 'Remove photo?';

  @override
  String get avatarPhotoDeleteBody => 'This try-on photo will be deleted.';

  @override
  String get avatarPhotoDeleted => 'Photo removed';

  @override
  String get avatarPhotoDeleteError => 'Couldn\'t remove. Please try again.';

  @override
  String get profileLinkError => 'Couldn\'t open the link.';

  @override
  String get profileExportData => 'Export my data';

  @override
  String get profileDeleteAccount => 'Delete account & data';

  @override
  String get profileDeleteConfirmTitle => 'Delete your account?';

  @override
  String get profileDeleteConfirmBody =>
      'This permanently removes your account, wardrobe and looks. This can\'t be undone.';

  @override
  String get profileCancel => 'Cancel';

  @override
  String get profileComingSoon => 'This is coming soon.';

  @override
  String get profileExportDone => 'Your data was copied to the clipboard';

  @override
  String get profileExportError =>
      'Couldn\'t export your data. Please try again.';

  @override
  String get profileDeleteDone => 'Your account and data have been deleted';

  @override
  String get profileDeleteError =>
      'Couldn\'t delete your account. Please try again.';

  @override
  String get paywallTitle => 'Unlock everything';

  @override
  String get paywallSubtitle =>
      'Unlimited AI try-ons, your whole closet organized, and HD looks with no watermark — your style OS, fully unlocked.';

  @override
  String get paywallFeatureUnlimited => 'Unlimited MoodMirror try-ons';

  @override
  String get paywallFeatureHd => 'HD results & video reels';

  @override
  String get paywallFeatureWardrobe => 'Unlimited wardrobe';

  @override
  String get paywallFeatureStylist => 'Advanced AI stylist';

  @override
  String get paywallFeaturePriority => 'Priority processing';

  @override
  String get paywallBestValue => 'BEST VALUE';

  @override
  String get paywallActiveTitle => 'You\'re Premium';

  @override
  String get paywallActiveBody =>
      'You have full access to Wear The Mood. Manage your plan in the app store.';

  @override
  String get paywallPerYear => 'per year';

  @override
  String get paywallPerMonth => 'per month';

  @override
  String paywallTrialNote(int days, String price) {
    return '$days-day free trial, then $price. Cancel anytime.';
  }

  @override
  String get paywallCta => 'Start free trial';

  @override
  String get paywallRestore => 'Restore purchases';

  @override
  String get paywallMaybeLater => 'Maybe later';

  @override
  String get paywallComingSoon => 'Subscriptions are coming soon.';

  @override
  String get paywallSetupRequired =>
      'Subscriptions aren\'t available yet — AI Try-On already works with your free daily credits, and 2D try-on is always free.';

  @override
  String get paywallSetupBadge => 'Subscriptions setup pending';

  @override
  String paywallPriceNote(String price) {
    return '$price · billed via Google Play. Cancel anytime.';
  }

  @override
  String get paywallUnavailableTitle => 'Purchases unavailable';

  @override
  String get paywallUnavailableBody =>
      'Premium isn\'t available to purchase right now. You can still use AI Try-On with your daily credits, and 2D try-on is always free.';

  @override
  String get paywallCreditsNote =>
      'Your first 3 AI realistic try-ons are free — Premium unlocks unlimited, forever.';

  @override
  String get paywallRestoreNothing => 'No previous purchases to restore.';

  @override
  String get paywallSeePlans => 'See plans';

  @override
  String get profilePremium => 'Fashion OS Premium';

  @override
  String creditsChipFree(int count) {
    return '$count free';
  }

  @override
  String creditsChipBalance(int count) {
    return '$count credits';
  }

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonClose => 'Close';

  @override
  String get commonShare => 'Share';

  @override
  String get commonContinue => 'Continue';

  @override
  String get navCloset => 'Closet';

  @override
  String get navTryOn => 'Try-On';

  @override
  String get homeStylistReady => 'Your AI stylist is ready';

  @override
  String get homeHelloMorning => 'Good morning';

  @override
  String get homeHelloAfternoon => 'Good afternoon';

  @override
  String get homeHelloEvening => 'Good evening';

  @override
  String homeGreetingName(String greeting, String name) {
    return '$greeting, $name';
  }

  @override
  String get homeHeroTitle => 'MoodMirror';

  @override
  String get homeHeroSubtitle =>
      'See clothes on your body before you wear them.';

  @override
  String get homeHeroCta => 'Open MoodMirror';

  @override
  String get homeHeroUpload => 'Upload clothing';

  @override
  String get homeQuickActions => 'Quick actions';

  @override
  String get homeQaTryOnTitle => 'Try on clothes';

  @override
  String get homeQaTryOnSub => 'See it on you instantly';

  @override
  String get homeQaOutfitTitle => 'Build outfit';

  @override
  String get homeQaOutfitSub => 'Mix & match your closet';

  @override
  String get homeQaStylistTitle => 'Today\'s stylist';

  @override
  String get homeQaStylistSub => 'Your daily look';

  @override
  String get homeQaPackTitle => 'Pack for a trip';

  @override
  String get homeQaPackSub => 'Smart packing list';

  @override
  String homeClosetItemsCount(int count) {
    return '$count items added';
  }

  @override
  String get homeBuildClosetTitle => 'Build your digital closet';

  @override
  String get homeBuildClosetSub => 'Add clothes to unlock styling and try-on.';

  @override
  String get homeAddFirstItem => 'Add first item';

  @override
  String get homeSuggestionsTitle => 'AI Suggestions';

  @override
  String get homeSuggestionStyleTop =>
      'Style a top with tailored bottoms for a sharp look.';

  @override
  String get homeSuggestionAddShoes =>
      'Add shoes to complete more of your outfits.';

  @override
  String get homeSuggestionNeedBottoms =>
      'Your closet could use a few more bottoms.';

  @override
  String get homeSuggestionStartCloset =>
      'Add a few pieces and I\'ll start styling you.';

  @override
  String get homeTrendingTitle => 'Trending looks';

  @override
  String get homeTrendingSub => 'Fresh from the community';

  @override
  String get homeTryThisLook => 'Try this look';

  @override
  String get closetTitle => 'Closet';

  @override
  String closetSubtitle(int items, int outfits) {
    return '$items items · $outfits outfits';
  }

  @override
  String get closetSearchHint => 'Search your closet';

  @override
  String get closetCatAll => 'All';

  @override
  String get closetCatTops => 'Tops';

  @override
  String get closetCatBottoms => 'Bottoms';

  @override
  String get closetCatDresses => 'Dresses';

  @override
  String get closetCatOuterwear => 'Outerwear';

  @override
  String get closetCatShoes => 'Shoes';

  @override
  String get closetCatBags => 'Bags';

  @override
  String get closetCatAccessories => 'Accessories';

  @override
  String get closetCatFavorites => 'Favorites';

  @override
  String get closetTryOn => 'Try on';

  @override
  String get closetStyleIt => 'Style it';

  @override
  String get closetAiOrganize => 'AI organize';

  @override
  String get closetAiOrganizeSoon => 'AI organize is coming soon.';

  @override
  String get closetFavorited => 'Added to favorites';

  @override
  String get closetUnfavorited => 'Removed from favorites';

  @override
  String get closetUncategorized => 'Uncategorized';

  @override
  String get closetTapToCategorize => 'Tap to categorize';

  @override
  String get closetTabWardrobe => 'Wardrobe';

  @override
  String get closetTabAllItems => 'All Items';

  @override
  String get closetTabOutfits => 'Outfits';

  @override
  String get wardrobeHangingRail => 'Hanging Rail';

  @override
  String get wardrobeDrawersShelves => 'Drawers & Shelves';

  @override
  String get wardrobeFavorites => 'Favorites';

  @override
  String get wardrobeSavedOutfits => 'Saved Outfits';

  @override
  String get wardrobeUnsorted => 'Unsorted';

  @override
  String get wardrobeCreateDrawer => 'New drawer';

  @override
  String wardrobeItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'Empty',
    );
    return '$_temp0';
  }

  @override
  String get drawerDetailSearchHint => 'Search this drawer';

  @override
  String get drawerSortRecent => 'Recently added';

  @override
  String get drawerSortWorn => 'Most worn';

  @override
  String get drawerSortFavorites => 'Favorites first';

  @override
  String get drawerEmptyTitle => 'This drawer is empty';

  @override
  String drawerEmptyMessage(String name) {
    return 'Add your first item to $name.';
  }

  @override
  String get drawerAddItem => 'Add item';

  @override
  String get drawerStyleThis => 'Style this drawer';

  @override
  String get drawerStyleThisSoon =>
      'Outfit ideas for this drawer are coming soon.';

  @override
  String get drawerRename => 'Rename';

  @override
  String get drawerEditAction => 'Edit drawer';

  @override
  String get drawerDeleteAction => 'Delete drawer';

  @override
  String get drawerDeleteConfirmTitle => 'Delete this drawer?';

  @override
  String get drawerDeleteConfirmBody =>
      'Your items stay in the closet — only the drawer is removed.';

  @override
  String get drawerDeleteConfirm => 'Delete';

  @override
  String get drawerCreateTitle => 'New drawer';

  @override
  String get drawerEditTitle => 'Edit drawer';

  @override
  String get drawerNameLabel => 'Drawer name';

  @override
  String get drawerNameHint => 'e.g. Summer, Gym, Office';

  @override
  String get drawerIconLabel => 'Icon';

  @override
  String get drawerColorLabel => 'Accent color';

  @override
  String get drawerSave => 'Save drawer';

  @override
  String get drawerNameRequired => 'Give your drawer a name.';

  @override
  String get drawerMoveTitle => 'Move to drawer';

  @override
  String drawerAssigned(String name) {
    return 'Moved to $name';
  }

  @override
  String get drawerCreated => 'Drawer created';

  @override
  String get addItemDrawerLabel => 'Add to drawer';

  @override
  String get addItemDrawerSuggested => 'Suggested';

  @override
  String get closetMissingPiecesTitle => 'Missing pieces';

  @override
  String get closetCleanupTitle => 'Closet clean-up';

  @override
  String closetCleanupBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items need a category or name',
      one: '1 item needs a category or name',
    );
    return '$_temp0';
  }

  @override
  String get closetCleanupReview => 'Review';

  @override
  String get closetColorMap => 'Color map';

  @override
  String get closetColorMapSoon => 'Color tagging is coming soon.';

  @override
  String get profileStatDrawers => 'Drawers';

  @override
  String get profileSectionPremium => 'Premium';

  @override
  String get profileSectionDanger => 'Danger zone';

  @override
  String get closetDetailTryOnMe => 'Try on me';

  @override
  String get closetDetailFavorite => 'Favorite';

  @override
  String get closetDetailUnfavorite => 'Unfavorite';

  @override
  String get closetDetailPairsTitle => 'Pairs well with';

  @override
  String get closetDetailPairsValue =>
      'Neutral bottoms, a light jacket and clean sneakers.';

  @override
  String get closetDetailBestForTitle => 'Best for';

  @override
  String get closetDetailBestForValue => 'Casual · Workwear · Travel';

  @override
  String get closetDetailRelated => 'More from your closet';

  @override
  String get tryOnLandingTitle => 'MoodMirror';

  @override
  String get tryOnLandingSubtitle => 'Three steps to see any piece on you.';

  @override
  String get tryOnBodyTitle => 'Choose try-on body';

  @override
  String get tryOnBodySubtitle => 'Try on your own photo or a studio model.';

  @override
  String get tryOnBodyMyPhoto => 'My photo';

  @override
  String get tryOnBodyStudioModel => 'Studio model';

  @override
  String get tryOnStudioPickHint => 'Pick a studio model to continue.';

  @override
  String get tryOnStudioComingSoon => 'Studio models are coming soon.';

  @override
  String get tryOnStudioComingSoonBody =>
      'We\'re curating a set of studio models you can try clothes on. Check back soon.';

  @override
  String get tryOnStudioProTitle => 'Studio models are a Pro feature';

  @override
  String get tryOnStudioProBody =>
      'Upgrade to Pro or Pro Max to try clothes on curated studio models.';

  @override
  String get tryOnStudioSelected => 'Studio model selected';

  @override
  String get tryOnStepPhotoTitle => 'Choose your photo';

  @override
  String get tryOnStepPhotoSub => 'Use your try-on photo or add a new one.';

  @override
  String get tryOnStepClothingTitle => 'Choose clothing';

  @override
  String get tryOnStepClothingSub => 'Pick from your closet or upload.';

  @override
  String get tryOnStepModeTitle => 'Pick a try-on mode';

  @override
  String get tryOnStepModeSub => '2D preview or realistic AI.';

  @override
  String get tryOnStepGenerateTitle => 'Generate your look';

  @override
  String get tryOnStepGenerateSub => 'We render it in seconds.';

  @override
  String get tryOnGenerate2d => 'Generate 2D preview';

  @override
  String get tryOnGenerateAi => 'Generate AI look';

  @override
  String get tryOn2dFreeHint => 'Free — no credits used';

  @override
  String get tryOn2dResultTitle => 'MoodMirror 2D Preview';

  @override
  String get tryOn2dResultNote => 'On-device preview — adjust anytime.';

  @override
  String get tryOn2dEditorTitle => 'Adjust your look';

  @override
  String get tryOn2dHint => 'Drag, pinch and rotate to fit';

  @override
  String get tryOn2dHintCanvas => 'Pinch to zoom · pick a piece to edit';

  @override
  String get tryOn2dHintEdit => 'Drag to place · tap photo to zoom';

  @override
  String get tryOn2dFit => 'Fit to screen';

  @override
  String get tryOn2dDone => 'Done';

  @override
  String get tryOn2dCenter => 'Center';

  @override
  String get tryOn2dReset => 'Reset';

  @override
  String get tryOn2dResetAll => 'Reset all';

  @override
  String get tryOn2dResetAllDone => 'All pieces reset to smart fit';

  @override
  String get tryOn2dFlip => 'Flip';

  @override
  String get tryOn2dToggleVisible => 'Show / hide';

  @override
  String get tryOn2dColor => 'Colour';

  @override
  String get tryOn2dColorOriginal => 'Original';

  @override
  String get tryOn2dColorMono => 'Mono';

  @override
  String get tryOn2dLook => 'Look';

  @override
  String get tryOn2dLookNone => 'None';

  @override
  String get tryOn2dLookWarm => 'Warm';

  @override
  String get tryOn2dLookCool => 'Cool';

  @override
  String get tryOn2dMannequin => 'Mannequin';

  @override
  String get tryOn2dUpgradeHd => 'See it in HD — AI Realistic';

  @override
  String get tryOn2dBackground => 'Background';

  @override
  String get tryOn2dBgPhoto => 'Your photo';

  @override
  String get tryOn2dBgStudio => 'Studio';

  @override
  String get tryOn2dBgGradient => 'Gradient';

  @override
  String get tryOn2dBgEditorial => 'Editorial';

  @override
  String get tryOn2dSaved => 'Saved to your looks';

  @override
  String get tryOn2dCaptureError =>
      'Couldn\'t create the preview. Please try again.';

  @override
  String get tryOnMode2dTitle => '2D Try-On';

  @override
  String get tryOnMode2dSub => 'Fast preview · free for everyone';

  @override
  String get tryOnModeAiTitle => 'AI Realistic Try-On';

  @override
  String get tryOnModeAiSub => 'HD · realistic fabric & body fit';

  @override
  String get tryOnBadgeFree => 'Free';

  @override
  String get tryOnBadgePremium => 'Premium';

  @override
  String get tryOnGuideTitle => 'How to take the perfect photo';

  @override
  String get tryOnGuideFullBody => 'Full body visible, head to feet';

  @override
  String get tryOnGuidePlainBg => 'Plain, uncluttered background';

  @override
  String get tryOnGuideLighting => 'Bright, even lighting';

  @override
  String get tryOnGuideFaceCamera => 'Face the camera';

  @override
  String get tryOnGuideArms => 'Arms slightly away from your body';

  @override
  String get tryOnGuideOnePerson => 'Just you — one person only';

  @override
  String get tryOnGuideAvoid =>
      'Avoid close-ups, mirror cutoffs and group photos';

  @override
  String get tryOnUpgradeTitle => 'Unlock AI Realistic Try-On';

  @override
  String get tryOnUpgradeBody =>
      'Go Premium for HD results, realistic fabric and body fit, plus save, share and compare.';

  @override
  String get tryOnUpgradeCta => 'See Premium';

  @override
  String get tryOnUpgradeMaybe => 'Maybe later';

  @override
  String get tryOnHdToggle => 'Try-On Max (HD)';

  @override
  String get tryOnHdToggleSub => 'Sharper render · 4 credits (standard is 1)';

  @override
  String get tryOnHdLockedTitle => 'HD is a Pro Max feature';

  @override
  String get tryOnHdLockedBody =>
      'Upgrade to Pro Max for HD / Try-On Max renders — 4 credits each.';

  @override
  String get tryOnUpgradeForHd => 'Upgrade to Pro Max for HD.';

  @override
  String tryOnNeedCreditsHd(int count) {
    return 'You need $count credits for HD.';
  }

  @override
  String tryOnCostLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count credits',
      one: '1 credit',
    );
    return 'Costs $_temp0';
  }

  @override
  String get tryOnTopUp => 'Top Up';

  @override
  String get tryOnProgressFitting => 'Fitting the outfit…';

  @override
  String get tryOnProgressMatching => 'Matching body shape…';

  @override
  String get tryOnProgressRendering => 'Rendering your look…';

  @override
  String get tryOnProgressPreparing => 'Preparing your photo…';

  @override
  String get tryOnProgressGenerating => 'Generating your look…';

  @override
  String get tryOnProgressAlmost => 'Almost done…';

  @override
  String get tryOnProgressLongWait =>
      'Still working — high-quality looks take a moment.';

  @override
  String tryOnElapsed(int seconds) {
    return '${seconds}s';
  }

  @override
  String get tryOnSaveLook => 'Save look';

  @override
  String get tryOnPostCommunity => 'Post to Community';

  @override
  String get tryOnCompare => 'Compare';

  @override
  String get tryOnBefore => 'Before';

  @override
  String get tryOnAfter => 'After';

  @override
  String get tryOnLookSaved => 'Look saved to your history';

  @override
  String get tryOnLookSaveError =>
      'Couldn\'t save your look. Please try again.';

  @override
  String get tryOnChangePhoto => 'Change photo';

  @override
  String get tryOnSelectedLabel => 'Selected';

  @override
  String get tryOnStillPreparing =>
      'Still preparing this piece — try again in a moment.';

  @override
  String get communityCatForYou => 'For You';

  @override
  String get communityCatFollowing => 'Following';

  @override
  String get communityCatTrending => 'Trending';

  @override
  String get communityCatHijab => 'Hijab Style';

  @override
  String get communityCatCasual => 'Casual';

  @override
  String get communityCatWorkwear => 'Workwear';

  @override
  String get communityCatStreetwear => 'Streetwear';

  @override
  String get communityCatTravel => 'Travel';

  @override
  String get communityCatModest => 'Modest';

  @override
  String get communityCatMinimal => 'Minimal';

  @override
  String get communityCatWedding => 'Wedding';

  @override
  String get communityCatOffice => 'Office';

  @override
  String get communityChallengesTitle => 'Style Challenges';

  @override
  String get communityChallengesSeeAll => 'See all';

  @override
  String get communityLeaderboardCardSubtitle =>
      'See who\'s topping this month\'s Style Score.';

  @override
  String get studioTitle => 'Try-On Studio';

  @override
  String get studioAddPieces => 'Add pieces';

  @override
  String get studioYourOutfit => 'Your outfit';

  @override
  String get studioOutfitEmpty =>
      'Add tops, bottoms, shoes & accessories to build a look.';

  @override
  String get studioRemovePiece => 'Remove';

  @override
  String get studioLayersTitle => 'Layers';

  @override
  String get studioBringForward => 'Bring forward';

  @override
  String get studioSendBack => 'Send back';

  @override
  String get studioDeleteLayer => 'Delete layer';

  @override
  String get studioAddItem => 'Add item';

  @override
  String get studioSelectLayerHint =>
      'Tap a piece to move, resize, rotate or fade it';

  @override
  String get studioAiPrimaryNote =>
      'AI renders your main piece now — full-outfit AI is on the way.';

  @override
  String get studioAiFullOutfitNote =>
      'AI renders your full outfit — add your pieces and generate.';

  @override
  String tryOnTooManyGarments(int count) {
    return 'You can try on up to $count pieces at once. Remove a few and try again.';
  }

  @override
  String get studioGenerate2d => 'Build 2D outfit';

  @override
  String studioPiecesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pieces',
      one: '1 piece',
      zero: 'No pieces',
    );
    return '$_temp0';
  }

  @override
  String get postSave => 'Save';

  @override
  String get postSaved => 'Saved to your looks';

  @override
  String get postShare => 'Share';

  @override
  String get postTryThisLook => 'Try this look';

  @override
  String get postTryThisLookEmptyHint =>
      'Choose items from your wardrobe to recreate this look.';

  @override
  String get postShareText => 'Check out this look on Wear The Mood ✨';

  @override
  String get postShareCopied => 'Copied to clipboard — paste to share.';

  @override
  String get shareFailed => 'Couldn\'t open share. Please try again.';

  @override
  String closetWornCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Worn $count times',
      one: 'Worn once',
      zero: 'Not worn yet',
    );
    return '$_temp0';
  }

  @override
  String closetLastWorn(String date) {
    return 'Last worn $date';
  }

  @override
  String get composeDiscardTitle => 'Discard this post?';

  @override
  String get composeDiscardBody => 'Your caption and photo will be lost.';

  @override
  String get composeDiscardConfirm => 'Discard';

  @override
  String get composeKeepEditing => 'Keep editing';

  @override
  String get profileEditProfile => 'Edit profile';

  @override
  String get profileTabLooks => 'Looks';

  @override
  String get profileTabSaved => 'Saved';

  @override
  String get profileTabCloset => 'Closet';

  @override
  String get profileTabSettings => 'Settings';

  @override
  String get profileStatCloset => 'Closet';

  @override
  String get profileStatOutfits => 'Outfits';

  @override
  String get profileStatTryOns => 'Try-ons';

  @override
  String get profileStatSaved => 'Saved';

  @override
  String get profileLooksEmptyTitle => 'No looks yet';

  @override
  String get profileLooksEmptyMessage =>
      'Share an outfit and it\'ll show up here.';

  @override
  String get profileSavedEmptyTitle => 'Nothing saved yet';

  @override
  String get profileSavedEmptyMessage =>
      'Save looks you love from try-on and the community.';

  @override
  String get profileClosetEmptyMessage =>
      'Your closet preview will appear here.';

  @override
  String get profilePremiumBannerTitle => 'Fashion OS Premium';

  @override
  String get profilePremiumBannerSubtitle =>
      'Realistic AI try-on, unlimited outfits, HD exports and premium styling.';

  @override
  String get profilePremiumBannerCta => 'Upgrade';

  @override
  String get profileStyleTitle => 'Style';

  @override
  String get profileBodyPhoto => 'Body & try-on photo';

  @override
  String get profileTagCasual => 'Casual';

  @override
  String get profileTagModest => 'Modest';

  @override
  String get profileTagStreetwear => 'Streetwear';

  @override
  String get profileTagMinimal => 'Minimal';

  @override
  String get profileTagWorkwear => 'Workwear';

  @override
  String get pubProfileTitle => 'Profile';

  @override
  String get pubProfileFollow => 'Follow';

  @override
  String get pubProfileFollowing => 'Following';

  @override
  String get pubProfileMessage => 'Message';

  @override
  String get pubProfileMessageSoon => 'Direct messages are coming soon.';

  @override
  String get pubProfileStatLooks => 'Looks';

  @override
  String get pubProfileStatFollowers => 'Followers';

  @override
  String get pubProfileStatFollowing => 'Following';

  @override
  String get pubProfileTabLooks => 'Looks';

  @override
  String get pubProfileTabCloset => 'Closet';

  @override
  String get pubProfileTabAbout => 'About';

  @override
  String get pubProfileLooksEmptyTitle => 'No looks yet';

  @override
  String pubProfileLooksEmptyMessage(String name) {
    return 'When $name shares a look, it\'ll show up here.';
  }

  @override
  String get pubProfileClosetEmptyTitle => 'Nothing shared yet';

  @override
  String get pubProfileClosetEmptyMessage =>
      'This member hasn\'t shared any closet pieces.';

  @override
  String get pubProfileAboutBioEmpty => 'No bio yet.';

  @override
  String get pubProfileAboutStyleTitle => 'Style';

  @override
  String get pubProfileAboutStyleEmpty => 'No style tags yet.';

  @override
  String get pubProfileNotFoundTitle => 'Profile unavailable';

  @override
  String get pubProfileNotFoundMessage =>
      'This profile is private or no longer exists.';

  @override
  String get pubProfileViewProfile => 'View profile';

  @override
  String get pubProfileFollowError =>
      'Couldn\'t update follow. Please try again.';

  @override
  String get followListFollowersTitle => 'Followers';

  @override
  String get followListFollowingTitle => 'Following';

  @override
  String get followListEmptyFollowers => 'No followers yet';

  @override
  String get followListEmptyFollowing => 'Not following anyone yet';

  @override
  String get followListErrorTitle => 'Couldn\'t load that list';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsEmptyTitle => 'You\'re all caught up';

  @override
  String get notificationsEmptyMessage =>
      'Likes, comments, follows and try-on updates will show up here.';

  @override
  String get notificationsMarkAllRead => 'Mark all read';

  @override
  String get notificationsErrorTitle => 'Couldn\'t load notifications';

  @override
  String get notificationActionError => 'Couldn\'t update. Please try again.';

  @override
  String get accountShowClosetTitle => 'Show closet publicly';

  @override
  String get accountShowClosetSubtitle =>
      'Let others browse your closet pieces on your public profile.';

  @override
  String get creditsSheetTitle => 'Your try-on credits';

  @override
  String creditsSheetFreeLeft(int count) {
    return '$count free AI try-ons left';
  }

  @override
  String creditsSheetBalance(int count) {
    return '$count purchased credits';
  }

  @override
  String get creditsSheetReset =>
      'A one-time free trial. Upgrade for unlimited AI try-ons.';

  @override
  String get creditsSheetUpgrade => 'Get more with Premium';

  @override
  String get creditsSheetUnlimited =>
      'You\'re on Premium — enjoy your try-ons.';

  @override
  String get premiumComparisonTitle => 'Free · Pro · Pro Max';

  @override
  String get premiumCompareFree => 'Free';

  @override
  String get premiumComparePremium => 'Premium';

  @override
  String get premiumComparePro => 'Pro';

  @override
  String get premiumCompareProMax => 'Pro Max';

  @override
  String get premiumFeatureRealistic => 'AI Realistic Try-On';

  @override
  String get premiumFeatureHd => 'HD / Try-On Max';

  @override
  String get premiumFeatureSaveShare => 'Save & share looks';

  @override
  String get premiumFeaturePriority => 'Priority rendering';

  @override
  String get premiumFeatureCredits => 'AI realistic try-ons';

  @override
  String get premiumCreditsFree => '3 free';

  @override
  String get premiumCreditsPro => '75/mo';

  @override
  String get premiumCreditsProMax => '150/mo';

  @override
  String get premiumCreditsPremium => 'Unlimited';

  @override
  String get premiumFeatureWardrobe => 'Unlimited wardrobe';

  @override
  String get premiumFeatureDrawers => 'Wardrobe drawers';

  @override
  String get premiumDrawersFree => '3';

  @override
  String get premiumDrawersPremium => 'Unlimited';

  @override
  String get premiumFeatureEnhance => 'AI Enhance items';

  @override
  String get premiumFeatureCatalog => 'Catalog model shots';

  @override
  String get premiumFeatureStudioModels => 'Studio try-on models';

  @override
  String get premiumStudioFree => '2 free';

  @override
  String get premiumStudioAll => 'All';

  @override
  String get paywallActiveProTitle => 'You\'re on Pro';

  @override
  String get paywallActiveProMaxTitle => 'You\'re on Pro Max';

  @override
  String get paywallActiveProBody =>
      'You\'ve unlocked AI Enhance, catalog model shots, all studio models, 75 AI credits every month and unlimited wardrobe drawers.';

  @override
  String get paywallActiveProMaxBody =>
      'You\'ve unlocked everything: HD Try-On Max, catalog shots, all studio models, 150 AI credits every month, priority rendering and unlimited drawers.';

  @override
  String get paywallUpgradeProMax => 'Upgrade to Pro Max';

  @override
  String get paywallUpgradeProMaxSub =>
      'Add HD Try-On Max + double the credits (150/mo) + priority';

  @override
  String get paywallManageSub => 'Manage or cancel subscription';

  @override
  String get paywallManageUnavailable =>
      'Manage your plan in the Play Store subscriptions.';

  @override
  String get premiumRestore => 'Restore purchase';

  @override
  String get drawerLockedBadge => 'Premium';

  @override
  String get drawerLockedTapHint => 'Upgrade to Premium to open this drawer';

  @override
  String get catGroupTops => 'Tops';

  @override
  String get catGroupBottoms => 'Bottoms';

  @override
  String get catGroupOnePiece => 'One-piece';

  @override
  String get catGroupOuterwear => 'Outerwear';

  @override
  String get catGroupFootwear => 'Footwear';

  @override
  String get catGroupModest => 'Modest';

  @override
  String get catGroupAccessories => 'Bags & Accessories';

  @override
  String get catGroupLifestyle => 'Lifestyle';

  @override
  String get catGroupOther => 'Other';

  @override
  String get catTops => 'Tops';

  @override
  String get catTshirts => 'T-Shirts';

  @override
  String get catShirts => 'Shirts';

  @override
  String get catBlouses => 'Blouses';

  @override
  String get catTunics => 'Tunics/Kurtis';

  @override
  String get catBottoms => 'Bottoms';

  @override
  String get catPants => 'Pants';

  @override
  String get catJeans => 'Jeans';

  @override
  String get catSkirts => 'Skirts';

  @override
  String get catShorts => 'Shorts';

  @override
  String get catDresses => 'Dresses';

  @override
  String get catTraditional => 'Traditional';

  @override
  String get catOuterwear => 'Outerwear';

  @override
  String get catWinter => 'Winter';

  @override
  String get catShoes => 'Shoes';

  @override
  String get catHijab => 'Hijab';

  @override
  String get catScarves => 'Scarves';

  @override
  String get catBags => 'Bags';

  @override
  String get catEyewear => 'Eyewear';

  @override
  String get catJewelry => 'Jewelry';

  @override
  String get catBelts => 'Belts';

  @override
  String get catHats => 'Hats';

  @override
  String get catAccessories => 'Accessories';

  @override
  String get catActivewear => 'Activewear';

  @override
  String get catSleepwear => 'Sleepwear';

  @override
  String get catSwimwear => 'Swimwear';

  @override
  String get catWorkwear => 'Workwear';

  @override
  String get catParty => 'Party';

  @override
  String get catTravel => 'Travel';

  @override
  String get catOther => 'Other';

  @override
  String get catMore => 'More';

  @override
  String get catPickerTitle => 'Choose a category';

  @override
  String get catPickerSearchHint => 'Search categories';

  @override
  String get drawerSearchHint => 'Search drawers';

  @override
  String get drawerSearchEmpty => 'No drawers match';

  @override
  String get addItemPhotoHint =>
      'A clear photo of one clothing item works best';

  @override
  String get categorizeTitle => 'Edit details';

  @override
  String get categorizeNameLabel => 'Name';

  @override
  String get categorizeNameHint => 'e.g. White linen shirt';

  @override
  String get categorizeCategoryLabel => 'Category';

  @override
  String get categorizeColorLabel => 'Color';

  @override
  String get categorizeSave => 'Save changes';

  @override
  String get categorizeSaved => 'Item updated';

  @override
  String get categorizeError => 'Couldn\'t save changes';

  @override
  String get categorizeDrawerNone => 'No drawer';

  @override
  String get categorizeEditDetails => 'Edit details';

  @override
  String get categorizePromptBody =>
      'Add a category so this piece sorts into the right drawer.';

  @override
  String get categorizeAction => 'Categorize';

  @override
  String get closetNeedsCategory => 'Needs category';

  @override
  String get slotTop => 'Top';

  @override
  String get slotBottom => 'Bottom';

  @override
  String get slotDress => 'Dress';

  @override
  String get slotOuterwear => 'Outerwear';

  @override
  String get slotShoes => 'Shoes';

  @override
  String get slotBag => 'Bag';

  @override
  String get slotHijabScarf => 'Hijab / Scarf';

  @override
  String get slotEyewear => 'Eyewear';

  @override
  String get slotJewelry => 'Jewelry & accessories';

  @override
  String get outfitEditTitle => 'Edit outfit';

  @override
  String get outfitBuilderPickTitle => 'Build your look';

  @override
  String get outfitBuilderPickSubtitle =>
      'Add pieces to each slot to create a full outfit set.';

  @override
  String get outfitBuilderOtherPieces => 'Other pieces';

  @override
  String get outfitTryFullLook => 'Try full look';

  @override
  String get outfitUpdated => 'Outfit updated';

  @override
  String get outfitSlotAdd => 'Add a piece';

  @override
  String get outfitSlotRemove => 'Remove';

  @override
  String outfitPickForSlot(String slot) {
    return 'Choose a $slot';
  }

  @override
  String get outfitShowAll => 'Show all';

  @override
  String get outfitShowMatching => 'Show matching';

  @override
  String get outfitEditAction => 'Edit outfit';

  @override
  String get outfitDetailMissingTitle => 'Pieces no longer in your closet';

  @override
  String get outfitDetailMissingBody =>
      'The items in this outfit have been removed. Edit it to pick new pieces.';

  @override
  String get outfitFavorite => 'Add to favorites';

  @override
  String get outfitUnfavorite => 'Remove from favorites';

  @override
  String get profileStatFollowers => 'Followers';

  @override
  String get profileStatFollowing => 'Following';

  @override
  String get packingDestinationLabel => 'Destination';

  @override
  String get packingDestinationHint => 'City or country (optional)';

  @override
  String get packingClimateLabel => 'Climate';

  @override
  String get packingClimateHot => 'Hot';

  @override
  String get packingClimateCold => 'Cold';

  @override
  String get packingClimateRainy => 'Rainy';

  @override
  String get packingClimateMixed => 'Mixed';

  @override
  String get packingActivitiesLabel => 'Activities';

  @override
  String get packingActivityCasual => 'Casual';

  @override
  String get packingActivityWork => 'Work';

  @override
  String get packingActivityUniversity => 'University';

  @override
  String get packingActivityParty => 'Party';

  @override
  String get packingActivityBeach => 'Beach';

  @override
  String get packingActivityWedding => 'Wedding';

  @override
  String get packingActivityTravel => 'Travel day';

  @override
  String get packingLaundryLabel => 'Laundry access';

  @override
  String get packingLaundrySubtitle =>
      'Pack lighter — you can re-wash on the trip';

  @override
  String get packingModestLabel => 'Modest / hijab-friendly';

  @override
  String get packingModestSubtitle =>
      'Prioritise modest, hijab-friendly pieces';

  @override
  String packingPackedCount(int packed, int total) {
    return '$packed of $total packed';
  }

  @override
  String get packingMissingPieces =>
      'Your closet is a little light for this trip. Add a few versatile pieces and plan again.';

  @override
  String get packingGroupTops => 'Tops';

  @override
  String get packingGroupBottoms => 'Bottoms';

  @override
  String get packingGroupDresses => 'Dresses & tunics';

  @override
  String get packingGroupOuterwear => 'Outerwear';

  @override
  String get packingGroupShoes => 'Shoes';

  @override
  String get packingGroupBags => 'Bags';

  @override
  String get packingGroupHijab => 'Hijab & scarves';

  @override
  String get packingGroupAccessories => 'Accessories';

  @override
  String get packingGroupEssentials => 'Essentials';

  @override
  String get wtmNavHome => 'Home';

  @override
  String get wtmNavSocial => 'Social';

  @override
  String get wtmNavInbox => 'Inbox';

  @override
  String get wtmNavProfile => 'Profile';

  @override
  String get wtmNavOrb => 'Upload Hub';

  @override
  String get wtmUploadHubTitle => 'Upload Hub';

  @override
  String get wtmUploadHubSubtitle => 'What do you want to add?';

  @override
  String get wtmUploadGarmentTitle => 'Upload a Garment';

  @override
  String get wtmUploadGarmentSub => 'Add to your closet';

  @override
  String get wtmUploadBodyTitle => 'Upload Body Photo';

  @override
  String get wtmUploadBodySub => 'For try-on & better fit';

  @override
  String get wtmUploadLookTitle => 'Upload a Look';

  @override
  String get wtmUploadLookSub => 'Save a full outfit';

  @override
  String get wtmUploadBrandTitle => 'Brand & Store';

  @override
  String get wtmUploadBrandSub => 'Link a brand or store';

  @override
  String get wtmUploadTryonTitle => 'Try It On';

  @override
  String get wtmUploadTryonSub => 'AI try-on from any image';

  @override
  String get wtmAssistantEyebrow => 'Atelier assistant';

  @override
  String get wtmAssistantLine => 'I\'m here to help you style it.';

  @override
  String get wtmHomeTagline => 'Express your mood. Define your style.';

  @override
  String get wtmMoodEyebrow => 'Today\'s mood';

  @override
  String get wtmMoodCalm => 'Calm';

  @override
  String get wtmMoodConfident => 'Confident';

  @override
  String get wtmMoodBold => 'Bold';

  @override
  String get wtmMoodRebel => 'Rebel';

  @override
  String get wtmQaTryOn => 'Try-On\nStudio';

  @override
  String get wtmQaCloset => 'Smart\nCloset';

  @override
  String get wtmQaStylist => 'AI\nStylist';

  @override
  String get wtmQaOutfits => 'Outfit\nMaker';

  @override
  String get wtmTodaysLook => 'Today\'s look';

  @override
  String get wtmLookCalmA => 'Morning';

  @override
  String get wtmLookCalmB => 'Stillness';

  @override
  String get wtmLookConfidentA => 'Moonlit';

  @override
  String get wtmLookConfidentB => 'Confidence';

  @override
  String get wtmLookBoldA => 'Golden';

  @override
  String get wtmLookBoldB => 'Hour';

  @override
  String get wtmLookRebelA => 'Quiet';

  @override
  String get wtmLookRebelB => 'Rebellion';

  @override
  String wtmLookContext(String daypart) {
    return '$daypart · 22°C';
  }

  @override
  String get wtmDaypartMorning => 'Morning';

  @override
  String get wtmDaypartAfternoon => 'Afternoon';

  @override
  String get wtmDaypartEvening => 'Evening';

  @override
  String get wtmInspiration => 'Inspiration for you';

  @override
  String get wtmViewAll => 'View all';

  @override
  String get wtmDiscover => 'Discover';

  @override
  String get wtmDiscoverGiveaways => 'Giveaways';

  @override
  String get wtmDiscoverOffers => 'Offers';

  @override
  String get wtmDiscoverNewsroom => 'Newsroom';

  @override
  String get wtmClosetTitle => 'Smart Closet';

  @override
  String get wtmClosetStatItems => 'Items';

  @override
  String get wtmClosetStatOutfits => 'Outfits';

  @override
  String get wtmClosetStatFavorites => 'Favorites';

  @override
  String get wtmClosetStatCategories => 'Categories';

  @override
  String get wtmClosetEmptyTitle => 'Your atelier awaits';

  @override
  String get wtmClosetEmptyMessage =>
      'Digitize your first piece — background removed, tagged, and ready to try on.';

  @override
  String get wtmClosetEmptyCta => 'Add your first piece';

  @override
  String get wtmClosetErrorTitle => 'The closet didn\'t load';

  @override
  String get wtmClosetFilterTitle => 'Filter';

  @override
  String get wtmClosetSearchLabel => 'Search closet';

  @override
  String get wtmClosetAddLabel => 'Add a garment';

  @override
  String get wtmGarmentUntitled => 'New piece';

  @override
  String wtmGarmentWearStats(int count, String date) {
    return 'Worn $count times · last on $date';
  }

  @override
  String get wtmGarmentNeverWorn => 'Not worn yet';

  @override
  String get wtmGarmentTryOn => 'Try It On';

  @override
  String get wtmGarmentEdit => 'Edit';

  @override
  String get wtmGarmentDelete => 'Delete';

  @override
  String get wtmGarmentDeleteTitle => 'Delete this piece?';

  @override
  String get wtmGarmentDeleteMessage =>
      'It will be removed from your closet and outfits.';

  @override
  String get wtmGarmentDeleted => 'Removed from your closet.';

  @override
  String get wtmGarmentFavoriteAdd => 'Add to favorites';

  @override
  String get wtmGarmentFavoriteRemove => 'Remove from favorites';

  @override
  String get wtmGarmentEditTitle => 'Edit piece';

  @override
  String get wtmGarmentNameHint => 'Name this piece…';

  @override
  String get wtmGarmentSave => 'Save';

  @override
  String get wtmGarmentSaved => 'Saved.';

  @override
  String get wtmAddTitle => 'Add Garment';

  @override
  String get wtmAddCaptureEyebrow => 'Capture';

  @override
  String get wtmAddCaptureTitle => 'Add a piece to your closet';

  @override
  String get wtmAddCaptureMessage =>
      'Lay it flat or hang it against a clean background.';

  @override
  String get wtmAddTakePhoto => 'Take Photo';

  @override
  String get wtmAddFromGallery => 'Choose from Gallery';

  @override
  String get wtmAddProcessingEyebrow => 'Atelier at work';

  @override
  String get wtmAddProcessingHint =>
      'Cutting the silhouette free — a few seconds.';

  @override
  String get wtmAddConfirmEyebrow => 'Confirm';

  @override
  String get wtmAddConfirmTitle => 'Looking sharp';

  @override
  String get wtmAddConfirmMessage => 'Name it and confirm the category.';

  @override
  String get wtmAddSaveCta => 'Save to Closet';

  @override
  String get wtmAddSavedToast => 'Added to your closet.';

  @override
  String get wtmAddPickFailed => 'Couldn\'t read that photo — try another.';

  @override
  String get wtmMirrorTitle => 'MoodMirror';

  @override
  String wtmMirrorStep(int n) {
    return 'Step $n of 3';
  }

  @override
  String get wtmMirrorS1Title => 'Choose your body photo';

  @override
  String get wtmMirrorS1Sub => 'Great lighting. Front pose. Arms by side.';

  @override
  String get wtmMirrorS1Continue => 'Continue · Add Garments';

  @override
  String get wtmMirrorS1Upload => 'Upload Photo';

  @override
  String get wtmMirrorS1Gallery => 'Select from Gallery';

  @override
  String get wtmMirrorS1Update => 'Update photo';

  @override
  String get wtmMirrorS1PortalLabel => 'Body photo';

  @override
  String get wtmMirrorS1ErrorTitle => 'Your photos didn\'t load';

  @override
  String get wtmMirrorS2Title => 'Add garments or outfits';

  @override
  String get wtmMirrorS2Sub =>
      'Tap to add to your look — layers render in order.';

  @override
  String get wtmMirrorS2Next => 'Next · Choose Mode';

  @override
  String wtmMirrorS2NextCount(int n) {
    return 'Next · Choose Mode ($n)';
  }

  @override
  String get wtmMirrorS2Samples => 'Or try a sample piece';

  @override
  String get wtmMirrorS2EmptyTitle => 'Nothing to try on yet';

  @override
  String get wtmMirrorS2EmptyMessage =>
      'Add a piece to your closet, or start with a sample.';

  @override
  String get wtmMirrorS2AddCta => 'Add a garment';

  @override
  String wtmMirrorS2Max(int n) {
    return 'Up to $n pieces per look.';
  }

  @override
  String get wtmMirrorS3Title => 'Choose your try-on mode';

  @override
  String get wtmMirrorS3Sub => 'Each mode gives a unique result.';

  @override
  String get wtmMirrorMode2dTitle => '2D Try-On';

  @override
  String get wtmMirrorMode2dSub => 'Fast & free · on-device outfit stack';

  @override
  String get wtmMirrorModeAiTitle => 'AI Couture Try-On';

  @override
  String get wtmMirrorModeAiSub => 'Ultra realistic · advanced AI detail';

  @override
  String get wtmMirrorModeHdTitle => 'Full Look';

  @override
  String get wtmMirrorModeHdSub => 'Head-to-toe HD render · top of the line';

  @override
  String get wtmMirrorCreditsEyebrow => 'Your credits';

  @override
  String wtmMirrorCreditChip(int n) {
    return '$n credits';
  }

  @override
  String get wtmMirrorCreditChipOne => '1 credit';

  @override
  String get wtmMirrorGenerate => 'Generate Look';

  @override
  String get wtmMirrorOpen2d => 'Open 2D Studio';

  @override
  String wtmMirrorCostNote(int n) {
    return 'Uses $n credits · 2D mode is always free';
  }

  @override
  String get wtmMirrorCostNoteFree => '2D mode is always free';

  @override
  String get wtmMirrorNeedCredits => 'Not enough credits for this mode.';

  @override
  String get wtmMirrorGetCredits => 'Get credits';

  @override
  String get wtmMirrorHdLocked =>
      'Full Look renders in HD — a Pro Max exclusive.';

  @override
  String get wtmMirrorGenTitle1 => 'Draping the silhouette…';

  @override
  String get wtmMirrorGenTitle2 => 'Matching light and shadow…';

  @override
  String get wtmMirrorGenTitle3 => 'Weaving the final threads…';

  @override
  String get wtmMirrorGenHint =>
      'Usually under a minute. Credits are reserved and refunded if it fails.';

  @override
  String get wtmMirrorGenCancel => 'Cancel';

  @override
  String get wtmMirrorGenCancelNote =>
      'The render keeps finishing server-side — find it in your history.';

  @override
  String get wtmMirrorFailedTitle => 'The render didn\'t finish';

  @override
  String get wtmMirrorRetry => 'Retry';

  @override
  String get wtmMirrorResultTitle => 'Your look';

  @override
  String get wtmMirrorSaveLook => 'Save Look';

  @override
  String get wtmMirrorSaved => 'Saved to Looks';

  @override
  String get wtmMirrorSaveFailed =>
      'Couldn\'t save — check your connection and try again.';

  @override
  String get wtmMirrorAdjust => 'Adjust';

  @override
  String get wtmMirrorShare => 'Share';

  @override
  String get wtmMirrorShareText => 'Styled with Wear The Mood';

  @override
  String get wtmMirrorNoResultTitle => 'No look to show';

  @override
  String get wtmMirrorNoResultMessage =>
      'Generate a look first — it lands here.';

  @override
  String get wtmMirrorAdjustTitle => 'Adjust Your Look';

  @override
  String get wtmMirrorAdjustEyebrow => 'Refine every detail';

  @override
  String get wtmMirrorAdjustments => 'Adjustments';

  @override
  String get wtmMirrorReset => 'Reset';

  @override
  String get wtmMirrorDone => 'Done';

  @override
  String get wtmMirrorToolCrop => 'Crop';

  @override
  String get wtmMirrorToolRotate => 'Rotate';

  @override
  String get wtmMirrorToolErase => 'Erase';

  @override
  String get wtmMirrorToolSwap => 'Swap';

  @override
  String get wtmMirrorToolRetouch => 'Retouch';

  @override
  String get wtmMirrorToolBackdrop => 'Backdrop';

  @override
  String get wtmMirrorToolSoon =>
      'This tool arrives with the full studio pass.';

  @override
  String get wtmMirrorAdjBrightness => 'Brightness';

  @override
  String get wtmMirrorAdjContrast => 'Contrast';

  @override
  String get wtmMirrorAdjSaturation => 'Saturation';

  @override
  String get wtmMirrorAdjShadows => 'Shadows';

  @override
  String get wtmStylistTitle => 'AI Stylist';

  @override
  String get wtmStylistEyebrow => 'Atelier assistant';

  @override
  String get wtmStylistYourStylist => 'Your stylist';

  @override
  String get wtmStylistWeather => '22°C · clear';

  @override
  String wtmStylistMoodChip(String mood) {
    return '$mood mood';
  }

  @override
  String get wtmStylistContextTitle => 'Styling context';

  @override
  String get wtmStylistContextBody =>
      'Your stylist blends the time of day and the weather into today\'s fabric, layer and palette picks.';

  @override
  String get wtmStylistContextDaypart => 'Time of day';

  @override
  String get wtmStylistContextWeather => 'Weather';

  @override
  String get wtmStylistContextWeatherNote =>
      'Weather is estimated for styling context — live local weather lands in a later update.';

  @override
  String get wtmStylistMoodSheetTitle => 'Set the mood';

  @override
  String get wtmStylistMoodSheetNote =>
      'Slide to retune today\'s styling direction.';

  @override
  String get wtmStylistTryThis => 'Try This On';

  @override
  String get wtmStylistShuffle => 'Shuffle';

  @override
  String get wtmStylistOpenLook => 'Open look';

  @override
  String get wtmStylistEmptyTitle => 'Your closet is empty';

  @override
  String get wtmStylistEmptyMessage =>
      'Add a few pieces and I\'ll style them into looks for you.';

  @override
  String get wtmStylistEmptyCta => 'Add a garment';

  @override
  String get wtmStylistErrorTitle => 'The stylist is resting';

  @override
  String get wtmStylistLookEyebrow => 'Today\'s look';

  @override
  String get wtmStylistInsight => 'AI insight';

  @override
  String get wtmTryOnNoImage =>
      'These pieces are still processing — try again shortly.';

  @override
  String get wtmOutfitsTitle => 'Outfit Maker';

  @override
  String get wtmOutfitsEyebrow => 'Saved outfits & composer';

  @override
  String get wtmOutfitsSaved => 'Saved outfits';

  @override
  String get wtmOutfitsErrorTitle => 'Your outfits didn\'t load';

  @override
  String get wtmOutfitsEmptyMessage =>
      'No saved outfits yet — compose one below.';

  @override
  String get wtmOutfitsComposer => 'Composer';

  @override
  String get wtmOutfitsComposerHint =>
      'Tap a slot, then pick a piece below. Re-tap to clear.';

  @override
  String get wtmOutfitsUntitled => 'Untitled look';

  @override
  String wtmOutfitPieces(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n pieces',
      one: '1 piece',
    );
    return '$_temp0';
  }

  @override
  String get wtmOutfitSlotTop => 'Top';

  @override
  String get wtmOutfitSlotBottom => 'Bottom';

  @override
  String get wtmOutfitSlotLayer => 'Layer';

  @override
  String get wtmOutfitSlotExtra => 'Extra';

  @override
  String get wtmOutfitsPickFirst => 'Pick a piece for at least one slot first.';

  @override
  String get wtmOutfitsNoCloset => 'Your closet is empty.';

  @override
  String get wtmOutfitsNameHint => 'Name this look…';

  @override
  String get wtmOutfitsUpdate => 'Update Outfit';

  @override
  String get wtmOutfitsSave => 'Save Outfit';

  @override
  String get wtmOutfitsSavedSnack => 'Outfit saved';

  @override
  String get wtmOutfitsSaveFailed =>
      'Couldn\'t save — check your connection and try again.';

  @override
  String get wtmOutfitDetailEyebrow => 'Outfit';

  @override
  String get wtmOutfitTryOn => 'Try It On';

  @override
  String get wtmOutfitEdit => 'Edit';

  @override
  String get wtmOutfitEditing => 'Editing — pick pieces and save.';

  @override
  String get wtmOutfitDelete => 'Delete';

  @override
  String get wtmOutfitDeleteTitle => 'Delete this outfit?';

  @override
  String get wtmOutfitDeleteMessage => 'The garments stay in your closet.';

  @override
  String get wtmOutfitDeleted => 'Outfit deleted';

  @override
  String get wtmOutfitMissingTitle => 'These pieces are gone';

  @override
  String get wtmOutfitMissingMessage =>
      'The garments in this outfit were removed from your closet.';

  @override
  String get wtmPaywallTitle => 'Atelier Membership';

  @override
  String get wtmPaywallEyebrow => 'Unlock the full mirror';

  @override
  String get wtmPaywallHead1 => 'Wear it';

  @override
  String get wtmPaywallHeadEmph => 'before';

  @override
  String get wtmPaywallHead2 => 'you own it';

  @override
  String get wtmPaywallFree => 'Free';

  @override
  String get wtmPaywallPro => 'Pro';

  @override
  String get wtmPaywallProMax => 'Pro Max';

  @override
  String get wtmPaywallFreeB1 => '3 free try-ons a day';

  @override
  String get wtmPaywallFreeB2 => '2D on-device studio';

  @override
  String get wtmPaywallProB1 => '75 AI credits every month';

  @override
  String get wtmPaywallProB2 => 'AI Couture try-on';

  @override
  String get wtmPaywallProB3 => 'Priority render queue';

  @override
  String get wtmPaywallMaxB1 => '150 credits every month';

  @override
  String get wtmPaywallMaxB2 => 'Full Look — HD Try-On Max';

  @override
  String get wtmPaywallMaxB3 => 'Top-priority queue';

  @override
  String get wtmPaywallPopular => 'Best value';

  @override
  String get wtmPaywallPerMonth => '/mo';

  @override
  String get wtmPaywallContinue => 'Continue';

  @override
  String get wtmPaywallRestore => 'Restore Purchases';

  @override
  String get wtmPaywallTerms => 'Auto-renews monthly · cancel anytime';

  @override
  String get wtmPaywallPrivacy => 'Privacy';

  @override
  String get wtmPaywallTermsLink => 'Terms';

  @override
  String get wtmPaywallSuccess => 'Welcome to the Atelier.';

  @override
  String get wtmPaywallSetup =>
      'Memberships open soon — AI try-on runs on your daily free credits.';

  @override
  String get wtmPaywallError =>
      'That purchase didn\'t complete. Please try again.';

  @override
  String get wtmPaywallRestored => 'Your membership is restored.';

  @override
  String get wtmPaywallRestoreNothing => 'No purchases to restore.';

  @override
  String get wtmPaywallMemberTitle => 'You\'re an Atelier member';

  @override
  String get wtmPaywallMemberSub =>
      'Unlimited AI try-on and the full mirror are yours.';

  @override
  String get wtmPaywallManage => 'Manage subscription';

  @override
  String get wtmTopupTitle => 'Your credits';

  @override
  String get wtmTopupSubtitle =>
      'AI try-ons draw from your daily free credits and any membership pool.';

  @override
  String get wtmTopupBalance => 'Current balance';

  @override
  String wtmTopupFreeLeft(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n free try-ons left today',
      one: '1 free try-on left today',
    );
    return '$_temp0';
  }

  @override
  String get wtmTopupReset =>
      'Free try-ons reset each day. Become a member for a monthly credit pool.';

  @override
  String get wtmTopupUnlimited =>
      'You\'re a member — enjoy your monthly credits.';

  @override
  String get wtmTopupGetMore => 'Get more credits';

  @override
  String get wtmSettingsTitle => 'Settings';

  @override
  String get wtmSettingsEyebrow => 'Preferences & account';

  @override
  String get wtmSettingsAccount => 'Account';

  @override
  String get wtmSettingsAccountSub => 'Name, bio & style';

  @override
  String get wtmSettingsPrefs => 'Preferences';

  @override
  String get wtmSettingsPrefsSub => 'App behavior & language';

  @override
  String get wtmSettingsNotifs => 'Notifications';

  @override
  String get wtmSettingsNotifsSub => 'Manage your alerts';

  @override
  String get wtmSettingsSubscription => 'Subscription';

  @override
  String get wtmSettingsSubscriptionSub => 'Manage & restore';

  @override
  String get wtmSettingsPrivacy => 'Privacy & data';

  @override
  String get wtmSettingsPrivacySub => 'Export your data';

  @override
  String get wtmSettingsExportDone => 'Your data was copied to the clipboard.';

  @override
  String get wtmSettingsExportError =>
      'Couldn\'t export right now. Please try again.';

  @override
  String get wtmSettingsLegal => 'Legal';

  @override
  String get wtmSettingsLegalSub => 'Privacy Policy & Terms';

  @override
  String get wtmSettingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get wtmSettingsTerms => 'Terms of Service';

  @override
  String get wtmSettingsHelp => 'Help & Support';

  @override
  String get wtmSettingsHelpSub => 'FAQs & contact';

  @override
  String get wtmSettingsMore => 'More controls arrive in a later update.';

  @override
  String get wtmSettingsDelete => 'Delete Account';

  @override
  String get wtmSettingsDeleteSub => 'Erase account & data';

  @override
  String get wtmSettingsDelete1Title => 'Delete your account?';

  @override
  String get wtmSettingsDelete1Body =>
      'Your closet, looks, outfits, and posts will be erased.';

  @override
  String get wtmSettingsDelete1Confirm => 'Continue';

  @override
  String get wtmSettingsDelete2Title => 'This is permanent';

  @override
  String get wtmSettingsDelete2Body =>
      'There\'s no way back. Delete everything?';

  @override
  String get wtmSettingsDelete2Confirm => 'Delete forever';

  @override
  String get wtmSettingsDeleteDone => 'Your account was deleted.';

  @override
  String get wtmSettingsDeleteError =>
      'Couldn\'t delete right now. Please try again.';

  @override
  String get wtmSettingsSignOut => 'Sign Out';

  @override
  String get wtmSettingsSignOutTitle => 'Sign out?';

  @override
  String get wtmSettingsSignOutBody => 'You can sign back in any time.';

  @override
  String get wtmSettingsBodyPhoto => 'Body photo';

  @override
  String get wtmSettingsBodyPhotoTitle => 'Your try-on photo';

  @override
  String get wtmSettingsBodyPhotoSub => 'Used for fit & AI try-on';

  @override
  String get wtmSettingsUpdate => 'Update';

  @override
  String get wtmSettingsVersion => 'Wear The Mood · Atelier';

  @override
  String get wtmProfileTitle => 'Profile';

  @override
  String get wtmProfileMenu => 'Profile menu';

  @override
  String get wtmProfileSavedPosts => 'Saved posts';

  @override
  String get wtmProfileSignedOutTitle => 'Sign in to see your profile';

  @override
  String get wtmProfileSignedOutMessage =>
      'Your closet, looks, and style live here once you\'re signed in.';

  @override
  String get wtmProfileYou => 'You';

  @override
  String get wtmProfileEyebrow => 'Atelier member';

  @override
  String get wtmProfileEdit => 'Edit Profile';

  @override
  String get wtmProfileFollowers => 'Followers';

  @override
  String get wtmProfileFollowing => 'Following';

  @override
  String get wtmProfileItems => 'Items';

  @override
  String get wtmProfileOutfits => 'Outfits';

  @override
  String get wtmProfileStyleDna => 'Style DNA';

  @override
  String get wtmProfileSegCloset => 'Closet';

  @override
  String get wtmProfileSegLooks => 'Looks';

  @override
  String get wtmProfileSegPosts => 'Posts';

  @override
  String get wtmProfileMyCloset => 'My closet';

  @override
  String get wtmProfileMyLooks => 'Saved looks';

  @override
  String get wtmProfileMyPosts => 'My posts';

  @override
  String get wtmProfileMembership => 'Atelier membership';

  @override
  String get wtmProfileMembershipSub => 'Manage your plan & credits';

  @override
  String get wtmProfileEmptyCloset => 'Your closet is empty — add a piece.';

  @override
  String get wtmProfileEmptyLooks => 'No saved looks yet.';

  @override
  String get wtmProfileEmptyPosts =>
      'Share your first look with the community.';

  @override
  String get wtmEditTitle => 'Edit Profile';

  @override
  String get wtmEditEyebrow => 'Account';

  @override
  String get wtmEditNameHint => 'Your name';

  @override
  String get wtmEditBioHint => 'Bio — a line about your style';

  @override
  String get wtmEditTagsHint => 'Style tags — romantic, street, bold';

  @override
  String get wtmEditTagsNote => 'Comma-separated. These seed your Style DNA.';

  @override
  String get wtmEditPublicTitle => 'Public profile';

  @override
  String get wtmEditPublicSub => 'Others can find and follow you';

  @override
  String get wtmEditSave => 'Save';

  @override
  String get wtmEditSaved => 'Profile updated';

  @override
  String get wtmEditError =>
      'Couldn\'t save — check your connection and try again.';

  @override
  String get wtmLooksTitle => 'Saved Looks';

  @override
  String get wtmLooksEyebrow => 'Your renders';

  @override
  String get wtmLooksView => 'View look';

  @override
  String get wtmTodaysLookEmptyMessage =>
      'Your closet is empty — add pieces and the stylist will dress you here.';

  @override
  String get wtmTodaysLookEmptyCta => 'Add a piece';

  @override
  String get wtmInspirationEmptyMessage =>
      'Save a look or build an outfit — your inspiration lands here.';

  @override
  String get wtmInspirationEmptyCta => 'Open MoodMirror';

  @override
  String get wtmInspirationErrorMessage => 'Inspiration didn\'t load.';

  @override
  String get wtmProfilePhotoChange => 'Change photo';

  @override
  String get wtmProfilePhotoTitle => 'Profile photo';

  @override
  String get wtmProfilePhotoView => 'View photo';

  @override
  String get wtmPhotoCropTitle => 'Adjust your photo';

  @override
  String get wtmPhotoCropHint => 'Pinch and drag until it fits the frame.';

  @override
  String get wtmPhotoCropUse => 'Use photo';

  @override
  String get wtmMirrorBackToStyling => 'Back to styling';

  @override
  String get wtmEnhanceProgress => 'Enhancing with AI…';

  @override
  String get wtmEnhanceDone =>
      'Enhanced — your piece got the studio treatment.';

  @override
  String get wtmEnhanceFailedTitle => 'Enhance didn\'t finish';

  @override
  String get wtmMirrorSaving => 'Saving…';

  @override
  String get wtmSharePreparing => 'Preparing…';

  @override
  String get wtmComposePublishing => 'Publishing…';

  @override
  String get wtmPhotoSaving => 'Saving your photo…';

  @override
  String get wtmCreditsCheckFailed =>
      'Couldn\'t check your plan — pull down to retry or try again.';

  @override
  String get wtmLooksEmptyTitle => 'No looks yet';

  @override
  String get wtmLooksEmptyMessage =>
      'Generate a try-on and save it — it lands here.';

  @override
  String get wtmLooksEmptyCta => 'Open MoodMirror';

  @override
  String get wtmTimeNow => 'now';

  @override
  String wtmTimeMinutes(int n) {
    return '${n}m';
  }

  @override
  String wtmTimeHours(int n) {
    return '${n}h';
  }

  @override
  String wtmTimeDays(int n) {
    return '${n}d';
  }

  @override
  String get wtmReportTitle => 'Report or block';

  @override
  String get wtmReportSubtitle => 'Reports reach our moderation team.';

  @override
  String get wtmReportInappropriate => 'Inappropriate content';

  @override
  String get wtmReportSpam => 'Spam or scam';

  @override
  String get wtmReportHarassment => 'Harassment';

  @override
  String get wtmReportOther => 'Something else';

  @override
  String get wtmReportDone => 'Report submitted — thank you.';

  @override
  String get wtmReportError => 'Couldn\'t do that right now. Please try again.';

  @override
  String get wtmBlockUser => 'Block user';

  @override
  String get wtmBlockUserSub => 'Hides their content immediately';

  @override
  String get wtmBlockDone => 'User blocked.';

  @override
  String get wtmSocialTitle => 'Community';

  @override
  String get wtmSocialSearch => 'Search community';

  @override
  String get wtmSocialComingTitle => 'Community is on its way';

  @override
  String get wtmSocialComingMessage =>
      'The feed, challenges, and OOTD sharing arrive soon.';

  @override
  String get wtmSocialForYou => 'For You';

  @override
  String get wtmSocialFollowing => 'Following';

  @override
  String get wtmSocialNew => 'New';

  @override
  String get wtmSocialNearYou => 'Near You';

  @override
  String get wtmSocialNearYouNote =>
      'Near You uses your location — it falls back to For You without it.';

  @override
  String get wtmSocialErrorTitle => 'The feed didn\'t load';

  @override
  String get wtmSocialEmptyTitle => 'No posts yet';

  @override
  String get wtmSocialEmptyMessage =>
      'Be the first to share a look with the community.';

  @override
  String get wtmSocialShare => 'Share a look';

  @override
  String get wtmSocialSomeone => 'Someone';

  @override
  String get wtmSocialPostOptions => 'Post options';

  @override
  String get wtmSocialSave => 'Save post';

  @override
  String get wtmOwnPostTitle => 'Your post';

  @override
  String get wtmOwnPostSubtitle => 'Manage what you shared.';

  @override
  String get wtmOwnPostView => 'View post';

  @override
  String get wtmOwnPostEdit => 'Edit caption';

  @override
  String get wtmOwnPostEditHint => 'Update your caption…';

  @override
  String get wtmOwnPostEditSave => 'Save';

  @override
  String get wtmOwnPostEditSaved => 'Caption updated.';

  @override
  String get wtmOwnPostDelete => 'Delete post';

  @override
  String get wtmOwnPostDeleteConfirmTitle => 'Delete this post?';

  @override
  String get wtmOwnPostDeleteConfirmBody =>
      'It disappears from the community for everyone. This can\'t be undone.';

  @override
  String get wtmOwnPostDeleted => 'Post deleted.';

  @override
  String get wtmPostTitle => 'Post';

  @override
  String get wtmPostComments => 'Comments';

  @override
  String get wtmPostCommentsError => 'Comments didn\'t load.';

  @override
  String get wtmPostNoComments => 'No comments yet — say something kind.';

  @override
  String get wtmPostAddComment => 'Add a comment…';

  @override
  String get wtmPostSend => 'Post';

  @override
  String get wtmCommentDone => 'Comment posted.';

  @override
  String get wtmCommentError =>
      'Couldn\'t post your comment. Please try again.';

  @override
  String get wtmComposeTitle => 'Create Post';

  @override
  String get wtmComposeEyebrow => 'Share a look';

  @override
  String get wtmComposePick => 'Pick a look';

  @override
  String get wtmComposePickFirst => 'Pick a look to share first.';

  @override
  String get wtmComposeCaption => 'Write a caption…';

  @override
  String get wtmComposePublish => 'Publish';

  @override
  String get wtmComposeModerationNote =>
      'Publishes instantly — content that breaks the rules is blocked.';

  @override
  String get wtmComposeDone => 'Posted — it\'s live in the community.';

  @override
  String get wtmComposeError =>
      'Couldn\'t publish right now. Please try again.';

  @override
  String get wtmComposeEmptyTitle => 'No looks to share yet';

  @override
  String get wtmComposeEmptyMessage =>
      'Generate and save a try-on look, then share it here.';

  @override
  String get wtmComposeEmptyCta => 'Open MoodMirror';

  @override
  String get wtmComposeModeLook => 'Look';

  @override
  String get wtmComposeModeText => 'Text';

  @override
  String get wtmComposeModePoll => 'Poll';

  @override
  String get wtmComposeLooksEyebrow => 'Saved looks';

  @override
  String get wtmComposeOutfitsEyebrow => 'Your outfits';

  @override
  String get wtmComposeSharedEyebrow => 'Sharing';

  @override
  String get wtmComposeTextHint => 'Share a thought with the community…';

  @override
  String get wtmComposeTextFirst => 'Write something to share first.';

  @override
  String get wtmComposePollNote =>
      'Polls post without a photo — the community votes right on the card.';

  @override
  String get wtmShareLook => 'Share Look';

  @override
  String get wtmComposeChoose => 'Choose picture or look';

  @override
  String get wtmComposeSourceCloset => 'Closet';

  @override
  String get wtmComposeSourceOutfits => 'Outfits';

  @override
  String get wtmComposeSourceLooks => 'Looks';

  @override
  String get wtmComposeFromGallery => 'Gallery';

  @override
  String get wtmComposeFromCamera => 'Camera';

  @override
  String get wtmComposePreviewEyebrow => 'Preview';

  @override
  String get wtmComposeNoPreview =>
      'Pick a piece, outfit or look — or upload a photo — to share.';

  @override
  String get wtmComposeSourceEmpty =>
      'Nothing here yet — try another source or upload a photo.';

  @override
  String get wtmComposeGenerateLook => 'Generate a look with MoodMirror';

  @override
  String get wtmComposeUploadFailed =>
      'Couldn\'t prepare your photo. Please try again.';

  @override
  String get wtmUserTitle => 'Profile';

  @override
  String get wtmUserOptions => 'Profile options';

  @override
  String get wtmUserErrorTitle => 'This profile didn\'t load';

  @override
  String get wtmUserPosts => 'Posts';

  @override
  String get wtmUserNoPosts => 'No posts yet.';

  @override
  String get wtmFollow => 'Follow';

  @override
  String get wtmFollowing => 'Following';

  @override
  String get wtmFollowError => 'Couldn\'t update follow. Please try again.';

  @override
  String get wtmFollowEmptyTitle => 'No one here yet';

  @override
  String get wtmFollowEmptyMessage =>
      'When there are people, they\'ll show up here.';

  @override
  String get wtmSavedPostsTitle => 'Saved posts';

  @override
  String get wtmSavedPostsEyebrow => 'Bookmarks';

  @override
  String get wtmSavedPostsEmptyTitle => 'Nothing saved yet';

  @override
  String get wtmSavedPostsEmptyMessage =>
      'Tap the bookmark on a post to save it here.';

  @override
  String get wtmInboxTitle => 'Inbox';

  @override
  String get wtmInboxActivity => 'Activity';

  @override
  String get wtmInboxDrops => 'Drops';

  @override
  String get wtmInboxSystem => 'System';

  @override
  String get wtmInboxErrorTitle => 'Your inbox didn\'t load';

  @override
  String get wtmInboxEmptyTitle => 'Nothing here yet';

  @override
  String get wtmInboxEmptyMessage =>
      'Likes, drops, and updates will show up here.';

  @override
  String get wtmGiveawaysTitle => 'Giveaways';

  @override
  String get wtmGiveawaysErrorTitle => 'Giveaways didn\'t load';

  @override
  String get wtmGiveawaysEmptyTitle => 'No giveaways right now';

  @override
  String get wtmGiveawaysEmptyMessage =>
      'Check back soon — members share pieces here.';

  @override
  String get wtmGiveawayOpen => 'Open';

  @override
  String get wtmGiveawayClosed => 'Closed';

  @override
  String get wtmGiveawayMember => 'A member';

  @override
  String wtmGiveawayInterested(int n) {
    return '$n interested';
  }

  @override
  String get wtmGiveawayEnter => 'Enter Now';

  @override
  String get wtmGiveawayEntered => 'You\'re entered — good luck!';

  @override
  String get wtmGiveawayEnteredPill => 'Entered — good luck';

  @override
  String get wtmGiveawayRules =>
      'One entry per member. The owner picks a winner at close — you\'ll hear in Inbox · Drops.';

  @override
  String get wtmOffersTitle => 'Offers';

  @override
  String get wtmOffersErrorTitle => 'Offers didn\'t load';

  @override
  String get wtmOffersEmptyTitle => 'No offers today';

  @override
  String get wtmOffersEmptyMessage => 'New brand offers land here daily.';

  @override
  String get wtmOfferEyebrow => 'Offer';

  @override
  String get wtmOfferGoneTitle => 'This offer expired';

  @override
  String get wtmOfferGoneMessage =>
      'It\'s no longer available. Browse today\'s offers.';

  @override
  String get wtmOfferShopNow => 'Shop Now';

  @override
  String get wtmOfferExternalNote => 'Opens the brand\'s site externally.';

  @override
  String get wtmNewsTitle => 'Newsroom';

  @override
  String get wtmNewsErrorTitle => 'The newsroom didn\'t load';

  @override
  String get wtmNewsEmptyTitle => 'No stories yet';

  @override
  String get wtmNewsEmptyMessage => 'Fashion news lands here as it breaks.';

  @override
  String get wtmNewsMore => 'More stories';

  @override
  String get wtmNewsRead => 'Read More';

  @override
  String get wtmArticleEyebrow => 'Article';

  @override
  String get wtmArticleGoneTitle => 'This story moved on';

  @override
  String get wtmArticleGoneMessage =>
      'It\'s no longer in the feed. Back to the newsroom.';

  @override
  String get wtmArticleNoSummary => 'Open the full story for the details.';

  @override
  String wtmArticleReadOn(String source) {
    return 'Read on $source';
  }

  @override
  String get wtmArticleFromCloset => 'From your closet';

  @override
  String get wtmSearchTitle => 'Search';

  @override
  String get wtmSearchCloset => 'Closet';

  @override
  String get wtmSearchCommunity => 'Community';

  @override
  String get wtmSearchBrands => 'Brands';

  @override
  String get wtmSearchHint => 'Search closet, community, brands…';

  @override
  String get wtmSearchRecent => 'Recent';

  @override
  String get wtmSearchResults => 'Results';

  @override
  String get wtmSearchPrompt =>
      'Type to search your closet, the community, and brands.';

  @override
  String get wtmSearchNoResults => 'No matches — try another word.';

  @override
  String get wtmSearchUntitled => 'Untitled piece';

  @override
  String get wtmSplashTagline => 'Express your mood. Define your style.';

  @override
  String get wtmAuthSignInTitle => 'Welcome back';

  @override
  String get wtmAuthCreateTitle => 'Create your atelier';

  @override
  String get wtmAuthSubtitle => 'Your personal fashion OS.';

  @override
  String get wtmAuthEmail => 'Email';

  @override
  String get wtmAuthPassword => 'Password';

  @override
  String get wtmAuthSignIn => 'Sign In';

  @override
  String get wtmAuthCreate => 'Create Account';

  @override
  String get wtmAuthForgot => 'Forgot password?';

  @override
  String get wtmAuthOr => 'or';

  @override
  String get wtmAuthGoogle => 'Continue with Google';

  @override
  String get wtmAuthApple => 'Continue with Apple';

  @override
  String get wtmAuthAppleSoon => 'Apple Sign-In arrives at iOS launch.';

  @override
  String get wtmAuthHaveAccount => 'Already have an account? Sign in';

  @override
  String get wtmAuthNeedAccount => 'New here? Create an account';

  @override
  String get wtmAuthLegal => 'By continuing you agree to our';

  @override
  String get wtmAuthCheckEmail => 'Check your email to confirm your account.';

  @override
  String get wtmAuthAlready => 'That email is registered — sign in instead.';

  @override
  String get wtmAuthEnterEmail => 'Enter your email first.';

  @override
  String get wtmAuthResetSent => 'Password reset sent — check your email.';

  @override
  String get wtmObSkip => 'Skip';

  @override
  String get wtmObNext => 'Next';

  @override
  String get wtmObEnter => 'Enter Wear The Mood';

  @override
  String get wtmObMoodTitle => 'How do you feel today?';

  @override
  String get wtmObMoodSub =>
      'Set your baseline — we\'ll tune your looks to it.';

  @override
  String get wtmObTagsTitle => 'Your style';

  @override
  String get wtmObTagsSub => 'Pick a few — they seed your Style DNA.';

  @override
  String get wtmObBodyTitle => 'Try clothes on you';

  @override
  String get wtmObBodySub =>
      'Add a full-body photo to see garments on yourself — you can do this later.';

  @override
  String get wtmObBodyAdd => 'Add a photo';
}
