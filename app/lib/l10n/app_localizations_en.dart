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
  String get tryOnOutOfCredits => 'You\'re out of free try-ons for today.';

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
  String get addItemSaved => 'Added to your closet';

  @override
  String get addItemError => 'Couldn\'t add that. Please try again.';

  @override
  String get addItemPickError => 'Couldn\'t load that photo. Try another.';

  @override
  String get wardrobeProcessing => 'Processing';

  @override
  String get wardrobeRemovingBackground => 'Removing background';

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
      'Your full style OS — unlimited try-ons, wardrobe and your AI stylist.';

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
      'Free includes a few AI try-ons a day with credits — Premium is unlimited.';

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
  String get tryOn2dDone => 'Done';

  @override
  String get tryOn2dReset => 'Reset';

  @override
  String get tryOn2dFlip => 'Flip';

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
  String get tryOnChangePhoto => 'Change photo';

  @override
  String get tryOnSelectedLabel => 'Selected';

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
    return '$count free try-ons left today';
  }

  @override
  String creditsSheetBalance(int count) {
    return '$count purchased credits';
  }

  @override
  String get creditsSheetReset => 'Free try-ons refresh every day.';

  @override
  String get creditsSheetUpgrade => 'Get more with Premium';

  @override
  String get creditsSheetUnlimited =>
      'You\'re on Premium — enjoy your try-ons.';

  @override
  String get premiumComparisonTitle => 'Free vs Premium';

  @override
  String get premiumCompareFree => 'Free';

  @override
  String get premiumComparePremium => 'Premium';

  @override
  String get premiumFeatureRealistic => 'AI Realistic Try-On';

  @override
  String get premiumFeatureHd => 'HD results';

  @override
  String get premiumFeatureSaveShare => 'Save & share looks';

  @override
  String get premiumFeaturePriority => 'Priority rendering';

  @override
  String get premiumFeatureCredits => 'More daily try-ons';

  @override
  String get premiumFeatureWardrobe => 'Unlimited wardrobe';

  @override
  String get premiumFeatureDrawers => 'Wardrobe drawers';

  @override
  String get premiumDrawersFree => '3';

  @override
  String get premiumDrawersPremium => 'Unlimited';

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
}
